# PowerShell script to deploy VNet Integration Project
# This script creates the resource group and deploys the Bicep template

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-pp-vnet",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory=$false)]
    [string]$UserEmail = "admin@MngEnvMCAP664295.onmicrosoft.com",

    [Parameter(Mandatory=$false)]
    [string]$PrimaryLocation = "westeurope",

    [Parameter(Mandatory=$false)]
    [string]$SecondaryLocation = "northeurope",

    [Parameter(Mandatory=$false)]
    [string]$PrimaryVnetName = "vnet-pp-westeurope",

    [Parameter(Mandatory=$false)]
    [string]$SecondaryVnetName = "vnet-pp-northeurope",

    [Parameter(Mandatory=$false)]
    [switch]$DeployEnterprisePolicy,

    [Parameter(Mandatory=$false)]
    [string]$EnterprisePolicyTemplateFile = "./infra/templateEntPolicyPP.json",

    [Parameter(Mandatory=$false)]
    [string]$EnterprisePolicyParametersFile = "./infra/enterprisePolicy.parameters.json"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to install Bicep CLI
function Install-BicepCLI {
    Write-Host "Installing Bicep CLI..." -ForegroundColor Yellow
    try {
        # Create directory for Bicep if it doesn't exist
        $bicepPath = "$env:USERPROFILE\.bicep"
        if (-not (Test-Path $bicepPath)) {
            New-Item -ItemType Directory -Path $bicepPath -Force | Out-Null
        }
        
        # Download and install Bicep CLI
        $bicepExe = "$bicepPath\bicep.exe"
        Invoke-RestMethod -Uri "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe" -OutFile $bicepExe
        
        # Add to PATH for current session
        $env:PATH = "$bicepPath;$env:PATH"
        
        # Add to user PATH permanently
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath -notlike "*$bicepPath*") {
            [Environment]::SetEnvironmentVariable("PATH", "$userPath;$bicepPath", "User")
        }
        
        Write-Host "Bicep CLI installed successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to install Bicep CLI: $_"
        return $false
    }
}

# Check if Bicep CLI is available
Write-Host "Checking Bicep CLI availability..." -ForegroundColor Yellow
$bicepAvailable = $false
try {
    $bicepVersion = bicep --version 2>$null
    if ($bicepVersion) {
        Write-Host "Bicep CLI is available: $bicepVersion" -ForegroundColor Green
        $bicepAvailable = $true
    }
} catch {
    Write-Host "Bicep CLI not found in PATH" -ForegroundColor Yellow
}

# Install Bicep if not available
if (-not $bicepAvailable) {
    $installResult = Install-BicepCLI
    if (-not $installResult) {
        Write-Error "Failed to install Bicep CLI. Exiting."
        exit 1
    }
}

# Login to Azure (if not already logged in)
Write-Host "Checking Azure authentication..." -ForegroundColor Yellow
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in to Azure. Please login..." -ForegroundColor Red
    Connect-AzAccount
}

# Set subscription
Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
try {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
} catch {
    Write-Host "Set-AzContext failed. Attempting interactive login for subscription..." -ForegroundColor Yellow
    try {
        Connect-AzAccount -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
        Write-Host "Subscription context set after login." -ForegroundColor Green
    } catch {
        Write-Error "Failed to set Azure context: $_"
        exit 1
    }
}

# Get user object ID from currently signed-in context (avoids directory mismatch)
Write-Host "Getting user object ID from current Azure context..." -ForegroundColor Yellow
try {
    $currentContext = Get-AzContext
    if (-not $currentContext -or -not $currentContext.Account) {
        throw "No valid Azure context found. Please login first."
    }
    
    # Try to get the signed-in user's object ID
    $signedInUserId = $currentContext.Account.ExtendedProperties.HomeAccountId
    if ($signedInUserId -and $signedInUserId.Contains('.')) {
        # Extract object ID from HomeAccountId (format: objectId.tenantId)
        $userObjectId = ($signedInUserId -split '\.')[0]
        Write-Host "Using signed-in user object ID: $userObjectId" -ForegroundColor Green
    } else {
        # Fallback: lookup by email
        Write-Host "Falling back to lookup by email: $UserEmail" -ForegroundColor Yellow
        $user = Get-AzADUser -UserPrincipalName $UserEmail -ErrorAction Stop
        if (-not $user) {
            throw "User not found: $UserEmail"
        }
        $userObjectId = $user.Id
        Write-Host "Found user object ID: $userObjectId" -ForegroundColor Green
    }
    
    Write-Host "Waiting 10 seconds for Azure AD replication..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
} catch {
    Write-Error "Failed to get user object ID: $_"
    exit 1
}

# Create resource group
Write-Host "Creating resource group: $ResourceGroupName in $Location" -ForegroundColor Yellow
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Write-Host "Resource group created successfully!" -ForegroundColor Green
    } else {
        Write-Host "Resource group already exists!" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to create resource group: $_"
    exit 1
}

# Deploy Bicep template
Write-Host "Deploying Bicep template..." -ForegroundColor Yellow
$deploymentName = "vnet-integration-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Beginning infrastructure (network) deployment (SQL removed)" -ForegroundColor Yellow

try {
    # Check if Azure PowerShell is available (preferred over CLI due to known CLI bugs)
    $azPowerShellAvailable = $false
    try {
        if (Get-Module -ListAvailable -Name Az.Resources) {
            $azPowerShellAvailable = $true
            Write-Host "Using Azure PowerShell for deployment (preferred)" -ForegroundColor Green
        }
    } catch {
        Write-Host "Azure PowerShell not available, checking for Azure CLI" -ForegroundColor Yellow
    }
    
    if ($azPowerShellAvailable) {
        # Use Azure PowerShell to deploy Bicep template
        Write-Host "Deploying using Azure PowerShell with Bicep..." -ForegroundColor Yellow
        
        Import-Module Az.Resources -Force
        
        $deployment = New-AzResourceGroupDeployment `
            -ResourceGroupName $ResourceGroupName `
            -Name $deploymentName `
            -TemplateFile ".\infra\main.bicep" `
            -primaryLocation $PrimaryLocation `
            -secondaryLocation $SecondaryLocation `
            -primaryVnetName $PrimaryVnetName `
            -secondaryVnetName $SecondaryVnetName `
            -userObjectId $userObjectId `
            -userEmail $UserEmail `
            -Verbose
        
        # Save connection information
        $connectionInfo = @{
            ResourceGroupName         = $ResourceGroupName
            PrimaryVirtualNetworkId   = $deployment.Outputs.primaryVirtualNetworkId.Value
            SecondaryVirtualNetworkId = $deployment.Outputs.secondaryVirtualNetworkId.Value
            WestEuropeSubnetId        = $deployment.Outputs.westEuropeSubnetId.Value
            NorthEuropeSubnetId       = $deployment.Outputs.northEuropeSubnetId.Value
        }
        
        $outputsForDisplay = $deployment.Outputs
    } else {
        # Fallback to Azure CLI
        Write-Host "Deploying using Azure CLI with Bicep..." -ForegroundColor Yellow
        
        # Create a temporary parameters file
        $tempParamsFile = "temp-params.json"
        $parametersObject = @{
            '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
            contentVersion = "1.0.0.0"
            parameters = @{
                primaryLocation   = @{ value = $PrimaryLocation }
                secondaryLocation = @{ value = $SecondaryLocation }
                primaryVnetName   = @{ value = $PrimaryVnetName }
                secondaryVnetName = @{ value = $SecondaryVnetName }
                userObjectId      = @{ value = $userObjectId }
                userEmail         = @{ value = $UserEmail }
            }
        }
        $parametersObject | ConvertTo-Json -Depth 4 | Out-File $tempParamsFile -Encoding UTF8
        
        try {
            $deploymentResult = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $deploymentName `
                --template-file ".\infra\main.bicep" `
                --parameters "@$tempParamsFile" `
                --output json
            
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI deployment failed with exit code $LASTEXITCODE"
            }
            
            $deployment = $deploymentResult | ConvertFrom-Json
        } finally {
            # Clean up temporary file
            if (Test-Path $tempParamsFile) {
                Remove-Item $tempParamsFile -Force
            }
        }
        
        # Save connection information
        $connectionInfo = @{
            ResourceGroupName        = $ResourceGroupName
            PrimaryVirtualNetworkId  = $deployment.properties.outputs.primaryVirtualNetworkId.value
            SecondaryVirtualNetworkId= $deployment.properties.outputs.secondaryVirtualNetworkId.value
            WestEuropeSubnetId       = $deployment.properties.outputs.westEuropeSubnetId.value
            NorthEuropeSubnetId      = $deployment.properties.outputs.northEuropeSubnetId.value
        }
        
        $outputsForDisplay = $deployment.properties.outputs
    }
    
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Deployment outputs:" -ForegroundColor Yellow
    $outputsForDisplay | ConvertTo-Json -Depth 3
    
    $connectionInfo | ConvertTo-Json -Depth 3 | Out-File ".\deployment-info.json" -Encoding UTF8
    Write-Host "Connection information saved to deployment-info.json" -ForegroundColor Green
    
} catch {
    Write-Error "Deployment failed: $_"
    exit 1
}

if ($DeployEnterprisePolicy) {
    Write-Host "`nDeploying Enterprise Policy (NetworkInjection)..." -ForegroundColor Yellow
    if (-not (Test-Path $EnterprisePolicyTemplateFile)) {
        Write-Error "Enterprise Policy template not found at path: $EnterprisePolicyTemplateFile"
        exit 1
    }
    if (-not (Test-Path $EnterprisePolicyParametersFile)) {
        Write-Error "Enterprise Policy parameters file not found at path: $EnterprisePolicyParametersFile"
        exit 1
    }

    try {
        $policyDeploymentName = "enterprise-policy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        # Generate dynamic parameters from infrastructure deployment outputs
        Write-Host "Generating Enterprise Policy parameters from deployment outputs..." -ForegroundColor Yellow
        $policyParamsTemplate = Get-Content $EnterprisePolicyParametersFile -Raw
        
        # Extract VNet names from resource IDs
        $primaryVNetId = $connectionInfo.PrimaryVirtualNetworkId
        $secondaryVNetId = $connectionInfo.SecondaryVirtualNetworkId
        
        # Generate dynamic policy name with random 4-digit suffix
        $randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
        $dynamicPolicyName = "pp-network-injection-policy-$randomSuffix"
        Write-Host "Generated policy name: $dynamicPolicyName" -ForegroundColor Cyan
        
        # Replace placeholders with actual values from deployment
        $policyParamsContent = $policyParamsTemplate `
            -replace '{{POLICY_NAME}}', $dynamicPolicyName `
            -replace '{{VNET_ONE_SUBNET_NAME}}', 'subnet-westeurope' `
            -replace '{{VNET_ONE_RESOURCE_ID}}', $primaryVNetId `
            -replace '{{VNET_TWO_SUBNET_NAME}}', 'subnet-northeurope' `
            -replace '{{VNET_TWO_RESOURCE_ID}}', $secondaryVNetId
        
        # Save to temporary file
        $tempPolicyParamsFile = "temp-policy-params.json"
        $policyParamsContent | Out-File $tempPolicyParamsFile -Encoding UTF8
        Write-Host "Generated parameters file: $tempPolicyParamsFile" -ForegroundColor Green
        
        # Ensure provider registered
        Write-Host "Ensuring Microsoft.PowerPlatform resource provider is registered..." -ForegroundColor Yellow
        try {
            $provider = Get-AzResourceProvider -ProviderNamespace Microsoft.PowerPlatform -ErrorAction SilentlyContinue
            if (-not $provider -or $provider.RegistrationState -ne 'Registered') {
                Write-Host "Registering Microsoft.PowerPlatform resource provider..." -ForegroundColor Yellow
                Register-AzResourceProvider -ProviderNamespace Microsoft.PowerPlatform | Out-Null
            }
        } catch { Write-Host "Warning: Unable to verify provider registration ($_). Continuing..." -ForegroundColor DarkYellow }

        # Deploy at resource group scope
        if ($azPowerShellAvailable) {
            # Use PowerShell for deployment
            if (-not (Get-Module -ListAvailable -Name Az.Resources)) { throw "Az.Resources module not available for PowerShell deployment." }
            $policyDeployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $ResourceGroupName `
                -Name $policyDeploymentName `
                -TemplateFile $EnterprisePolicyTemplateFile `
                -TemplateParameterFile $tempPolicyParamsFile `
                -Verbose
            if ($policyDeployment.ProvisioningState -ne 'Succeeded') { throw "Enterprise Policy deployment failed (PowerShell)" }
            Write-Host "Enterprise Policy deployed successfully (PowerShell, RG scope)." -ForegroundColor Green
        } else {
            # Fallback to Azure CLI
            $null = az deployment group create `
                --resource-group $ResourceGroupName `
                --name $policyDeploymentName `
                --template-file $EnterprisePolicyTemplateFile `
                --parameters @$tempPolicyParamsFile `
                --output json
            if ($LASTEXITCODE -ne 0) { throw "Enterprise Policy deployment failed (Azure CLI) with exit code $LASTEXITCODE" }
            Write-Host "Enterprise Policy deployed successfully (Azure CLI, RG scope)." -ForegroundColor Green
        }
        
        # Cleanup temporary file
        if (Test-Path $tempPolicyParamsFile) {
            Remove-Item $tempPolicyParamsFile -Force
            Write-Host "Cleaned up temporary parameters file." -ForegroundColor Green
        }
    } catch {
        Write-Error "Enterprise Policy deployment failed: $_"
        exit 1
    }
}

Write-Host "`nDeployment Summary:" -ForegroundColor Green
Write-Host "- Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "- Primary VNet: $($connectionInfo.PrimaryVirtualNetworkId)" -ForegroundColor White
Write-Host "- Secondary VNet: $($connectionInfo.SecondaryVirtualNetworkId)" -ForegroundColor White
Write-Host "- West Europe Subnet: $($connectionInfo.WestEuropeSubnetId)" -ForegroundColor White
Write-Host "- North Europe Subnet: $($connectionInfo.NorthEuropeSubnetId)" -ForegroundColor White
Write-Host "- RBAC Reader role assigned to: $UserEmail" -ForegroundColor White
if ($DeployEnterprisePolicy.IsPresent) { Write-Host "- Enterprise Policy deployed: True" -ForegroundColor White }

Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green