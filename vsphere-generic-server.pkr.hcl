# Windows Server image for vSphere.
#
# Packer and plugin versions are NOT declared here. They are pinned in
# versions.pkr.hcl, generated from packer-toolchain at .toolchain-sha, and
# installed from Nexus by the bootstrap step. Never add a required_plugins
# block to this file.

# ---------------------------------------------------------------------------
# Inputs driven by Port (passed as PKR_VAR_* by the CI pipeline)
# ---------------------------------------------------------------------------

variable "os_selection" {
  type        = string
  description = "OS chosen on the Port form, e.g. 'Windows Server 2022'."
}

variable "iso_item_name" {
  type        = string
  description = "OS ISO content-library item name (from the Port dropdown, parens-extracted)."
}

variable "tools_item_name" {
  type        = string
  description = "VMware Tools ISO content-library item name (from the Port dropdown)."
}

# ---------------------------------------------------------------------------
# Build-target inputs (CI/CD variables — not user-facing for the PoC)
# ---------------------------------------------------------------------------

variable "vsphere_server" {
  type    = string
  default = "10.10.2.22"
}

variable "vsphere_username" {
  type    = string
  default = "Administrator@sphere.local"
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

variable "build_datacenter" {
  type    = string
  default = "DC"
}

variable "build_datastore" {
  type    = string
  default = "ds1"
}

variable "build_cluster" {
  type    = string
  default = "CLUSTER1"
}

variable "os_iso_library" {
  type    = string
  default = "windows-image-iso"
}

variable "tools_iso_library" {
  type    = string
  default = "vmtools-iso"
}

variable "output_content_library" {
  type    = string
  default = "CONTENT"
}

variable "winrm_password" {
  type      = string
  sensitive = true
}

variable "winrm_user" {
  type    = string
  default = "administrator"
}

variable "ansible_extra_arguments" {
  type    = list(string)
  default = []
}

# ---------------------------------------------------------------------------
# OS matrix — all per-OS knowledge lives here, keyed by the Port selection.
# Add a new supported OS by adding one entry; nothing else changes.
# `eval`/`key` are wired for later licensed builds; PoC uses eval ISOs so
# `key` stays empty and the autounattend skips the ProductKey block.
# ---------------------------------------------------------------------------

variable "os_config" {
  type = map(object({
    guest_os_type = string
    os_image      = string
    os_short      = string
    eval          = bool
    key           = string
  }))
  default = {
    "Windows Server 2019" = {
      guest_os_type = "windows2019srv_64Guest"
      os_image      = "Windows Server 2019 SERVERDATACENTER"
      os_short      = "win2019"
      eval          = true
      key           = ""
    }
    "Windows Server 2022" = {
      guest_os_type = "windows2019srvNext_64Guest"
      os_image      = "Windows Server 2022 SERVERDATACENTER"
      os_short      = "win2022"
      eval          = true
      key           = ""
    }
    "Windows Server 2025" = {
      guest_os_type = "windows2019srvNext_64Guest"
      os_image      = "Windows Server 2025 SERVERDATACENTER"
      os_short      = "win2025"
      eval          = true
      key           = ""
    }
  }
}

locals {
  os = var.os_config[var.os_selection]

  # Machine name = <os_short>-<UTC build stamp>, e.g. win2022-20260721-1430.
  # This becomes the vSphere template name AND the Port vmImage identifier.
  template_name = "${local.os.os_short}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  ansible_extra_arguments = [
    "-e", "ansible_connection=winrm",
    "-e", "ansible_winrm_transport=basic",
    "-e", "winrm_password=${var.winrm_password}",
    "-e", "winrm_user=${var.winrm_user}",
    "-e", "ansible_password=${var.winrm_password}",
    "-e", "ansible_user=${var.winrm_user}",
    "-e", "ansible_winrm_server_cert_validation=ignore"
  ]
}

source "vsphere-iso" "windows-server-standard" {

  vcenter_server      = var.vsphere_server
  username            = var.vsphere_username
  password            = var.vsphere_password
  insecure_connection = true

  datacenter = var.build_datacenter
  datastore  = var.build_datastore
  cluster    = var.build_cluster

  boot_order    = "disk,cdrom"
  boot_command  = ["<spacebar>"]
  boot_wait     = "2s"
  guest_os_type = local.os.guest_os_type
  vm_name       = "build-${local.template_name}"

  RAM      = 8192
  firmware = "efi"

  convert_to_template = false
  content_library_destination {
    library     = var.output_content_library
    description = "Built by Packer from ${var.iso_item_name}"
    ovf         = false
    destroy     = true
    skip_import = false
    name        = local.template_name
  }
  network_adapters {
    network      = "VM Network"
    network_card = "vmxnet3"
  }

  disk_controller_type = ["lsilogic-sas"]
  storage {
    disk_size             = 100000
    disk_thin_provisioned = true
  }

  # ---------------------------------------------------------------------------
  # ISO ORDER IS LOAD-BEARING. Do not reorder.
  # In WinPE the tools ISO must land on E: so the pvscsi driver path in
  # autounattend.pkrtpl.hcl (<Path>E:\...\pvscsi\...</Path>) resolves. That
  # driver injection is required so VMs later DEPLOYED from this template can
  # use pvscsi controllers. Tools is listed FIRST to pin it to E: relative to
  # the OS install media. Verify on first build with PACKER_LOG=1 that tools
  # resolves to E:; if not, adjust order here.
  # ---------------------------------------------------------------------------
  iso_paths = [
    "${var.tools_iso_library}/${var.tools_item_name}/${var.tools_item_name}.iso",
    "${var.os_iso_library}/${var.iso_item_name}/${var.iso_item_name}.iso",
  ]
  # Guest-side PowerShell (run from autounattend). Not scripts/, which holds
  # this repo's CI scripts and must not end up on the build VM's CD.
  cd_files = [
    "${path.cwd}/guest-scripts/"
  ]
  cd_content = {
    "autounattend.xml" = templatefile("${abspath(path.root)}/data_vsphere/autounattend.pkrtpl.hcl", {
      build_username       = "administrator"
      build_password       = var.winrm_password
      vm_inst_os_eval      = local.os.eval
      vm_inst_os_language  = "en-US"
      vm_inst_os_keyboard  = "en-US"
      vm_inst_os_image     = local.os.os_image
      vm_inst_os_key       = local.os.key
      vm_guest_os_language = "en-US"
      vm_guest_os_keyboard = "en-US"
      vm_guest_os_timezone = "UTC"
    })
  }

  communicator   = "winrm"
  winrm_username = "administrator"
  winrm_password = var.winrm_password
}

build {
  # No hcp_packer_registry: it publishes build metadata to HashiCorp Cloud,
  # an internet dependency the air-gapped build network can't have.

  sources = [
    "source.vsphere-iso.windows-server-standard"
  ]

  provisioner "ansible" {
    playbook_file   = "${path.cwd}/ansible/optional_feature_remove_smbv1.yml"
    use_proxy       = false
    extra_arguments = local.ansible_extra_arguments
  }

  provisioner "ansible" {
    playbook_file   = "${path.cwd}/ansible/registry_crashcontrol_nmi.yml"
    use_proxy       = false
    extra_arguments = local.ansible_extra_arguments
  }

  provisioner "ansible" {
    playbook_file   = "${path.cwd}/ansible/service_windowsupdate.yml"
    use_proxy       = false
    extra_arguments = local.ansible_extra_arguments
  }
}
