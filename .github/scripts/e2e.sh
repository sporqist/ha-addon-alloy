#!/usr/bin/env bash
# End-to-end test of the add-on image UNDER ITS APPARMOR PROFILE, in enforce
# mode, against a real journal and a real Loki. This is the gate that lets
# dependency bumps merge without a human: a new Alloy that needs a path the
# profile does not grant fails here, on the runner, not inside a household's
# Home Assistant.
#
# Proves, in order:
#   1. the profile parses and loads (apparmor_parser)
#   2. the container starts and its HEALTHCHECK reports healthy
#   3. a line written to the runner's journal arrives in Loki through the add-on
#   4. the kernel logged ZERO apparmor DENIED (or ALLOWED) events for the profile
#
# Usage: e2e.sh <image> <loki-url-as-seen-from-the-container> <loki-url-as-seen-from-the-runner>
#
# E2E_LOCAL=1 runs the same script on a machine without AppArmor or journald
# (Docker Desktop, WSL): steps 1 and 4 are skipped, a stub journal directory
# is mounted, and the probe is pushed to Loki from inside the container rather
# than written to a journal. Run it before every push - it catches everything
# except the profile itself.
set -euo pipefail

IMAGE="${1:?image}"
LOKI_PUSH="${2:?loki push url for the container}"
LOKI_QUERY="${3:?loki base url for the runner}"
LOCAL="${E2E_LOCAL:-}"
PROFILE_SRC="alloy/apparmor.txt"
NAME="alloy-e2e"
PROBE="ci-probe-${GITHUB_RUN_ID:-local}-$RANDOM"

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
  sudo aa-status | grep -q 'ci_alloy' || fail "profile not loaded"
  echo "profile loaded in enforce mode"
fi

say "2. Start the add-on under the profile"
# Runner-owned and world-writable: the container runs as root and the runner's
# docker may remap it; ownership must not be the thing under test.
DATA="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/addon-data"
rm -rf "$DATA"; mkdir -p "$DATA"; chmod 777 "$DATA"
printf '{"loki_url":"%s","log_level":"info"}' "$LOKI_PUSH" > "$DATA/options.json"
docker rm -f "$NAME" >/dev/null 2>&1 || true
journal_mounts=()
security=()
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

st=missing
for _ in $(seq 1 30); do
  st=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)
  [ "$st" = "healthy" ] && break
  [ "$st" = "unhealthy" ] && fail "HEALTHCHECK reports unhealthy"
  sleep 3
done
[ "$st" = "healthy" ] || fail "not healthy after 90s (state: $st)"
echo "healthy"
if [ -z "$LOCAL" ]; then
  docker logs "$NAME" 2>&1 | grep -q 'error creating journal target' && fail "journal source could not open the journal"
fi

say "3. A journal line makes it to Loki"
if [ -n "$LOCAL" ]; then
  # No journald here: push the probe from inside the container instead, which
  # still proves the container's network path to Loki.
  docker exec "$NAME" curl -sf -X POST -H 'Content-Type: application/json' \
    -d "{\"streams\":[{\"stream\":{\"job\":\"systemd-journal\",\"e2e\":\"local\"},\"values\":[[\"$(date +%s)000000000\",\"$PROBE\"]]}]}" \
    "$LOKI_PUSH" || fail "container cannot push to Loki at $LOKI_PUSH"
else
  logger -t ci-probe "$PROBE"
fi
found=""
q=""
for _ in $(seq 1 24); do
  sleep 5
  q=$(curl -sG "$LOKI_QUERY/loki/api/v1/query_range" \
        --data-urlencode "query={job=\"systemd-journal\"} |= \"$PROBE\"" \
        --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
        --data-urlencode "end=$(( $(date +%s) + 60 ))000000000" \
        --data-urlencode "limit=5")
  if printf '%s' "$q" | grep -q "$PROBE"; then found=1; break; fi
done
[ -n "$found" ] || { printf '%s\n' "$q" | head -c 600; fail "probe line never reached Loki"; }
echo "line received by Loki with labels: $(printf '%s' "$q" | python3 -c 'import json,sys; s=json.load(sys.stdin)["data"]["result"][0]["stream"]; print({k:s[k] for k in ("job","unit","syslog_identifier","hostname","level","e2e") if k in s})')"

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
