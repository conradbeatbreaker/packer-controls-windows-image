#!/usr/bin/env bash
# Fail if versions.pkr.hcl is not exactly what versions.yaml at the pinned
# toolchain commit produces. Catches a hand-edited required_plugins block.
#
# Reads .toolchain-sha, fetches versions.yaml from packer-toolchain at that
# commit, regenerates into a temp file and diffs against the committed one.
#
# Env: GH_TOKEN (TOOLCHAIN_READ_TOKEN: Contents read-only on packer-toolchain).
set -euo pipefail

cd "$(dirname "$0")/.."
sha="$(tr -d '[:space:]' < .toolchain-sha)"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::.toolchain-sha is not a full commit SHA: '$sha'"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh api "repos/conradbeatbreaker/packer-toolchain/contents/versions.yaml?ref=$sha" \
  --jq '.content' | base64 -d > "$tmp/versions.yaml"
./scripts/generate-required-plugins.sh "$tmp/versions.yaml" "$tmp/versions.pkr.hcl"

if ! diff -u --label "versions.pkr.hcl (committed)" --label "versions.pkr.hcl (from toolchain @ ${sha:0:12})" \
     versions.pkr.hcl "$tmp/versions.pkr.hcl"; then
  echo "::error::versions.pkr.hcl does not match versions.yaml at toolchain ${sha:0:12}. Don't edit it by hand; run the Bump toolchain workflow."
  exit 1
fi
echo "versions.pkr.hcl matches packer-toolchain @ ${sha:0:12}."
