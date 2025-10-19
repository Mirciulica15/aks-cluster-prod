# Create Azure AD App Registration for Argo CD SSO
# This script automates the creation of an Azure AD application for Argo CD OAuth2 authentication
# Prerequisites: Azure CLI installed and authenticated (az login)

param(
    [string]$AppName = "ArgoCD-Management-Cluster",
    [string]$ArgoCDURL, # Will be fetched from Terraform output if not provided
    [string]$EnvFilePath = "$PSScriptRoot\..\infrastructure\.env"
)

Write-Host "Creating Azure AD App Registration for Argo CD..." -ForegroundColor Green

# Get current tenant ID
$tenantId = az account show --query tenantId -o tsv
Write-Host "Current Tenant ID: $tenantId" -ForegroundColor Cyan

# Get ArgoCD URL from Terraform output if not provided
if (-not $ArgoCDURL) {
    Write-Host "Fetching ArgoCD URL from Terraform output..." -ForegroundColor Cyan
    Push-Location "$PSScriptRoot\..\infrastructure"
    $ArgoCDURL = terraform output -raw argocd_url 2>$null
    Pop-Location

    if (-not $ArgoCDURL) {
        Write-Host "Error: Could not fetch ArgoCD URL from Terraform output." -ForegroundColor Red
        Write-Host "Please provide -ArgoCDURL parameter or ensure Terraform has been applied." -ForegroundColor Red
        exit 1
    }
}

Write-Host "ArgoCD URL: $ArgoCDURL" -ForegroundColor Cyan

# Check if app already exists
$existingApp = az ad app list --display-name $AppName --query "[0]" | ConvertFrom-Json

if ($existingApp) {
    Write-Host "App registration '$AppName' already exists. Using existing app." -ForegroundColor Yellow
    $appId = $existingApp.appId
    $objectId = $existingApp.id
} else {
    Write-Host "Creating new app registration '$AppName'..." -ForegroundColor Cyan

    # Create the app registration with redirect URIs
    $appRegistration = az ad app create `
        --display-name $AppName `
        --sign-in-audience "AzureADMyOrg" `
        --web-redirect-uris "$ArgoCDURL/auth/callback" "$ArgoCDURL/api/dex/callback" `
        --enable-id-token-issuance true | ConvertFrom-Json

    $appId = $appRegistration.appId
    $objectId = $appRegistration.id

    Write-Host "App created successfully!" -ForegroundColor Green
    Write-Host "Application (client) ID: $appId" -ForegroundColor Cyan
}

# Add Microsoft Graph API permissions for user profile and group membership
Write-Host "`nConfiguring API permissions..." -ForegroundColor Cyan

# User.Read (delegated) - Sign in and read user profile
Write-Host "  Adding User.Read permission..." -ForegroundColor White
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 2>$null

# GroupMember.Read.All (delegated) - Read group memberships
Write-Host "  Adding GroupMember.Read.All permission..." -ForegroundColor White
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions bc024368-1153-4739-b217-4326f2e966d0=Scope 2>$null

# Group.Read.All (delegated) - Read all groups (needed for Dex Microsoft connector)
Write-Host "  Adding Group.Read.All permission..." -ForegroundColor White
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions 5f8c59db-677d-491f-a6b8-5f174b11ec1d=Scope 2>$null

Write-Host "✓ API permissions configured" -ForegroundColor Green

# Configure group membership claims in token
Write-Host "`nConfiguring group membership claims..." -ForegroundColor Cyan
az ad app update --id $objectId --set groupMembershipClaims=SecurityGroup 2>$null
Write-Host "✓ Group membership claims configured (SecurityGroup)" -ForegroundColor Green

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

# Generate a client secret (valid for 2 years)
Write-Host "Generating client secret..." -ForegroundColor Cyan
$secretName = "ArgoCD-Secret-$(Get-Date -Format 'yyyyMMdd')"
$secret = az ad app credential reset `
    --id $appId `
    --append `
    --display-name $secretName `
    --years 2 | ConvertFrom-Json

$clientSecret = $secret.password

Write-Host "Client secret created successfully!" -ForegroundColor Green

# Update .env file
Write-Host "Updating .env file..." -ForegroundColor Cyan

$envContent = Get-Content $EnvFilePath -Raw

# Add or update Argo CD environment variables
$argocdVars = @"

# Argo CD Azure AD OAuth2 Configuration
export TF_VAR_azure_ad_argocd_client_id="$appId"
export TF_VAR_azure_ad_argocd_client_secret="$clientSecret"
"@

# Check if Argo CD variables already exist
if ($envContent -match "TF_VAR_azure_ad_argocd_client_id") {
    # Update existing variables
    $envContent = $envContent -replace 'export TF_VAR_azure_ad_argocd_client_id="[^"]*"', "export TF_VAR_azure_ad_argocd_client_id=`"$appId`""
    $envContent = $envContent -replace 'export TF_VAR_azure_ad_argocd_client_secret="[^"]*"', "export TF_VAR_azure_ad_argocd_client_secret=`"$clientSecret`""
    Set-Content -Path $EnvFilePath -Value $envContent -NoNewline
} else {
    # Append new variables
    Add-Content -Path $EnvFilePath -Value $argocdVars -NoNewline
}

Write-Host ".env file updated successfully!" -ForegroundColor Green

# Summary
Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "App Registration Details:" -ForegroundColor Cyan
Write-Host "  Name:         $AppName" -ForegroundColor White
Write-Host "  Tenant ID:    $tenantId" -ForegroundColor White
Write-Host "  App ID:       $appId" -ForegroundColor White
Write-Host "  Redirect URI: $ArgoCDURL/api/dex/callback" -ForegroundColor White
Write-Host "`nAPI Permissions:" -ForegroundColor Cyan
Write-Host "  • User.Read (Delegated)" -ForegroundColor White
Write-Host "  • GroupMember.Read.All (Delegated)" -ForegroundColor White
Write-Host "  • Group.Read.All (Delegated)" -ForegroundColor White
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Run 'direnv allow' in the infrastructure directory" -ForegroundColor White
Write-Host "  2. Run 'terraform plan' to verify configuration" -ForegroundColor White
Write-Host "  3. Run 'terraform apply' to deploy ArgoCD with Azure AD SSO" -ForegroundColor White
Write-Host "  4. Access ArgoCD at: $ArgoCDURL" -ForegroundColor White
