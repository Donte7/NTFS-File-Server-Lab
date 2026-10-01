variable "location" {
  type        = string
  default     = "Central US"
  description = "Azure region where all resources will be deployed."
}

variable "resource_group_name" {
  type        = string
  default     = "RG-FileServerLab"
  description = "Must stay consistent — Lab 2 references this exact name."
}

variable "vnet_name" {
  type        = string
  default     = "VNET-FileServerLab"
  description = "Name of the Virtual Network."
}

variable "subnet_name" {
  type        = string
  default     = "Subnet-Servers"
  description = "Name of the subnet all VMs sit on."
}

variable "vnet_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Address space for the VNet — 65,536 addresses."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "Address range for the subnet — 251 usable addresses."
}

variable "nsg_name" {
  type        = string
  default     = "NSG-RDP"
  description = "Name of the Network Security Group."
}

variable "rdp_source" {
  type        = string
  default     = "*"
  description = "Your public IP in CIDR format e.g. 1.2.3.4/32. Find at whatismyip.com"
}

variable "admin_username" {
  type        = string
  default     = "azureadmin"
  description = "Local administrator username for all three VMs."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_admin_password env var — never put this in a file."
}

variable "server_vm_size" {
  type        = string
  default     = "Standard_D2s_v3"
  description = "VM size for DC01 and FS01."
}

variable "client_vm_size" {
  type        = string
  default     = "Standard_D2s_v3"
  description = "VM size for CLIENT01."
}# CI/CD pipeline first run - Wed Sep 30 22:33:45 EDT 2026
