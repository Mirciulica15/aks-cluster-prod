# Create Azure AD App Registration for Argo CD SSO
# This script automates the creation of an Azure AD application for Argo CD OAuth2 authentication
# Prerequisites: Azure CLI installed and authenticated (az login)

param(
    [string]$AppName = "ArgoCD-Management-Cluster",
    [string]$ArgoCDURL = "https://argocd.yourdomain.com", # Update this with your actual Argo CD URL
    [string]$EnvFilePath = "$PSScriptRoot\..\infrastructure\.env"
)

Write-Host "Creating Azure AD App Registration for Argo CD..." -ForegroundColor Green

# Get current tenant ID
$tenantId = az account show --query tenantId -o tsv
Write-Host "Current Tenant ID: $tenantId" -ForegroundColor Cyan

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
Write-Host "Configuring API permissions..." -ForegroundColor Cyan

# User.Read (delegated) - Sign in and read user profile
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

# GroupMember.Read.All (delegated) - Read group memberships
az ad app permission add `
    --id $objectId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions bc024368-1153-4739-b217-4326f2e966d0=Scope

Write-Host "API permissions configured. Admin consent may be required." -ForegroundColor Yellow

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
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Azure AD App Registration Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "App Name:         $AppName"
Write-Host "Tenant ID:        $tenantId"
Write-Host "Application ID:   $appId"
Write-Host "Redirect URIs:    $ArgoCDURL/auth/callback"
Write-Host "                  $ArgoCDURL/api/dex/callback"
Write-Host "`nClient secret has been saved to .env file" -ForegroundColor Yellow
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Update ArgoCDURL parameter if you have a custom domain"
Write-Host "2. Grant admin consent for API permissions in Azure Portal (optional)"
Write-Host "3. Run 'source infrastructure/.env' to load environment variables"
Write-Host "4. Run 'terraform plan' and 'terraform apply' to deploy Argo CD"
Write-Host "========================================`n" -ForegroundColor Green
