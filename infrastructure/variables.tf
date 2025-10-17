variable "project" {
  description = "The name of the project"
  type        = string
  default     = "management"
}

variable "location" {
  description = "The Azure region to deploy resources in"
  type        = string
  default     = "northeurope"
}

variable "environment" {
  description = "The environment for the resources (e.g., dev, test, prod)"
  type        = string
  default     = "prod"
}

variable "vm_size" {
  description = "The size of the virtual machines"
  type        = string
  default     = "Standard_D2s_v3"
  validation {
    condition     = contains(["Standard_D2s_v3"], var.vm_size)
    error_message = "Value must be one of 'Standard_D2s_v3'."
  }
}

variable "ip_range_whitelist" {
  description = "List of IP addresses to whitelist in the Key Vault and AKS API"
  type        = list(string)
  default = [
    "91.240.5.0/24"
  ]
}
