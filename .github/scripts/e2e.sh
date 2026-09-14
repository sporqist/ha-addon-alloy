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
set -euo pipefail

IMAGE="${1:?image}"
LOKI_PUSH="${2:?loki push url for the container}"
LOKI_QUERY="${3:?loki base url for the runner}"
PROFILE_SRC="alloy/apparmor.txt"
NAME="alloy-e2e"
PROBE="ci-probe-${GITHUB_RUN_ID:-local}-$RANDOM"

say() { printf '\n== %s\n' "$*"; }
fail() { printf '\n!! %s\n' "$*"; docker logs "$NAME" 2>&1 | tail -40 || true; exit 1; }

say "1. AppArmor on the runner"
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

say "2. Start the add-on under the profile"
mkdir -p /tmp/addon-data
printf '{"loki_url":"%s","log_level":"info"}' "$LOKI_PUSH" > /tmp/addon-data/options.json
docker rm -f "$NAME" >/dev/null 2>&1 || true
journal_mounts=()
[ -d /var/log/journal ] && journal_mounts+=(-v /var/log/journal:/var/log/journal:ro)
[ -d /run/log/journal ] && journal_mounts+=(-v /run/log/journal:/run/log/journal:ro)
[ ${#journal_mounts[@]} -gt 0 ] || fail "no journal directory on this runner"
docker run -d --name "$NAME" \
  --security-opt apparmor=ci_alloy \
  --add-host=host.docker.internal:host-gateway \
  -v /tmp/addon-data:/data \
  "${journal_mounts[@]}" \
  "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
  st=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)
  [ "$st" = "healthy" ] && break
  [ "$st" = "unhealthy" ] && fail "HEALTHCHECK reports unhealthy"
  sleep 3
done
[ "$st" = "healthy" ] || fail "not healthy after 90s (state: $st)"
echo "healthy"
docker logs "$NAME" 2>&1 | grep -q 'error creating journal target' && fail "journal source could not open the journal"

say "3. A journal line makes it to Loki"
logger -t ci-probe "$PROBE"
found=""
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
echo "line received by Loki with labels: $(printf '%s' "$q" | python3 -c 'import json,sys; s=json.load(sys.stdin)["data"]["result"][0]["stream"]; print({k:s[k] for k in ("job","unit","syslog_identifier","hostname","level") if k in s})')"

say "4. Zero AppArmor denials for the profile"
sudo journalctl -k --since "-10min" -o cat | grep -E 'apparmor="(DENIED|ALLOWED)"' | grep -E 'ci_alloy' > /tmp/aa.log || true
if [ -s /tmp/aa.log ]; then
  cat /tmp/aa.log
  fail "the profile denied (or would have denied) something - add it to apparmor.txt"
fi
echo "none"

docker rm -f "$NAME" >/dev/null
sudo apparmor_parser -R /tmp/ci_alloy.profile || true
say "PASS"
