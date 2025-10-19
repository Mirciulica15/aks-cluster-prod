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
  default     = "Standard_D4as_v4"
  validation {
    condition     = contains(["Standard_D2s_v3", "Standard_D4as_v4", "Standard_D4s_v3"], var.vm_size)
    error_message = "Value must be one of 'Standard_D2s_v3', 'Standard_D4as_v4', or 'Standard_D4s_v3'."
  }
}

variable "node_count" {
  description = "The number of nodes in the default node pool"
  type        = number
  default     = 2
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "ip_range_whitelist" {
  description = "List of IP addresses to whitelist in the Key Vault and AKS API"
  type        = list(string)
  default = [
    "91.240.5.0/24"
  ]
}

# Observability Stack Variables

variable "azure_ad_tenant_id" {
  description = "Azure AD Tenant ID for Grafana OAuth2 authentication"
  type        = string
  sensitive   = true
}

variable "azure_ad_grafana_client_id" {
  description = "Azure AD Application (Client) ID for Grafana OAuth2"
  type        = string
  sensitive   = true
}

variable "azure_ad_grafana_client_secret" {
  description = "Azure AD Application Client Secret for Grafana OAuth2"
  type        = string
  sensitive   = true
}

# Argo CD Variables

variable "azure_ad_argocd_client_id" {
  description = "Azure AD Application (Client) ID for Argo CD OAuth2"
  type        = string
  sensitive   = true
}

variable "azure_ad_argocd_client_secret" {
  description = "Azure AD Application Client Secret for Argo CD OAuth2"
  type        = string
  sensitive   = true
}

# OAuth2 Proxy Variables (for services without built-in auth)

variable "oauth2_proxy_hubble_client_id" {
  description = "Azure AD Application (Client) ID for OAuth2 Proxy (Hubble UI)"
  type        = string
  sensitive   = true
}

variable "oauth2_proxy_hubble_client_secret" {
  description = "Azure AD Application Client Secret for OAuth2 Proxy (Hubble UI)"
  type        = string
  sensitive   = true
}

variable "oauth2_proxy_cookie_secret" {
  description = "Cookie secret for OAuth2 Proxy (base64 encoded, 32 bytes)"
  type        = string
  sensitive   = true
}
