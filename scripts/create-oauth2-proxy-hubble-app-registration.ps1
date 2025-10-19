# Create Azure AD App Registration for OAuth2 Proxy (Hubble UI)
# This script automates the creation of an Azure AD application for OAuth2 Proxy authentication
# Prerequisites: Azure CLI installed and authenticated (az login)

param(
    [string]$AppName = "OAuth2-Proxy-Hubble-Management",
    [string]$HubbleURL = "https://hubble.98.71.72.150.nip.io", # Update with actual nip.io URL
    [string]$EnvFilePath = "$PSScriptRoot\..\infrastructure\.env"
)

Write-Host "Creating Azure AD App Registration for OAuth2 Proxy (Hubble UI)..." -ForegroundColor Green

# Get current tenant ID
$tenantId = az account show --query tenantId -o tsv
Write-Host "Current Tenant ID: $tenantId" -ForegroundColor Cyan

# Check if app already exists
$existingApp = az ad app list --display-name $AppName --query "[0]" | ConvertFrom-Json

if ($existingApp) {
    Write-Host "App registration '$AppName' already exists. Updating configuration..." -ForegroundColor Yellow
    $appId = $existingApp.appId
    $objectId = $existingApp.id

    # Update redirect URI
    Write-Host "  Updating redirect URI..." -ForegroundColor White
    az ad app update --id $objectId --web-redirect-uris "$HubbleURL/oauth2/callback" 2>$null
    Write-Host "✓ App configuration updated" -ForegroundColor Green
} else {
    Write-Host "Creating new app registration '$AppName'..." -ForegroundColor Cyan

    # Create the app registration with redirect URIs
    $appRegistration = az ad app create `
        --display-name $AppName `
        --sign-in-audience "AzureADMyOrg" `
        --web-redirect-uris "$HubbleURL/oauth2/callback" | ConvertFrom-Json

    $appId = $appRegistration.appId
    $objectId = $appRegistration.id

    Write-Host "✓ App registration created successfully!" -ForegroundColor Green
    Write-Host "  App ID: $appId" -ForegroundColor Yellow
}

# Add Microsoft Graph API permissions for user profile
Write-Host "`nConfiguring API permissions..." -ForegroundColor Cyan

# User.Read (delegated) - Sign in and read user profile
Write-Host "  Adding User.Read permission..." -ForegroundColor White
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 2>$null

Write-Host "✓ API permissions configured" -ForegroundColor Green

# Grant admin consent for API permissions
Write-Host "`nGranting admin consent for API permissions..." -ForegroundColor Cyan
try {
    az ad app permission admin-consent --id $objectId 2>$null
    Write-Host "✓ Admin consent granted successfully" -ForegroundColor Green
} catch {
    Write-Host "⚠ Could not automatically grant admin consent." -ForegroundColor Yellow
    Write-Host "  Please grant admin consent manually in Azure Portal:" -ForegroundColor Yellow
    Write-Host "  https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$appId" -ForegroundColor Cyan
}

# Check if client secret already exists in .env file
Write-Host "`nChecking for existing client secret..." -ForegroundColor Cyan
$existingClientSecret = $null

if (Test-Path $EnvFilePath) {
    $envContent = Get-Content $EnvFilePath
    $secretLine = $envContent | Where-Object { $_ -match '^TF_VAR_oauth2_proxy_hubble_client_secret=(.+)$' }
    if ($secretLine) {
        $existingClientSecret = $matches[1]
        Write-Host "✓ Using existing client secret from .env" -ForegroundColor Yellow
    }
}

# Only create a new secret if one doesn't exist
if (-not $existingClientSecret) {
    Write-Host "Creating new client secret..." -ForegroundColor Cyan
    $secretName = "oauth2-proxy-secret-$(Get-Date -Format 'yyyy-MM-dd')"
    $secret = az ad app credential reset --id $objectId --append --display-name $secretName --years 2 | ConvertFrom-Json
    $clientSecret = $secret.password
    Write-Host "✓ Client secret created (valid for 2 years)" -ForegroundColor Green
} else {
    $clientSecret = $existingClientSecret
}

# Generate cookie secret (must be exactly 16, 24, or 32 bytes for AES cipher)
# We'll generate 16 random bytes and convert to hex (32 characters)
Write-Host "`nGenerating cookie secret..." -ForegroundColor Cyan

# Check if cookie secret already exists and is valid length
$existingCookieSecret = $null
$validSecret = $false

if (Test-Path $EnvFilePath) {
    $envContent = Get-Content $EnvFilePath
    $cookieLine = $envContent | Where-Object { $_ -match '^TF_VAR_oauth2_proxy_cookie_secret=(.+)$' }
    if ($cookieLine) {
        $existingCookieSecret = $matches[1]
        # Check if the secret length is valid (16, 24, or 32 characters for hex strings = 8, 12, or 16 bytes)
        # OR 32, 48, or 64 characters for hex strings = 16, 24, or 32 bytes
        $length = $existingCookieSecret.Length
        if ($length -eq 32 -or $length -eq 48 -or $length -eq 64) {
            $validSecret = $true
            Write-Host "✓ Using existing valid cookie secret from .env (length: $length)" -ForegroundColor Yellow
        } else {
            Write-Host "⚠ Existing cookie secret has invalid length ($length), regenerating..." -ForegroundColor Yellow
        }
    }
}

if (-not $validSecret) {
    # Generate new 16-byte secret as hex string (32 characters)
    $cookieBytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Fill($cookieBytes)
    $cookieSecret = ($cookieBytes | ForEach-Object { $_.ToString("x2") }) -join ''
    Write-Host "✓ Cookie secret generated (32 hex characters = 16 bytes)" -ForegroundColor Green
} else {
    $cookieSecret = $existingCookieSecret
}

# Update or create .env file
Write-Host "`nUpdating environment file: $EnvFilePath" -ForegroundColor Cyan

$envVars = @{
    "TF_VAR_oauth2_proxy_hubble_client_id"     = $appId
    "TF_VAR_oauth2_proxy_hubble_client_secret" = $clientSecret
    "TF_VAR_oauth2_proxy_cookie_secret"        = $cookieSecret
}

# Read existing .env file if it exists
$envContent = @{}
if (Test-Path $EnvFilePath) {
    Get-Content $EnvFilePath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $envContent[$matches[1]] = $matches[2]
        }
    }
}

# Update with new values
foreach ($key in $envVars.Keys) {
    $envContent[$key] = $envVars[$key]
}

# Write back to file
$envContent.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "$($_.Key)=$($_.Value)"
} | Set-Content $EnvFilePath

Write-Host "✓ Environment file updated" -ForegroundColor Green

# Summary
Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "App Registration Details:" -ForegroundColor Cyan
Write-Host "  Name: $AppName" -ForegroundColor White
Write-Host "  App ID: $appId" -ForegroundColor White
Write-Host "  Tenant ID: $tenantId" -ForegroundColor White
Write-Host "  Redirect URI: $HubbleURL/oauth2/callback" -ForegroundColor White
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Run 'direnv allow' in the infrastructure directory" -ForegroundColor White
Write-Host "  2. Run 'terraform plan' to verify configuration" -ForegroundColor White
Write-Host "  3. Run 'terraform apply' to deploy OAuth2 Proxy" -ForegroundColor White
Write-Host "  4. Access Hubble UI at: $HubbleURL" -ForegroundColor White
