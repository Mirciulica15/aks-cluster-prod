# Create Azure AD Groups for AKS Management Cluster RBAC
# This script creates the required Azure AD groups for Grafana and Argo CD access control

param(
    [Parameter(Mandatory=$false)]
    [string[]]$AdminUsers = @("mircea.talu@accesa.eu")
)

Write-Host "=== Creating Azure AD Groups for AKS Management Cluster ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is logged in
try {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged in"
    }
    Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "✓ Tenant ID: $($account.tenantId)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "✗ Azure CLI not found or not logged in. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

# Groups to create
$groups = @(
    @{
        Name = "AKS-Platform-Team"
        Description = "Platform team with full admin access to AKS management cluster (Grafana, Argo CD, etc.)"
    },
    @{
        Name = "AKS-Developers"
        Description = "Developers with read-only viewer access to AKS management cluster"
    },
    @{
        Name = "AKS-Team-Alpha"
        Description = "Team Alpha with access to their namespaces and AppProject"
    },
    @{
        Name = "AKS-Team-Beta"
        Description = "Team Beta with access to their namespaces and AppProject"
    }
)

foreach ($group in $groups) {
    Write-Host "Processing group: $($group.Name)" -ForegroundColor Cyan

    # Check if group already exists
    $existingGroup = az ad group list --display-name $group.Name --query "[0]" | ConvertFrom-Json

    if ($existingGroup) {
        Write-Host "  ✓ Group already exists (Object ID: $($existingGroup.id))" -ForegroundColor Yellow
        $groupId = $existingGroup.id
    } else {
        Write-Host "  Creating new group..." -ForegroundColor White
        $newGroup = az ad group create `
            --display-name $group.Name `
            --mail-nickname $group.Name `
            --description $group.Description | ConvertFrom-Json

        $groupId = $newGroup.id
        Write-Host "  ✓ Group created (Object ID: $groupId)" -ForegroundColor Green
    }

    # Add admin users to AKS-Platform-Team
    if ($group.Name -eq "AKS-Platform-Team" -and $AdminUsers) {
        Write-Host "  Adding admin users to AKS-Platform-Team..." -ForegroundColor White

        foreach ($userEmail in $AdminUsers) {
            # Try to get user object ID (try both regular and guest formats)
            $user = az ad user show --id $userEmail --query "id" -o tsv 2>$null

            # If not found, try searching by userPrincipalName or mail
            if (-not $user) {
                Write-Host "    User not found with email, searching by UPN..." -ForegroundColor Yellow
                $userList = az ad user list --filter "mail eq '$userEmail' or userPrincipalName eq '$userEmail'" --query "[0].id" -o tsv 2>$null
                $user = $userList
            }

            # If still not found, list all users with similar email to help identify the correct UPN
            if (-not $user) {
                Write-Host "    ⚠ Cannot find user automatically. Searching for guest users..." -ForegroundColor Yellow
                $emailPrefix = $userEmail -replace '@.*', ''
                $possibleUsers = az ad user list --query "[?contains(userPrincipalName, '$emailPrefix')].{UPN:userPrincipalName, Mail:mail, DisplayName:displayName}" -o table
                Write-Host "    Possible matches found:" -ForegroundColor Cyan
                Write-Host $possibleUsers
                Write-Host "    Please run manually: az ad group member add --group $groupId --member-id <USER_OBJECT_ID>" -ForegroundColor Yellow
                continue
            }

            if ($user) {
                # Check if user is already a member
                $isMember = az ad group member check --group $groupId --member-id $user --query "value" -o tsv

                if ($isMember -eq "true") {
                    Write-Host "    ✓ $userEmail already a member" -ForegroundColor Yellow
                } else {
                    az ad group member add --group $groupId --member-id $user
                    Write-Host "    ✓ Added $userEmail to group" -ForegroundColor Green
                }
            }
        }
    }

    Write-Host ""
}

Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Azure AD Groups Created:" -ForegroundColor Cyan
Write-Host "  • AKS-Platform-Team - Full admin access (Grafana Admin, Argo CD Admin)" -ForegroundColor White
Write-Host "  • AKS-Developers - Read-only viewer access" -ForegroundColor White
Write-Host "  • AKS-Team-Alpha - Team Alpha namespace access" -ForegroundColor White
Write-Host "  • AKS-Team-Beta - Team Beta namespace access" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify groups in Azure Portal: https://portal.azure.com/#blade/Microsoft_AAD_IAM/GroupsManagementMenuBlade" -ForegroundColor White
Write-Host "  2. Add more users to groups as needed" -ForegroundColor White
Write-Host "  3. Users will automatically get appropriate access to Grafana and Argo CD" -ForegroundColor White
Write-Host "  4. Changes take effect immediately (users may need to log out and back in)" -ForegroundColor White
