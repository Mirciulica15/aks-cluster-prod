# Update Azure AD App Registrations with new nip.io Redirect URIs
# Run this script after deploying ingress with nip.io DNS

param(
    [Parameter(Mandatory=$true)]
    [string]$LoadBalancerIP
)

$ErrorActionPreference = "Stop"

Write-Host "Updating Azure AD App Registrations with nip.io redirect URIs..." -ForegroundColor Cyan
Write-Host "LoadBalancer IP: $LoadBalancerIP" -ForegroundColor Yellow

# Grafana redirect URIs
$grafanaAppName = "AKS-Management-Grafana"
$grafanaRedirectUri = "https://grafana.$LoadBalancerIP.nip.io/login/generic_oauth"

Write-Host "`nUpdating Grafana app registration..." -ForegroundColor Cyan
$grafanaApp = az ad app list --display-name $grafanaAppName --query "[0]" | ConvertFrom-Json

if ($grafanaApp) {
    Write-Host "Found Grafana app: $($grafanaApp.appId)" -ForegroundColor Green

    # Get existing redirect URIs
    $existingUris = $grafanaApp.web.redirectUris

    # Add new nip.io URI if not already present
    if ($existingUris -notcontains $grafanaRedirectUri) {
        $existingUris += $grafanaRedirectUri

        # Update the app
        az ad app update --id $grafanaApp.appId --web-redirect-uris $existingUris
        Write-Host "Added redirect URI: $grafanaRedirectUri" -ForegroundColor Green
    } else {
        Write-Host "Redirect URI already exists: $grafanaRedirectUri" -ForegroundColor Yellow
    }
} else {
    Write-Host "ERROR: Grafana app registration not found!" -ForegroundColor Red
    exit 1
}

# Argo CD redirect URIs
$argocdAppName = "ArgoCD-Management-Cluster"
$argocdRedirectUris = @(
    "https://argocd.$LoadBalancerIP.nip.io/api/dex/callback",
    "https://argocd.$LoadBalancerIP.nip.io/auth/callback"
)

Write-Host "`nUpdating Argo CD app registration..." -ForegroundColor Cyan
$argocdApp = az ad app list --display-name $argocdAppName --query "[0]" | ConvertFrom-Json

if ($argocdApp) {
    Write-Host "Found Argo CD app: $($argocdApp.appId)" -ForegroundColor Green

    # Get existing redirect URIs
    $existingUris = $argocdApp.web.redirectUris

    # Add new nip.io URIs if not already present
    $updated = $false
    foreach ($uri in $argocdRedirectUris) {
        if ($existingUris -notcontains $uri) {
            $existingUris += $uri
            $updated = $true
            Write-Host "Added redirect URI: $uri" -ForegroundColor Green
        } else {
            Write-Host "Redirect URI already exists: $uri" -ForegroundColor Yellow
        }
    }

    if ($updated) {
        # Update the app
        az ad app update --id $argocdApp.appId --web-redirect-uris $existingUris
        Write-Host "Argo CD app registration updated successfully" -ForegroundColor Green
    }
} else {
    Write-Host "ERROR: Argo CD app registration not found!" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ All app registrations updated successfully!" -ForegroundColor Green
Write-Host "`nNew URLs:" -ForegroundColor Cyan
Write-Host "  Grafana: https://grafana.$LoadBalancerIP.nip.io" -ForegroundColor White
Write-Host "  Argo CD: https://argocd.$LoadBalancerIP.nip.io" -ForegroundColor White
Write-Host "  Hubble:  https://hubble.$LoadBalancerIP.nip.io" -ForegroundColor White
