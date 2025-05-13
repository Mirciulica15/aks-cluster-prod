data "http" "github_meta" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}

data "azurerm_network_service_tags" "azure_devops_runners" {
  location = var.azure_devops_organization_location
  service  = "AzureCloud"
}

locals {
  github_meta    = jsondecode(data.http.github_meta.response_body)
  raw_action_ips = local.github_meta.actions

  azure_devops_ips_ipv4 = data.azurerm_network_service_tags.azure_devops_runners.ipv4_cidrs

  action_ips_ipv4 = [
    for ip in local.raw_action_ips : ip
    if length(regexall("^\\d+\\.\\d+\\.\\d+\\.\\d+(/\\d{1,2})?$", ip)) > 0
  ]

  all_ips = concat(var.ip_range_whitelist, local.action_ips_ipv4, local.azure_devops_ips_ipv4)

  collapsed_ips = jsondecode(
    data.external.collapsed_ips.result["collapsed_ips_json"]
  )
}

data "external" "collapsed_ips" {
  program = ["python", "${path.module}/scripts/collapse_ips.py"]
  query = {
    ips_json = jsonencode(local.all_ips)
  }
}
