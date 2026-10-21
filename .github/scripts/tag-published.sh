#!/usr/bin/env bash
# Is <image>:<tag> already on the registry? Asked anonymously, the way a
# Home Assistant host pulls.
#
# Exit 0: published. Exit 1: not published (a 404 for the tag, or a package the
# registry does not know yet - a new add-on's first release). Exit 2: anything
# else. Callers treat 2 as a failure, never as "not published": a registry
# hiccup read as "free to push" is exactly how a version tag gets overwritten.
#
# Usage: tag-published.sh ghcr.io/<owner>/<name> <tag>
set -uo pipefail

image="${1:?image, e.g. ghcr.io/sporqist/ha-addon-alloy}"
tag="${2:?tag}"
registry="${image%%/*}"
repo="${image#*/}"

token_json=$(curl -sS --max-time 20 "https://${registry}/token?scope=repository:${repo}:pull") || {
  echo "tag-published: token request to ${registry} failed" >&2; exit 2; }
token=$(printf '%s' "$token_json" | jq -r '.token // empty')
if [ -z "$token" ]; then
  # GHCR answers DENIED for a package that does not exist yet (and for a
  # private one, which this repository's packages are not).
  if printf '%s' "$token_json" | jq -e '.errors[]? | select(.code == "DENIED")' >/dev/null 2>&1; then
    echo "tag-published: ${image} is not a package on ${registry} yet" >&2
    exit 1
  fi
  echo "tag-published: no token from ${registry}: ${token_json}" >&2
  exit 2
fi

code=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -I \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
  "https://${registry}/v2/${repo}/manifests/${tag}") || {
  echo "tag-published: manifest request failed" >&2; exit 2; }
case "$code" in
  200) exit 0 ;;
  404) exit 1 ;;
  *) echo "tag-published: ${image}:${tag} answered HTTP ${code}" >&2; exit 2 ;;
esac
