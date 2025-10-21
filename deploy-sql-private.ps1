<#
.SYNOPSIS
    Deploys Azure SQL Database with Private Endpoint for Power Platform VNet Integration

.DESCRIPTION
    This script deploys:
    - New subnets for Private Endpoints in both VNets
    - Azure SQL Server (public access disabled)
    - SQL Database
    - Private Endpoint in West Europe subnet
    - Private DNS Zone with VNet links
    - Sample table for testing

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER ResourceGroupName
    Resource group name (default: rg-pp-vnet)

.PARAMETER SqlServerName
    SQL Server name (must be globally unique). If not provided, auto-generated.

.PARAMETER DatabaseName
    SQL Database name (default: db-powerplatform-test)

.PARAMETER SqlAdminUsername
    SQL admin username

.PARAMETER SqlAdminPassword
    SQL admin password (SecureString)

.PARAMETER EnableAzureAD
    Enable Azure AD authentication (default: true)

.PARAMETER AzureAdAdminEmail
    Azure AD admin email for SQL Server

.EXAMPLE
    .\deploy-sql-private.ps1 -SubscriptionId "xxx" -SqlAdminUsername "sqladmin" -SqlAdminPassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force)

.EXAMPLE
    .\deploy-sql-private.ps1 -SubscriptionId "xxx" -SqlServerName "sql-mycompany-prod"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-pp-vnet",

    [Parameter(Mandatory = $false)]
    [string]$SqlServerName = "",

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "db-powerplatform-test",

    [Parameter(Mandatory = $false)]
    [string]$SqlAdminUsername = "sqladmin",

    [Parameter(Mandatory = $false)]
    [SecureString]$SqlAdminPassword,

    [Parameter(Mandatory = $false)]
    [bool]$EnableAzureAD = $true,

    [Parameter(Mandatory = $false)]
    [string]$AzureAdAdminEmail = "",

    [Parameter(Mandatory = $false)]
    [string]$PrimaryVnetName = "vnet-pp-westeurope",

    [Parameter(Mandatory = $false)]
    [string]$SecondaryVnetName = "vnet-pp-northeurope",

    [Parameter(Mandatory = $false)]
    [string]$Location = "westeurope"
)

$ErrorActionPreference = "Stop"

# Helper function to write colored output
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "`n=== Azure SQL Private Endpoint Deployment ===" "Cyan"
Write-ColorOutput "This script will deploy Azure SQL with Private Endpoint for Power Platform`n" "Yellow"

# Check authentication
Write-ColorOutput "Checking Azure authentication..." "White"
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "Not authenticated. Please run Connect-AzAccount first." "Red"
        exit 1
    }
    Write-ColorOutput "Authenticated as: $($context.Account.Id)" "Green"
} catch {
    Write-ColorOutput "Error checking authentication: $_" "Red"
    exit 1
}

# Set subscription
Write-ColorOutput "Setting subscription to: $SubscriptionId" "White"
try {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-ColorOutput "Subscription set successfully" "Green"
} catch {
    Write-ColorOutput "Error setting subscription: $_" "Red"
    exit 1
}

# Generate SQL Server name if not provided
if ([string]::IsNullOrEmpty($SqlServerName)) {
    $randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
    $SqlServerName = "sql-pp-$randomSuffix"
    Write-ColorOutput "Auto-generated SQL Server name: $SqlServerName" "Yellow"
}

# Prompt for SQL password if not provided
if (-not $SqlAdminPassword) {
    Write-ColorOutput "`nSQL Admin credentials required" "Yellow"
    $SqlAdminPassword = Read-Host "Enter SQL Admin Password (min 8 chars, must include uppercase, lowercase, number)" -AsSecureString
    $confirmPassword = Read-Host "Confirm SQL Admin Password" -AsSecureString
    
    $pwd1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlAdminPassword))
    $pwd2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword))
    
    if ($pwd1 -ne $pwd2) {
        Write-ColorOutput "Passwords do not match!" "Red"
        exit 1
    }
}

# Get Azure AD admin info if enabled
$AzureAdAdminObjectId = ""
if ($EnableAzureAD) {
    if ([string]::IsNullOrEmpty($AzureAdAdminEmail)) {
        $currentUser = Get-AzContext
        $AzureAdAdminEmail = $currentUser.Account.Id
        Write-ColorOutput "Using current user as Azure AD admin: $AzureAdAdminEmail" "Yellow"
    }
    
    try {
        $user = Get-AzADUser -UserPrincipalName $AzureAdAdminEmail
        $AzureAdAdminObjectId = $user.Id
        Write-ColorOutput "Azure AD admin object ID: $AzureAdAdminObjectId" "Green"
    } catch {
        Write-ColorOutput "Warning: Could not resolve Azure AD user. Azure AD auth will be skipped." "Yellow"
        $EnableAzureAD = $false
    }
}

# Deployment parameters
$deploymentParams = @{
    primaryVnetName = $PrimaryVnetName
    secondaryVnetName = $SecondaryVnetName
    sqlServerName = $SqlServerName
    databaseName = $DatabaseName
    sqlAdminUsername = $SqlAdminUsername
    sqlAdminPassword = $SqlAdminPassword
    location = $Location
    enableAzureAD = $EnableAzureAD
    azureAdAdminObjectId = $AzureAdAdminObjectId
    azureAdAdminEmail = $AzureAdAdminEmail
}

Write-ColorOutput "`n=== Deployment Configuration ===" "Cyan"
Write-ColorOutput "Resource Group: $ResourceGroupName" "White"
Write-ColorOutput "SQL Server: $SqlServerName" "White"
Write-ColorOutput "Database: $DatabaseName" "White"
Write-ColorOutput "Admin Username: $SqlAdminUsername" "White"
Write-ColorOutput "Location: $Location" "White"
Write-ColorOutput "Azure AD Auth: $EnableAzureAD" "White"
Write-ColorOutput "Primary VNet: $PrimaryVnetName" "White"
Write-ColorOutput "Secondary VNet: $SecondaryVnetName`n" "White"

# Confirm deployment
$confirmation = Read-Host "Proceed with deployment? (y/n)"
if ($confirmation -ne 'y') {
    Write-ColorOutput "Deployment cancelled" "Yellow"
    exit 0
}

# Deploy Bicep template
Write-ColorOutput "`n=== Deploying Azure SQL with Private Endpoint ===" "Cyan"
try {
    $deployment = New-AzResourceGroupDeployment `
        -Name "sql-private-endpoint-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile ".\infra\sql-private-endpoint.bicep" `
        -TemplateParameterObject $deploymentParams `
        -Verbose

    if ($deployment.ProvisioningState -eq "Succeeded") {
        Write-ColorOutput "`n✅ Deployment completed successfully!" "Green"
        
        # Display outputs
        Write-ColorOutput "`n=== Deployment Outputs ===" "Cyan"
        Write-ColorOutput "SQL Server Name: $($deployment.Outputs.sqlServerName.Value)" "White"
        Write-ColorOutput "SQL Server FQDN: $($deployment.Outputs.sqlServerFqdn.Value)" "White"
        Write-ColorOutput "Database Name: $($deployment.Outputs.databaseName.Value)" "White"
        Write-ColorOutput "Private DNS Zone: $($deployment.Outputs.privateDnsZoneName.Value)" "White"
        Write-ColorOutput "`nConnection String Template:" "Yellow"
        Write-ColorOutput $deployment.Outputs.connectionStringTemplate.Value "White"
        
        # Save connection info
        $connectionInfo = @{
            SqlServerName = $deployment.Outputs.sqlServerName.Value
            SqlServerFqdn = $deployment.Outputs.sqlServerFqdn.Value
            DatabaseName = $deployment.Outputs.databaseName.Value
            PrivateDnsZone = $deployment.Outputs.privateDnsZoneName.Value
            AdminUsername = $SqlAdminUsername
            ConnectionStringTemplate = $deployment.Outputs.connectionStringTemplate.Value
        }
        
        $connectionInfo | ConvertTo-Json -Depth 3 | Out-File ".\sql-connection-info.json" -Encoding UTF8
        Write-ColorOutput "`nConnection info saved to: sql-connection-info.json" "Green"
        
        # Testing instructions
        Write-ColorOutput "`n=== Next Steps ===" "Cyan"
        Write-ColorOutput "1. Wait 2-3 minutes for DNS propagation" "Yellow"
        Write-ColorOutput "2. Link Power Platform environment to policy: pp-network-injection-policy-XXXX" "Yellow"
        Write-ColorOutput "3. Test connection from Power Apps:" "Yellow"
        Write-ColorOutput "   - Server: $($deployment.Outputs.sqlServerFqdn.Value)" "White"
        Write-ColorOutput "   - Database: $($deployment.Outputs.databaseName.Value)" "White"
        Write-ColorOutput "   - Auth: SQL Server Authentication" "White"
        Write-ColorOutput "   - Username: $SqlAdminUsername" "White"
        Write-ColorOutput "4. Test query: SELECT * FROM TestData" "Yellow"
        
    } else {
        Write-ColorOutput "Deployment failed with state: $($deployment.ProvisioningState)" "Red"
        exit 1
    }
} catch {
    Write-ColorOutput "Deployment error: $_" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    exit 1
}

Write-ColorOutput "`n=== Deployment Complete ===" "Green"
