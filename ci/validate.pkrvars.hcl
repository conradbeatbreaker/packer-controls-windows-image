# Placeholder values for `packer validate` only. Validate never contacts
# vCenter or the guest, so none of these need to be real; they just let the
# template evaluate. Real builds get these from build.yml (inputs and secrets).
os_selection     = "Windows Server 2022"
iso_item_name    = "validate-placeholder"
tools_item_name  = "validate-placeholder"
vsphere_password = "validate-placeholder"
winrm_password   = "validate-placeholder"
