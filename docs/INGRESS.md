# HTTPS Ingress and Azure AD SSO

This document describes the HTTPS ingress implementation for the AKS management cluster, including automatic TLS certificate management and Azure AD single sign-on (SSO) authentication for all management services.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [DNS Strategy](#dns-strategy)
- [Service Access](#service-access)
- [Azure AD SSO Integration](#azure-ad-sso-integration)
- [Troubleshooting](#troubleshooting)

## Overview

The management cluster exposes three primary services via HTTPS with Azure AD authentication:

- **Grafana** - Observability dashboards with native Azure AD OAuth integration
- **ArgoCD** - GitOps continuous delivery with Dex identity provider
- **Hubble UI** - Cilium network observability with OAuth2 Proxy authentication layer

All services are exposed through an Azure LoadBalancer with a static public IP, using NGINX Ingress Controller for routing and cert-manager for automatic TLS certificate provisioning.

## Architecture

```
Internet
    |
    v
Azure LoadBalancer (Static Public IP)
    |
    v
NGINX Ingress Controller (2 replicas)
    |
    +-- cert-manager (automatic TLS)
    |
    +-- Grafana (native Azure AD OAuth)
    |
    +-- ArgoCD (Dex with Microsoft connector)
    |
    +-- OAuth2 Proxy --> Hubble UI
```

## Components

### NGINX Ingress Controller

**Deployment**: `infrastructure/ingress-nginx-helm.tf`

- **Version**: 4.11.3
- **Replicas**: 2 (high availability)
- **Service Type**: LoadBalancer with static public IP
- **External Traffic Policy**: Local (preserves source IP)

Key configuration:
```hcl
service = {
  type = "LoadBalancer"
  annotations = {
    "service.beta.kubernetes.io/azure-load-balancer-resource-group" = azurerm_kubernetes_cluster.main.node_resource_group
  }
  loadBalancerIP = azurerm_public_ip.ingress.ip_address
  externalTrafficPolicy = "Local"
}
```

### cert-manager

**Deployment**: `infrastructure/cert-manager-helm.tf`

- **Version**: 1.16.2
- **CRD Installation**: Enabled
- **Prometheus Metrics**: Enabled

Automatically provisions and renews TLS certificates from Let's Encrypt using HTTP-01 challenge.

**ClusterIssuer**: `examples/clusterissuer-letsencrypt.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: mircea.talu@accesa.eu
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Manual Setup Required**:
```bash
kubectl apply -f examples/clusterissuer-letsencrypt.yaml
```

### Static Public IP

**Deployment**: `infrastructure/ingress-public-ip.tf`

- **Allocation Method**: Static
- **SKU**: Standard
- **Resource Group**: AKS node resource group (MC_*)
- **DNS Label**: `aks-mgmt-accesa-{environment}` (Azure DNS)

The actual routing uses nip.io wildcard DNS (see DNS Strategy below).

### OAuth2 Proxy

**Deployment**: `infrastructure/oauth2-proxy-helm.tf`

- **Version**: 7.8.0
- **Namespace**: oauth2-proxy
- **Provider**: Azure AD
- **Purpose**: Authentication layer for Hubble UI (which lacks built-in auth)

Key configuration for cookie size optimization:
```hcl
config = {
  provider = "azure"
  sessionCookieMinimal = true  # Store only session ID in cookie
  scope = "openid email"       # Minimal scope to reduce cookie size
}
```

## DNS Strategy

Since we don't have a custom domain, we use **nip.io** - a wildcard DNS service that resolves `<subdomain>.<IP>.nip.io` to the IP address.

**Example**: `grafana.98.71.72.150.nip.io` resolves to `98.71.72.150`

This allows us to:
- Use different subdomains for each service
- Get valid Let's Encrypt TLS certificates (nip.io supports ACME challenges)
- Avoid the cost of registering and managing a custom domain

**Important**: The IP address is dynamically referenced from the Azure public IP resource in all Terraform configurations.

## Service Access

All services are accessible via HTTPS with Azure AD authentication:

### Grafana
- **URL**: `https://grafana.<PUBLIC_IP>.nip.io`
- **Authentication**: Native Grafana Azure AD OAuth
- **Role Mapping**:
  - `AKS-Platform-Team` → Admin
  - All authenticated users → Editor (default)

### ArgoCD
- **URL**: `https://argocd.<PUBLIC_IP>.nip.io`
- **Authentication**: Dex with Microsoft connector
- **RBAC Policies**:
  - `AKS-Platform-Team` → Admin (full access)
  - `AKS-Team-Alpha` → AppProject alpha access
  - `AKS-Team-Beta` → AppProject beta access
  - `AKS-Developers` → Read-only access

### Hubble UI
- **URL**: `https://hubble.<PUBLIC_IP>.nip.io`
- **Authentication**: OAuth2 Proxy with Azure AD
- **Access**: All authenticated Azure AD users

**To get the actual URLs**, run:
```bash
cd infrastructure/
terraform output ingress_ip_address
```

Then replace `<PUBLIC_IP>` in the URLs above.

## Azure AD SSO Integration

### Azure AD Groups

The following Azure AD groups control access:

- **AKS-Platform-Team** - Full admin access to all services
- **AKS-Developers** - Read-only access to ArgoCD
- **AKS-Team-Alpha** - Access to AppProject alpha in ArgoCD
- **AKS-Team-Beta** - Access to AppProject beta in ArgoCD

**Create groups**:
```powershell
.\scripts\create-azure-ad-groups.ps1
```

**Add users to groups** (example for guest users):
```powershell
.\scripts\create-azure-ad-groups.ps1 -UserEmail "mircea.talu_accesa.eu#EXT#@accesadw.onmicrosoft.com"
```

### Grafana SSO

**App Registration**: Created by `scripts/create-grafana-app-registration.ps1`

**Configuration**: `infrastructure/observability-kube-prometheus-stack.tf`

Grafana uses native Azure AD OAuth integration with automatic role mapping:
```hcl
"auth.generic_oauth" = {
  enabled = true
  name = "Azure AD"
  client_id = var.azure_ad_grafana_client_id
  client_secret = var.azure_ad_grafana_client_secret
  auth_url = "https://login.microsoftonline.com/${var.azure_ad_tenant_id}/oauth2/v2.0/authorize"
  token_url = "https://login.microsoftonline.com/${var.azure_ad_tenant_id}/oauth2/v2.0/token"
  api_url = "https://graph.microsoft.com/v1.0/me"
  scopes = "openid email profile"
  role_attribute_path = "contains(groups[*], 'AKS-Platform-Team') && 'Admin' || 'Editor'"
}
```

### ArgoCD SSO

**App Registration**: Created by `scripts/create-argocd-app-registration.ps1`

**Configuration**: `infrastructure/argocd-helm.tf`

ArgoCD uses Dex identity provider with Microsoft connector:
```hcl
"dex.config" = yamlencode({
  connectors = [{
    type = "microsoft"
    id = "microsoft"
    name = "Microsoft"
    config = {
      clientID = var.azure_ad_argocd_client_id
      clientSecret = var.azure_ad_argocd_client_secret
      tenant = var.azure_ad_tenant_id
      redirectURI = "https://argocd.${azurerm_public_ip.ingress.ip_address}.nip.io/api/dex/callback"
    }
  }]
})
```

**Critical**: Do NOT add `groups: ["id", "displayName"]` filter to the Dex config - this would filter to groups literally named "id" or "displayName", preventing all group membership from being returned.

**Required API Permissions**:
- `User.Read` (delegated)
- `GroupMember.Read.All` (delegated)
- `Group.Read.All` (delegated)

**Required App Configuration**:
- `groupMembershipClaims = SecurityGroup` (to include groups in token)

### Hubble UI SSO

**App Registration**: Created by `scripts/create-oauth2-proxy-hubble-app-registration.ps1`

**Configuration**: `infrastructure/oauth2-proxy-helm.tf`

Since Hubble UI lacks built-in authentication, we use OAuth2 Proxy as an authentication layer:
```hcl
config = {
  provider = "azure"
  sessionCookieMinimal = true  # Only store session ID in cookie
  scope = "openid email"       # Minimal scope to reduce cookie size
  upstreams = ["http://hubble-ui.kube-system.svc.cluster.local:80"]
}
```

**NGINX Buffer Configuration** (`infrastructure/ingress-hubble-oauth2.tf`):

OAuth2 Proxy with Azure AD can generate large session cookies. To handle this, the Hubble ingress has increased buffer sizes:
```hcl
annotations = {
  "nginx.ingress.kubernetes.io/proxy-buffer-size"   = "16k"
  "nginx.ingress.kubernetes.io/proxy-buffers"       = "4 32k"
  "nginx.ingress.kubernetes.io/proxy-busy-buffers-size" = "64k"
  "nginx.ingress.kubernetes.io/client-header-buffer-size" = "16k"
  "nginx.ingress.kubernetes.io/large-client-header-buffers" = "4 32k"
}
```

## Troubleshooting

### Certificate Issues

**Problem**: Certificate not issuing or stuck in pending state

**Check certificate status**:
```bash
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>
```

**Check cert-manager logs**:
```bash
kubectl logs -n cert-manager deploy/cert-manager
```

**Common causes**:
- ClusterIssuer not applied (run `kubectl apply -f examples/clusterissuer-letsencrypt.yaml`)
- HTTP-01 challenge failing (check ingress is reachable from internet)
- Rate limiting from Let's Encrypt (use staging issuer for testing)

### Grafana MultiAttachVolume Error

**Problem**: `Volume is already exclusively attached to one node and can't be attached to another`

**Root cause**: Azure Disk (RWO) can only attach to one pod. Rolling update tries to start new pod before old one releases volume.

**Solution**: Use `Recreate` deployment strategy instead of `RollingUpdate`:
```hcl
deploymentStrategy = {
  type = "Recreate"
}
```

This is already configured in `infrastructure/observability-kube-prometheus-stack.tf`.

### OAuth2 Proxy 502 Bad Gateway

**Problem**: `Multiple cookies are required for this session as it exceeds the 4kb cookie limit` causing 502 error

**Root cause**: Azure AD tokens can be large, especially with many group memberships

**Solution** (already implemented):
1. Enable minimal cookie mode: `sessionCookieMinimal = true`
2. Reduce OAuth scope to `openid email` (remove `profile`)
3. Increase NGINX buffer sizes (see Hubble UI SSO section)

### ArgoCD Login Failed

**Problem**: "Login failed" after successful Azure AD authentication

**Common causes**:

1. **Missing API permissions**:
   - Ensure `GroupMember.Read.All` and `Group.Read.All` are granted
   - Grant admin consent for permissions

2. **Missing group membership claims**:
   - Set `groupMembershipClaims = SecurityGroup` in app registration
   - Run `scripts/create-argocd-app-registration.ps1` to configure automatically

3. **Incorrect Dex group filter**:
   - Do NOT use `groups: ["id", "displayName"]` in Dex config
   - This filters to groups literally named "id" or "displayName"

4. **Guest user issues**:
   - Guest users have different UPN format: `user_domain#EXT#@tenant.onmicrosoft.com`
   - Ensure guest users are added to Azure AD groups correctly

**Check ArgoCD Dex logs**:
```bash
kubectl logs -n argocd deploy/argocd-dex-server
```

### OAuth2 Proxy 404 Not Found

**Problem**: Authentication succeeds but get 404 for root path

**Root cause**: Missing upstream configuration

**Solution**: Ensure `OAUTH2_PROXY_UPSTREAMS` environment variable is set:
```hcl
extraEnv = [
  {
    name = "OAUTH2_PROXY_UPSTREAMS"
    value = "http://hubble-ui.kube-system.svc.cluster.local:80"
  }
]
```

This is already configured in `infrastructure/oauth2-proxy-helm.tf`.

### Terraform Wants to Update Secrets

**Problem**: `terraform plan` shows updates to ArgoCD or OAuth2 Proxy secrets when nothing should change

**Root cause**: App registration scripts regenerated client secrets on every run, causing drift between .env file and deployed secrets

**Solution** (already implemented):
1. Scripts are now idempotent - they check for existing secrets before creating new ones
2. If drift occurs, extract actual secrets from Kubernetes cluster:
   ```bash
   # For ArgoCD
   kubectl get secret argocd-azure-ad-secret -n argocd -o jsonpath='{.data.client_secret}' | base64 -d

   # For OAuth2 Proxy
   kubectl get secret oauth2-proxy-hubble-secret -n oauth2-proxy -o jsonpath='{.data.client_secret}' | base64 -d
   ```
3. Update `.env` file with actual deployed secrets
4. Run `terraform refresh` to sync state

### DNS Resolution Issues

**Problem**: nip.io domain not resolving

**Check DNS**:
```bash
nslookup grafana.<PUBLIC_IP>.nip.io
```

**Alternative DNS servers** if nip.io is blocked:
- sslip.io (same format: `grafana.<IP>.sslip.io`)
- nip.io alternative servers (check nip.io documentation)

**Fallback**: Use direct IP access with port forwarding:
```bash
# Grafana
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80

# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

## Setup Checklist

To deploy the complete ingress stack from scratch:

1. **Deploy infrastructure**:
   ```bash
   cd infrastructure/
   terraform apply
   ```

2. **Apply ClusterIssuer**:
   ```bash
   kubectl apply -f examples/clusterissuer-letsencrypt.yaml
   ```

3. **Create Azure AD groups**:
   ```powershell
   .\scripts\create-azure-ad-groups.ps1
   ```

4. **Add users to groups**:
   ```powershell
   .\scripts\create-azure-ad-groups.ps1 -UserEmail "user@domain.com"
   ```

5. **Create Azure AD app registrations** (if not already done):
   ```powershell
   .\scripts\create-grafana-app-registration.ps1
   .\scripts\create-argocd-app-registration.ps1
   .\scripts\create-oauth2-proxy-hubble-app-registration.ps1
   ```

6. **Update environment variables**:
   ```bash
   cd infrastructure/
   direnv allow
   ```

7. **Apply Terraform changes**:
   ```bash
   terraform apply
   ```

8. **Get access URLs**:
   ```bash
   terraform output ingress_ip_address
   ```

9. **Wait for certificates** (can take 2-5 minutes):
   ```bash
   kubectl get certificate -A -w
   ```

10. **Access services** via HTTPS URLs and authenticate with Azure AD

## Security Considerations

- All services require Azure AD authentication
- TLS certificates automatically renewed by cert-manager
- NGINX Ingress Controller runs with non-root security context
- OAuth2 Proxy runs with non-root security context (UID 2000)
- API server access restricted to whitelisted IP ranges
- Key Vault access restricted to whitelisted IP ranges
- Grafana and ArgoCD use RBAC with Azure AD group integration
- Guest users supported with proper UPN format handling

## Cost Optimization

- Single NGINX Ingress Controller LoadBalancer (no per-service LoadBalancers)
- cert-manager single replica (sufficient for management cluster)
- OAuth2 Proxy single replica (sufficient for low traffic)
- No custom domain registration costs (using nip.io)
- No private endpoint costs (using public endpoints with IP whitelisting)

## References

- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [nip.io Documentation](https://nip.io/)
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [ArgoCD Dex Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/microsoft/)
- [Grafana OAuth Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/azuread/)
