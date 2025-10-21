# Power Platform VNet Integration

This project automates the deployment of Azure network infrastructure for Power Platform Network Injection, including dual-region VNet, peering, subnet delegation, and Enterprise Policy.

## Deployed Resources

### Network Infrastructure

- Resource Group: rg-pp-vnet (West Europe)
- Primary VNet: vnet-pp-westeurope (10.0.0.0/16)
  - Subnet: subnet-westeurope (/27 = 27 IPs)
  - Delegation: Microsoft.PowerPlatform/enterprisePolicies
  - Service Endpoints: Microsoft.Sql
- Secondary VNet: vnet-pp-northeurope (10.1.0.0/16)
  - Subnet: subnet-northeurope (/27 = 27 IPs)
  - Delegation: Microsoft.PowerPlatform/enterprisePolicies
  - Service Endpoints: Microsoft.Sql
- Bidirectional VNet Peering (West-North Europe)
- RBAC: Reader role assignment

### Enterprise Policy (optional)

- Policy Name: pp-network-injection-policy-{4-digits}
- Kind: NetworkInjection
- Region: europe
- Subnet injection: Both subnets

## Prerequisites

### Software
- PowerShell 7+
- Azure PowerShell (Az module)
- Bicep CLI (auto-installed if missing)

### Permissions
- Subscription Contributor
- Permissions to create Resource Group, VNet, RBAC, Enterprise Policy

### Authentication
```powershell
Connect-AzAccount
```

## Usage

### Main Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-SubscriptionId` | Yes | - | Azure subscription ID |
| `-UserEmail` | Yes | - | User UPN for RBAC |
| `-ResourceGroupName` | No | rg-pp-vnet | Resource group name |
| `-PrimaryLocation` | No | westeurope | Primary VNet region |
| `-SecondaryLocation` | No | northeurope | Secondary VNet region |
| `-PrimaryVnetName` | No | vnet-pp-westeurope | Primary VNet name |
| `-SecondaryVnetName` | No | vnet-pp-northeurope | Secondary VNet name |
| `-DeployEnterprisePolicy` | No | false | Deploy Enterprise Policy |

### Examples

**Basic deployment (infrastructure only)**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL>
```

**Complete deployment (infrastructure + policy)**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -DeployEnterprisePolicy
```

**Deployment with custom names**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -PrimaryVnetName "vnet-powerplatform-prod-we" `
  -SecondaryVnetName "vnet-powerplatform-prod-ne"
```

**Deployment with different regions**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -PrimaryLocation "eastus" `
  -SecondaryLocation "westus"
```

## Cleanup

**Complete cleanup (with confirmation)**
```powershell
.\cleanup.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -DeleteEnterprisePolicies
```

**Automatic cleanup (no confirmation)**
```powershell
.\cleanup.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -DeleteEnterprisePolicies `
  -Force
```

**Resource Group cleanup only**
```powershell
.\cleanup.ps1 -SubscriptionId <YOUR_SUBSCRIPTION_ID>
```

## Project Structure

```
Vnet Integration PP/
├── deploy.ps1                            Deployment script
├── cleanup.ps1                           Cleanup script
├── deploy-sql-private.ps1                Deploy Azure SQL with Private Endpoint
├── infra/
│   ├── main.bicep                        Infrastructure template
│   ├── templateEntPolicyPP.json          Enterprise Policy template
│   └── enterprisePolicy.parameters.json  Policy parameters
├── infra/sql-private-endpoint.bicep      SQL Private Endpoint template
├── TESTING-GUIDE.md                      Step-by-step testing guide
├── deployment-info.json                  Deployment output (generated, git ignored)
├── sql-connection-info.json              SQL connection output (git ignored)
├── .gitignore                            Git excluded files
└── README.md                             Documentation
```

### Generated Files (not versioned)

The `deploy.ps1` script generates temporary files containing sensitive information:
- `deployment-info.json` - Resource IDs of deployed VNets and subnets
- `temp-policy-params.json` - Temporary parameters for Enterprise Policy

These files are automatically excluded from the repository via `.gitignore`.

## Azure SQL Private Connectivity

This project includes an optional pattern to deploy an Azure SQL Server and Database with a Private Endpoint connected to the same VNets used for Power Platform integration. The implementation deploys dedicated subnets for Private Endpoints so that the Power Platform delegated subnets are not affected.

Key artifacts:
- `infra/sql-private-endpoint.bicep` - Bicep template that creates:
  - Private Endpoint subnets in both VNets (`subnet-private-endpoints-west` and `subnet-private-endpoints-north`)
  - Azure SQL Server (public access disabled)
  - Database
  - Private Endpoint and Private DNS Zone (`privatelink.database.windows.net`)
- `deploy-sql-private.ps1` - PowerShell script to orchestrate the Bicep deployment and save connection info to `sql-connection-info.json`.
- `TESTING-GUIDE.md` - Step-by-step instructions to test connectivity from Power Apps / Power Automate.

Usage example (PowerShell):
```powershell
.\deploy-sql-private.ps1 \
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> \
  -SqlAdminUsername "sqladmin" \
  -SqlAdminPassword (ConvertTo-SecureString "YourStrongP@ssw0rd123!" -AsPlainText -Force)
```

Notes and constraints:
- Do not create Private Endpoints in subnets delegated to `Microsoft.PowerPlatform/enterprisePolicies`. The template creates separate `/24` subnets for private endpoints.
- After deployment, link the Power Platform environment to the Enterprise Policy to enable network injection.
- DNS resolution for the SQL FQDN (`*.database.windows.net`) is provided by the private DNS zone `privatelink.database.windows.net`, which is linked to both VNets.
- The deployment saves connection details in `sql-connection-info.json`. This file is excluded from git.

Testing:
- Use the `TESTING-GUIDE.md` for instructions to test using Power Apps, Power Automate, or a VM inside the VNet.


## Troubleshooting

### PrincipalNotFound
Cause: Azure AD replication delay
Solution: The script waits 10 seconds automatically. If it persists, wait and relaunch.

### SubnetMissingRequiredDelegation
Cause: Subnet without delegation
Solution: The Bicep template automatically includes delegations.

### EnterprisePolicyUpdateNotAllowed
Cause: Policy with the same name already exists
Solution: The script generates unique names with random suffix.

### EnterprisePolicyDeleteNotAllowed
Cause: Policy linked to active Power Platform environment
Solution: Unlink environment in Power Platform Admin Center before cleanup.

## Important Notes

### Automation
- Policy name automatically generated with random suffix
- VNet IDs extracted from deployment outputs
- UserObjectId automatically resolved
- Fully parametric deployment

### Subnet Delegation
- Irreversible without Microsoft support
- Dedicated subnets (no other resources)
- Unique subnets per policy

### Sizing
- /27 = 27 usable IPs
- 1 IP per container
- Plan for load peaks

## References

- [Power Platform VNet Support](https://learn.microsoft.com/power-platform/admin/vnet-support-overview)
- [Enterprise Policies ARM](https://learn.microsoft.com/azure/templates/microsoft.powerplatform/enterprisepolicies)
- [Subnet Delegation](https://learn.microsoft.com/azure/virtual-network/manage-subnet-delegation)
- [Azure Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## License

Power Platform VNet Integration Project
