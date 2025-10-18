# Create Azure AD App Registration for Grafana OAuth2
# This script automates the creation of the App Registration required for Grafana Azure AD SSO

param(
    [Parameter(Mandatory=$false)]
    [string]$AppName = "AKS-Management-Grafana",

    [Parameter(Mandatory=$false)]
    [string]$GrafanaURL = "http://localhost:3000",

    [Parameter(Mandatory=$false)]
    [string]$OutputEnvFile = "../infrastructure/.env"
)

Write-Host "=== Azure AD App Registration Setup for Grafana ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is installed and logged in
try {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged in"
    }
    Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "✓ Subscription: $($account.name)" -ForegroundColor Green
    Write-Host "✓ Tenant ID: $($account.tenantId)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "✗ Azure CLI not found or not logged in. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

$tenantId = $account.tenantId

# Determine redirect URI
Write-Host "Redirect URI: $GrafanaURL/login/generic_oauth" -ForegroundColor Cyan
Write-Host ""

# Check if app already exists
Write-Host "Checking if app registration already exists..." -ForegroundColor Cyan
$existingApp = az ad app list --filter "displayName eq '$AppName'" --query "[0]" | ConvertFrom-Json

if ($existingApp) {
    Write-Host "✓ App registration already exists with ID: $($existingApp.appId)" -ForegroundColor Yellow
    $appId = $existingApp.appId
    $appObjectId = $existingApp.id

    Write-Host "  Using existing app registration (idempotent)" -ForegroundColor Green

    # Update redirect URI on existing app
    Write-Host "Updating redirect URI on existing app..." -ForegroundColor Cyan
    $redirectUris = @("$GrafanaURL/login/generic_oauth")
    az ad app update --id $appObjectId --web-redirect-uris $redirectUris 2>$null
    Write-Host "✓ Redirect URI updated" -ForegroundColor Green
} else {
    # Create the App Registration
    Write-Host "Creating new App Registration..." -ForegroundColor Cyan

    # API Permissions for Microsoft Graph
    $tempJsonFile = [System.IO.Path]::GetTempFileName()
    $apiPermissions = @{
        resourceAppId = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
        resourceAccess = @(
            @{
                id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegated)
                type = "Scope"
            },
            @{
                id = "14dad69e-099b-42c9-810b-d002981feec1" # profile (delegated)
                type = "Scope"
            },
            @{
                id = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email (delegated)
                type = "Scope"
            },
            @{
                id = "37f7f235-527c-4136-accd-4a02d197296e" # openid (delegated)
                type = "Scope"
            }
        )
    }

    @($apiPermissions) | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempJsonFile -Encoding UTF8

    try {
        $appRegistration = az ad app create `
            --display-name $AppName `
            --sign-in-audience "AzureADMyOrg" `
            --web-redirect-uris "$GrafanaURL/login/generic_oauth" `
            --enable-id-token-issuance true `
            --required-resource-accesses "@$tempJsonFile" | ConvertFrom-Json

        $appId = $appRegistration.appId
        $appObjectId = $appRegistration.id

        Write-Host "✓ App Registration created successfully" -ForegroundColor Green
        Write-Host "  App ID (Client ID): $appId" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to create app registration: $_" -ForegroundColor Red
        exit 1
    } finally {
        Remove-Item $tempJsonFile -ErrorAction SilentlyContinue
    }
}

# Create or reset client secret
Write-Host ""
Write-Host "Creating client secret..." -ForegroundColor Cyan

# Check for existing secrets
$existingSecrets = az ad app credential list --id $appObjectId | ConvertFrom-Json

if ($existingSecrets.Count -gt 0) {
    Write-Host "⚠ Found $($existingSecrets.Count) existing secret(s)" -ForegroundColor Yellow
    Write-Host "  Creating new secret (old secrets remain valid until expiration)" -ForegroundColor Yellow
}

$secretName = "grafana-secret-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    $credential = az ad app credential reset `
        --id $appObjectId `
        --append `
        --display-name $secretName `
        --years 2 | ConvertFrom-Json

    $clientSecret = $credential.password

    if (-not $clientSecret) {
        throw "Client secret is empty"
    }

    Write-Host "✓ Client secret created (expires: $($credential.endDateTime))" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to create client secret: $_" -ForegroundColor Red
    Write-Host "Attempting alternative method..." -ForegroundColor Yellow

    # Alternative: Remove all existing credentials and create new one
    $credential = az ad app credential reset `
        --id $appObjectId `
        --years 2 | ConvertFrom-Json

    $clientSecret = $credential.password
    Write-Host "✓ Client secret created (old secrets were reset)" -ForegroundColor Green
}

Write-Host ""

# Grant admin consent for API permissions
Write-Host "Granting admin consent for Microsoft Graph API permissions..." -ForegroundColor Cyan
$consentResult = az ad app permission admin-consent --id $appObjectId 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Admin consent granted" -ForegroundColor Green
} else {
    if ($consentResult -like "*Permissions were already granted*" -or $consentResult -like "*already consented*") {
        Write-Host "✓ Admin consent already granted (idempotent)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Could not grant admin consent automatically: $consentResult" -ForegroundColor Yellow
        Write-Host "  You may need to grant consent manually in Azure Portal:" -ForegroundColor Yellow
        Write-Host "  Azure Active Directory → App registrations → $AppName → API permissions → Grant admin consent" -ForegroundColor Yellow
    }
}

Write-Host ""

# Validate we have all required values
if (-not $appId -or -not $clientSecret) {
    Write-Host "✗ ERROR: Missing required values!" -ForegroundColor Red
    Write-Host "  App ID: $($appId ?? 'MISSING')" -ForegroundColor Red
    Write-Host "  Client Secret: $($clientSecret ? 'PRESENT' : 'MISSING')" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check the errors above and try again." -ForegroundColor Red
    exit 1
}

# Output summary
Write-Host "=== Configuration Summary ===" -ForegroundColor Cyan
Write-Host "Tenant ID:     $tenantId"
Write-Host "Client ID:     $appId"
Write-Host "Client Secret: $($clientSecret.Substring(0, [Math]::Min(10, $clientSecret.Length)))..." -ForegroundColor Green
Write-Host "Redirect URI:  $GrafanaURL/login/generic_oauth"
Write-Host ""

# Update or create .env file
Write-Host "Updating .env file..." -ForegroundColor Cyan

$envPath = Join-Path $PSScriptRoot $OutputEnvFile
$envContent = @()

# Read existing .env if it exists
if (Test-Path $envPath) {
    $envContent = Get-Content $envPath
}

# Remove existing Grafana OAuth2 variables if present
$envContent = $envContent | Where-Object {
    $_ -notmatch "^export TF_VAR_azure_ad_tenant_id=" -and
    $_ -notmatch "^export TF_VAR_azure_ad_grafana_client_id=" -and
    $_ -notmatch "^export TF_VAR_azure_ad_grafana_client_secret=" -and
    $_ -notmatch "^# Grafana OAuth2 Configuration"
}

# Add Grafana OAuth2 variables
$envContent += ""
$envContent += "# Grafana OAuth2 Configuration - Generated by create-grafana-app-registration.ps1"
$envContent += "# Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$envContent += "export TF_VAR_azure_ad_tenant_id=`"$tenantId`""
$envContent += "export TF_VAR_azure_ad_grafana_client_id=`"$appId`""
$envContent += "export TF_VAR_azure_ad_grafana_client_secret=`"$clientSecret`""

# Write back to .env
$envContent | Out-File -FilePath $envPath -Encoding UTF8
Write-Host "✓ .env file updated at: $envPath" -ForegroundColor Green
Write-Host ""

# Instructions
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Run 'direnv allow' (or source .env) in the infrastructure directory to load the new variables"
Write-Host "2. Run 'terraform apply' to deploy the observability stack"
Write-Host "3. If using port-forward, update the redirect URI:"
Write-Host "   ./scripts/create-grafana-app-registration.ps1 -GrafanaURL 'http://localhost:3000'"
Write-Host ""
Write-Host "4. If deploying with Ingress later, update the redirect URI:"
Write-Host "   ./scripts/create-grafana-app-registration.ps1 -GrafanaURL 'https://grafana.yourdomain.com'"
Write-Host ""
Write-Host "5. Access Grafana:"
Write-Host "   kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80"
Write-Host "   Open http://localhost:3000"
Write-Host "   Click 'Sign in with Azure AD'"
Write-Host ""

Write-Host "✓ Setup complete!" -ForegroundColor Green
