variable "vm_name" {
  type        = string
  description = "Azure VM name"
}

variable "resource_group_name" {
  type    = string
  default = "CITRIX_BUILD"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vnet_name" {
  type    = string
  default = "vnet-eastus-2"
}

variable "subnet_name" {
  type    = string
  default = "snet-eastus-1"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2as_v7"
}

variable "dns_server" {
  type    = string
  default = "172.16.0.4"
}

variable "image_publisher" {
  type    = string
  default = "microsoftwindowsserver"
}

variable "image_offer" {
  type    = string
  default = "windowsserver2022"
}

variable "image_sku" {
  type    = string
  default = "2022-datacenter-smalldisk-g2"
}

variable "image_version" {
  type    = string
  default = "latest"
}

variable "os_disk_type" {
  type    = string
  default = "Premium_LRS"
}

variable "citrix_build_identity_name" {
  type        = string
  description = "Existing user-assigned managed identity attached to Citrix build VMs"
  default     = "CitrixBuildIdentity"
}

variable "citrix_build_identity_resource_group" {
  type        = string
  description = "Resource group containing the Citrix build managed identity"
  default     = "CITRIX_BUILD"
}

variable "admin_password" {
  type      = string
  sensitive = true
}
