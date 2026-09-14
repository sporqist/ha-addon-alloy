#!/usr/bin/env bash
# End-to-end test of the add-on image UNDER ITS APPARMOR PROFILE, in enforce
# mode, against a real journal and a real Loki. This is the gate that lets
# dependency bumps merge without a human: a new Alloy that needs a path the
# profile does not grant fails here, on the runner, not inside a household's
# Home Assistant.
#
# Proves, in order:
#   0. the image carries the Alloy version config.yaml promises
#   1. the profile parses and loads (apparmor_parser)
#   2. with DEFAULT options: the container is healthy, a line written to the
#      runner's journal arrives in Loki under job="systemd-journal" with exactly
#      the default label set, and no detail field leaked into the labels
#   3. with OPINIONATED options (custom job, more labels, structured metadata,
#      level_from_message): the config validates under the profile and the line
#      arrives under the custom job with the extra labels present
#   4. the kernel logged ZERO apparmor DENIED (or ALLOWED) events for the profile
#
# Usage: e2e.sh <image> <loki-url-as-seen-from-the-container> <loki-url-as-seen-from-the-runner>
#
# E2E_LOCAL=1 runs the same script on a machine without AppArmor or journald
# (Docker Desktop, WSL): steps 1 and 4 are skipped, a stub journal directory
# is mounted, the probe is pushed to Loki from inside the container rather
# than written to a journal, and label assertions are skipped (no real journal
# fields exist). Run it before every push - it catches everything except the
# profile itself and the label shape.
set -euo pipefail

IMAGE="${1:?image}"
LOKI_PUSH="${2:?loki push url for the container}"
LOKI_QUERY="${3:?loki base url for the runner}"
LOCAL="${E2E_LOCAL:-}"
PROFILE_SRC="alloy/apparmor.txt"
NAME="alloy-e2e"
RUN_ID="${GITHUB_RUN_ID:-local}"

say() { printf '\n== %s\n' "$*"; }
aa_events() {
  [ -n "$LOCAL" ] && return 0
  sudo journalctl -k --since "-15min" -o cat | grep -E 'apparmor="(DENIED|ALLOWED|AUDIT)"' | grep -E 'ci_alloy|alloy_bin' || true
}
fail() {
  printf '\n!! %s\n' "$*"
  printf -- '-- container log (tail) --\n'; docker logs "$NAME" 2>&1 | tail -40 || true
  printf -- '-- apparmor events for the profile --\n'; aa_events
  printf -- '-- docker security --\n'; docker info --format '{{json .SecurityOptions}}' 2>/dev/null || true
  exit 1
}

# start_addon <options-json>: (re)start the container with these options and
# wait for its HEALTHCHECK.
DATA="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/addon-data"
start_addon() {
  rm -rf "$DATA"; mkdir -p "$DATA"; chmod 777 "$DATA"
  printf '%s' "$1" > "$DATA/options.json"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  local journal_mounts=() security=()
  if [ -n "$LOCAL" ]; then
    mkdir -p "$DATA/journal"
    journal_mounts+=(-v "$DATA/journal:/var/log/journal:ro")
  else
    [ -d /var/log/journal ] && journal_mounts+=(-v /var/log/journal:/var/log/journal:ro)
    [ -d /run/log/journal ] && journal_mounts+=(-v /run/log/journal:/run/log/journal:ro)
    [ ${#journal_mounts[@]} -gt 0 ] || fail "no journal directory on this runner"
    security+=(--security-opt apparmor=ci_alloy)
  fi
  docker run -d --name "$NAME" \
    "${security[@]}" \
    --add-host=host.docker.internal:host-gateway \
    -v "$DATA:/data" \
    "${journal_mounts[@]}" \
    "$IMAGE" >/dev/null
  local st=missing
  for _ in $(seq 1 30); do
    st=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)
    [ "$st" = "healthy" ] && break
    [ "$st" = "unhealthy" ] && fail "HEALTHCHECK reports unhealthy"
    sleep 3
  done
  [ "$st" = "healthy" ] || fail "not healthy after 90s (state: $st)"
  # One capture, then string tests: `docker logs | grep -q` under pipefail fails
  # spuriously when grep exits early and docker logs takes the SIGPIPE.
  local logs; logs=$(docker logs "$NAME" 2>&1)
  echo "healthy; container chose $(printf '%s\n' "$logs" | sed -n 's/^ Journal path: //p' | head -1)"
  case "$logs" in *"Alloy config validated"*) : ;; *) fail "the init script did not report a validated config" ;; esac
  if [ -z "$LOCAL" ]; then
    case "$logs" in *"error creating journal target"*) fail "journal source could not open the journal" ;; esac
  fi
}

# probe <job> <probe-text>: write the probe (journal, or a direct push locally)
# and wait for it under {job=<job>} in Loki. Leaves the matching stream's JSON
# in $STREAM.
STREAM=""
probe() {
  local job="$1" text="$2" q="" found=""
  if [ -n "$LOCAL" ]; then
    docker exec "$NAME" curl -sf -X POST -H 'Content-Type: application/json' \
      -d "{\"streams\":[{\"stream\":{\"job\":\"$job\",\"e2e\":\"local\"},\"values\":[[\"$(date +%s)000000000\",\"$text\"]]}]}" \
      "$LOKI_PUSH" || fail "container cannot push to Loki at $LOKI_PUSH"
  else
    logger -t ci-probe "$text"
  fi
  for _ in $(seq 1 24); do
    sleep 5
    # categorize-labels: stream labels and structured metadata come back apart;
    # without it Loki merges the metadata into the labels of the response.
    q=$(curl -sG -H 'X-Loki-Response-Encoding-Flags: categorize-labels' "$LOKI_QUERY/loki/api/v1/query_range" \
          --data-urlencode "query={job=\"$job\"} |= \"$text\"" \
          --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
          --data-urlencode "end=$(( $(date +%s) + 60 ))000000000" \
          --data-urlencode "limit=5")
    case "$q" in *"$text"*) found=1; break ;; esac
  done
  [ -n "$found" ] || { printf '%s\n' "$q" | head -c 600; fail "probe line never reached Loki under job=$job"; }
  STREAM=$(printf '%s' "$q" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"][0]; v=r["values"][0]; extra=v[2] if len(v)>2 else {}; print(json.dumps({"labels": r["stream"], "meta": extra.get("structuredMetadata", {}) if isinstance(extra, dict) else {}}))')
  echo "line received under job=$job: $STREAM"
}

# assert_labels <expected-sorted-comma-list> : exact label set of $STREAM,
# ignoring what Loki adds on its own (service_name from its service discovery).
assert_labels() {
  local have; have=$(printf '%s' "$STREAM" | python3 -c 'import json,sys; print(",".join(sorted(k for k in json.load(sys.stdin)["labels"] if k not in ("service_name",))))')
  [ "$have" = "$1" ] || fail "label set is [$have], expected [$1]"
}
# our_meta: the structured-metadata keys THIS add-on sets, ignoring Loki's own
# (detected_level). Prints them comma-separated, possibly empty.
our_meta() {
  printf '%s' "$STREAM" | python3 -c 'import json,sys; m=json.load(sys.stdin)["meta"]; print(",".join(sorted(k for k in m if k in ("syslog_identifier","container_name","transport","priority"))))'
}

say "1. AppArmor on the runner"
if [ -n "$LOCAL" ]; then
  echo "skipped (E2E_LOCAL)"
else
  sudo aa-enabled || fail "AppArmor is not enabled on this runner"
  # Home Assistant loads the profile under <repo-hash>_<slug>, so the sub-profile
  # receives signals from peer=*_alloy. Mirror that shape: ci_alloy matches *_alloy.
  # The complain flag, if present, is stripped: the test must run in ENFORCE.
  sed -e 's/^profile alloy /profile ci_alloy /' -e 's/,complain)/)/; s/(complain,/(/' "$PROFILE_SRC" > /tmp/ci_alloy.profile
  grep -q '^profile ci_alloy ' /tmp/ci_alloy.profile || fail "profile rename did not take"
  grep -q 'complain' /tmp/ci_alloy.profile && fail "complain flag still present after strip"
  sudo apparmor_parser -r -W /tmp/ci_alloy.profile || fail "profile does not parse"
  [ "$(sudo aa-status | grep -c 'ci_alloy')" -gt 0 ] || fail "profile not loaded"
  echo "profile loaded in enforce mode"
  echo "runner journald writes to: $(sudo journalctl --header 2>/dev/null | sed -n 's/^File path: //p' | head -1)"
fi

say "0. The image carries the Alloy version config.yaml promises"
# config.yaml carries <alloy>.<add-on revision>; the first three components must
# be the Alloy inside the image.
want=$(sed -n 's/^version: "\(.*\)"$/\1/p' alloy/config.yaml | cut -d. -f1-3)
have=$(docker run --rm --entrypoint /usr/bin/alloy "$IMAGE" --version | sed -n 's/^alloy, version v\([^ ]*\).*/\1/p')
echo "config.yaml alloy version=$want  image alloy=$have"
[ -n "$want" ] && [ "$want" = "$have" ] || fail "version mismatch: the published tag would lie about what is inside"

say "2. Default options: faithful and minimal"
start_addon "{\"loki_url\":\"$LOKI_PUSH\",\"log_level\":\"info\"}"
probe systemd-journal "ci-probe-default-$RUN_ID-$RANDOM"
if [ -z "$LOCAL" ]; then
  # Exactly the documented default set, nothing leaked in as a label.
  assert_labels "hostname,job,level,unit"
  # The detail fields travel nowhere by default (structured_metadata is off).
  [ -z "$(our_meta)" ] || fail "structured metadata present although the option defaults off: $STREAM"
  echo "default label set exact; no structured metadata from the add-on"
fi

say "3. Opinionated options: custom job, extra labels, metadata, level_from_message"
start_addon "{\"loki_url\":\"$LOKI_PUSH\",\"log_level\":\"info\",\"job\":\"e2e-custom\",\"stream_labels\":[\"hostname\",\"unit\",\"level\",\"syslog_identifier\"],\"structured_metadata\":true,\"level_from_message\":true}"
probe e2e-custom "ci-probe-custom-$RUN_ID-$RANDOM"
if [ -z "$LOCAL" ]; then
  assert_labels "hostname,job,level,syslog_identifier,unit"
  case "$(our_meta)" in *transport*) : ;; *) fail "structured metadata requested but transport not carried: $STREAM" ;; esac
  printf '%s' "$STREAM" | python3 -c 'import json,sys; l=json.load(sys.stdin)["labels"]; sys.exit(0 if l.get("syslog_identifier")=="ci-probe" else 1)' \
    || fail "syslog_identifier label wrong: $STREAM"
  echo "custom label set exact; structured metadata carried"
fi

say "4. Zero AppArmor denials for the profile"
if [ -n "$LOCAL" ]; then
  echo "skipped (E2E_LOCAL)"
else
  if [ -n "$(aa_events | grep -E 'DENIED|ALLOWED')" ]; then
    fail "the profile denied (or would have denied) something - add it to apparmor.txt"
  fi
  echo "none"
fi

docker rm -f "$NAME" >/dev/null
[ -n "$LOCAL" ] || sudo apparmor_parser -R /tmp/ci_alloy.profile || true
say "PASS"
