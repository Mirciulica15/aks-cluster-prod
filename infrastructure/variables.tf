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
  default     = "Standard_D2_v2"
  validation {
    condition     = contains(["Standard_D2_v2"], var.vm_size)
    error_message = "Value must be one of 'Standard_D2_v2'."
  }
}
