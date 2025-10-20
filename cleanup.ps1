#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cleanup script for Power Platform VNet Integration resources

.DESCRIPTION
    This script removes all resources created by the deployment script:
    - Enterprise Policies (all policies matching pattern pp-network-injection-policy-*)
    - Resource Group (rg-pp-vnet or custom name)
    - All contained resources (VNets, subnets, peerings, RBAC assignments)

.PARAMETER SubscriptionId
    The Azure subscription ID where resources are deployed

.PARAMETER ResourceGroupName
    The name of the resource group to delete (default: rg-pp-vnet)

.PARAMETER DeleteEnterprisePolicies
    Switch to delete all Enterprise Policies matching the pattern before deleting the resource group

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\cleanup.ps1 -SubscriptionId d68aa4f2-1c27-404b-8918-e064aba43131
    
.EXAMPLE
    .\cleanup.ps1 -SubscriptionId d68aa4f2-1c27-404b-8918-e064aba43131 -DeleteEnterprisePolicies -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure Subscription ID")]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-pp-vnet",

    [Parameter(Mandatory = $false)]
    [switch]$DeleteEnterprisePolicies,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "`n=== Power Platform VNet Integration - Cleanup ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow

# Check if Az PowerShell module is available
$azPowerShellAvailable = $false
try {
    Import-Module Az.Accounts -ErrorAction SilentlyContinue
    Import-Module Az.Resources -ErrorAction SilentlyContinue
    $azPowerShellAvailable = $true
    Write-Host "Using Azure PowerShell for cleanup" -ForegroundColor Green
} catch {
    Write-Host "Azure PowerShell not available, checking Azure CLI..." -ForegroundColor Yellow
}

# Check Azure CLI if PowerShell not available
$azCliAvailable = $false
if (-not $azPowerShellAvailable) {
    try {
        $null = az --version 2>$null
        $azCliAvailable = $true
        Write-Host "Using Azure CLI for cleanup" -ForegroundColor Green
    } catch {
        Write-Error "Neither Azure PowerShell nor Azure CLI is available. Please install one of them."
        exit 1
    }
}

# Set subscription context
Write-Host "`nSetting subscription context..." -ForegroundColor Yellow
if ($azPowerShellAvailable) {
    try {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        Write-Host "Context set successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to set subscription context: $_"
        exit 1
    }
} else {
    $null = az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set subscription context using Azure CLI"
        exit 1
    }
}

# Delete Enterprise Policies if requested
if ($DeleteEnterprisePolicies) {
    Write-Host "`nSearching for Enterprise Policies to delete..." -ForegroundColor Yellow
    
    if ($azPowerShellAvailable) {
        try {
            # Get all policies in the resource group
            $policies = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.PowerPlatform/enterprisePolicies" -ErrorAction SilentlyContinue
            
            if ($policies) {
                Write-Host "Found $($policies.Count) Enterprise Policy/Policies:" -ForegroundColor Cyan
                foreach ($policy in $policies) {
                    Write-Host "  - $($policy.Name)" -ForegroundColor White
                }
                
                if (-not $Force) {
                    $confirm = Read-Host "`nDelete these Enterprise Policies? (y/n)"
                    if ($confirm -ne 'y') {
                        Write-Host "Skipping Enterprise Policy deletion" -ForegroundColor Yellow
                        $DeleteEnterprisePolicies = $false
                    }
                }
                
                if ($DeleteEnterprisePolicies) {
                    foreach ($policy in $policies) {
                        Write-Host "Deleting policy: $($policy.Name)..." -ForegroundColor Yellow
                        try {
                            Remove-AzResource -ResourceId $policy.ResourceId -Force | Out-Null
                            Write-Host "  Deleted successfully" -ForegroundColor Green
                        } catch {
                            Write-Warning "Failed to delete policy $($policy.Name): $_"
                        }
                    }
                }
            } else {
                Write-Host "No Enterprise Policies found in resource group $ResourceGroupName" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Error searching for Enterprise Policies: $_"
        }
    } else {
        # Azure CLI approach
        try {
            $policiesJson = az resource list --resource-group $ResourceGroupName --resource-type "Microsoft.PowerPlatform/enterprisePolicies" --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and $policiesJson) {
                $policies = $policiesJson | ConvertFrom-Json
                
                if ($policies.Count -gt 0) {
                    Write-Host "Found $($policies.Count) Enterprise Policy/Policies:" -ForegroundColor Cyan
                    foreach ($policy in $policies) {
                        Write-Host "  - $($policy.name)" -ForegroundColor White
                    }
                    
                    if (-not $Force) {
                        $confirm = Read-Host "`nDelete these Enterprise Policies? (y/n)"
                        if ($confirm -ne 'y') {
                            Write-Host "Skipping Enterprise Policy deletion" -ForegroundColor Yellow
                            $DeleteEnterprisePolicies = $false
                        }
                    }
                    
                    if ($DeleteEnterprisePolicies) {
                        foreach ($policy in $policies) {
                            Write-Host "Deleting policy: $($policy.name)..." -ForegroundColor Yellow
                            $null = az resource delete --ids $policy.id 2>$null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "  Deleted successfully" -ForegroundColor Green
                            } else {
                                Write-Warning "Failed to delete policy $($policy.name)"
                            }
                        }
                    }
                } else {
                    Write-Host "No Enterprise Policies found in resource group $ResourceGroupName" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Warning "Error searching for Enterprise Policies: $_"
        }
    }
}

# Check if resource group exists
Write-Host "`nChecking if resource group exists..." -ForegroundColor Yellow
$rgExists = $false

if ($azPowerShellAvailable) {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    $rgExists = $null -ne $rg
} else {
    $rgJson = az group show --name $ResourceGroupName --output json 2>$null
    $rgExists = $LASTEXITCODE -eq 0
}

if (-not $rgExists) {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to clean up." -ForegroundColor Gray
    exit 0
}

# List resources in the group
Write-Host "`nListing resources in resource group..." -ForegroundColor Yellow
if ($azPowerShellAvailable) {
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    if ($resources) {
        Write-Host "Resources to be deleted:" -ForegroundColor Cyan
        foreach ($resource in $resources) {
            Write-Host "  - $($resource.ResourceType): $($resource.Name)" -ForegroundColor White
        }
    }
} else {
    $resourcesJson = az resource list --resource-group $ResourceGroupName --output json 2>$null
    if ($resourcesJson) {
        $resources = $resourcesJson | ConvertFrom-Json
        if ($resources.Count -gt 0) {
            Write-Host "Resources to be deleted:" -ForegroundColor Cyan
            foreach ($resource in $resources) {
                Write-Host "  - $($resource.type): $($resource.name)" -ForegroundColor White
            }
        }
    }
}

# Confirm deletion
if (-not $Force) {
    Write-Host "`n⚠️  WARNING: This will delete the entire resource group and all its resources!" -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to delete resource group '$ResourceGroupName'? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cleanup cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Delete the resource group
Write-Host "`nDeleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Gray

if ($azPowerShellAvailable) {
    try {
        Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
        Write-Host "`n✅ Resource group deleted successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to delete resource group: $_"
        exit 1
    }
} else {
    $null = az group delete --name $ResourceGroupName --yes --no-wait
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Resource group deletion initiated!" -ForegroundColor Green
        Write-Host "Note: Deletion is running in the background. Use 'az group show --name $ResourceGroupName' to check status." -ForegroundColor Gray
    } else {
        Write-Error "Failed to delete resource group"
        exit 1
    }
}

# Clean up local files if they exist
Write-Host "`nCleaning up local deployment files..." -ForegroundColor Yellow
$filesToClean = @("deployment-info.json", "temp-policy-params.json")
foreach ($file in $filesToClean) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "  Removed: $file" -ForegroundColor Gray
    }
}

Write-Host "`n✅ Cleanup completed successfully!" -ForegroundColor Green
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  - Resource Group: $ResourceGroupName (deleted)" -ForegroundColor White
if ($DeleteEnterprisePolicies) {
    Write-Host "  - Enterprise Policies: deleted" -ForegroundColor White
}
Write-Host "  - Local files: cleaned" -ForegroundColor White
Write-Host ""
