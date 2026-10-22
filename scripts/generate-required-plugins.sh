#!/usr/bin/env bash
# Render versions.pkr.hcl from the toolchain repo's versions.yaml.
#
#   generate-required-plugins.sh VERSIONS_YAML [OUT]
#
# OUT defaults to versions.pkr.hcl. Output is deterministic (plugins in
# versions.yaml order), so check-divergence.sh can diff it byte for byte.
# Requires yq (mikefarah v4).
set -euo pipefail

in="${1:?usage: generate-required-plugins.sh VERSIONS_YAML [OUT]}"
out="${2:-versions.pkr.hcl}"

packer_version="$(yq -r '.packer.version' "$in")"
[[ "$packer_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Bad Packer version in $in: $packer_version" >&2; exit 1; }

{
  cat <<EOF
# GENERATED FILE — do not edit.
# Rendered from versions.yaml by scripts/generate-required-plugins.sh.
# Source of truth: conradbeatbreaker/packer-toolchain @ .toolchain-sha
#
# The packer block does not interpolate variables, so exact versions are
# written in literally and CI fails if this file drifts from versions.yaml.

packer {
  required_version = "= $packer_version"

  required_plugins {
EOF
  while IFS=$'\t' read -r name version source; do
    [[ "$name" =~ ^[a-z0-9_-]+$ && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$source" =~ ^github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
      { echo "Bad plugin entry in $in: $name $version $source" >&2; exit 1; }
    cat <<EOF
    $name = {
      version = "= $version"
      source  = "$source"
    }
EOF
  done < <(yq -r '.plugins // {} | to_entries[] | [.key, .value.version, .value.source] | @tsv' "$in")
  cat <<EOF
  }
}
EOF
} > "$out"
