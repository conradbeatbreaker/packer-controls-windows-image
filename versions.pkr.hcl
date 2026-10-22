# GENERATED FILE — do not edit.
# Rendered from versions.yaml by scripts/generate-required-plugins.sh.
# Source of truth: conradbeatbreaker/packer-toolchain @ .toolchain-sha
#
# The packer block does not interpolate variables, so exact versions are
# written in literally and CI fails if this file drifts from versions.yaml.

packer {
  required_version = "= 1.16.0"

  required_plugins {
    vsphere = {
      version = "= 2.5.0"
      source  = "github.com/vmware/vsphere"
    }
    ansible = {
      version = "= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}
