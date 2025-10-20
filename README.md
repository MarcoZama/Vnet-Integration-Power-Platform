# Power Platform VNet Integration

Questo progetto automatizza il deployment dell'infrastruttura di rete Azure per Power Platform Network Injection, includendo VNet dual-region, peering, subnet delegation e Enterprise Policy.

## Risorse deployate

### Infrastruttura di rete

- Resource Group: rg-pp-vnet (West Europe)
- VNet primaria: vnet-pp-westeurope (10.0.0.0/16)
  - Subnet: subnet-westeurope (/27 = 27 IP)
  - Delegation: Microsoft.PowerPlatform/enterprisePolicies
  - Service Endpoints: Microsoft.Sql
- VNet secondaria: vnet-pp-northeurope (10.1.0.0/16)
  - Subnet: subnet-northeurope (/27 = 27 IP)
  - Delegation: Microsoft.PowerPlatform/enterprisePolicies
  - Service Endpoints: Microsoft.Sql
- VNet Peering bidirezionale (West-North Europe)
- RBAC: Reader role assignment

### Enterprise Policy (opzionale)

- Policy Name: pp-network-injection-policy-{4-digits}
- Kind: NetworkInjection
- Region: europe
- Subnet injection: Entrambe le subnet

## Prerequisiti

### Software
- PowerShell 7+
- Azure PowerShell (Az module)
- Bicep CLI (auto-installato se mancante)

### Permessi
- Subscription Contributor
- Permessi per creare Resource Group, VNet, RBAC, Enterprise Policy

### Autenticazione
```powershell
Connect-AzAccount
```

## Utilizzo

### Parametri principali

| Parametro | Obbligatorio | Default | Descrizione |
|-----------|--------------|---------|-------------|
| `-SubscriptionId` | Si | - | ID subscription Azure |
| `-UserEmail` | Si | - | UPN utente per RBAC |
| `-ResourceGroupName` | No | rg-pp-vnet | Nome resource group |
| `-PrimaryLocation` | No | westeurope | Region VNet primaria |
| `-SecondaryLocation` | No | northeurope | Region VNet secondaria |
| `-PrimaryVnetName` | No | vnet-pp-westeurope | Nome VNet primaria |
| `-SecondaryVnetName` | No | vnet-pp-northeurope | Nome VNet secondaria |
| `-DeployEnterprisePolicy` | No | false | Deploy Enterprise Policy |

### Esempi

**Deploy base (solo infrastruttura)**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL>
```

**Deploy completo (infrastruttura + policy)**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -DeployEnterprisePolicy
```

**Deploy con nomi custom**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -PrimaryVnetName "vnet-powerplatform-prod-we" `
  -SecondaryVnetName "vnet-powerplatform-prod-ne"
```

**Deploy con regioni diverse**
```powershell
.\deploy.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -UserEmail <YOUR_USER_EMAIL> `
  -PrimaryLocation "eastus" `
  -SecondaryLocation "westus"
```

## Cleanup

**Cleanup completo (con conferma)**
```powershell
.\cleanup.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -DeleteEnterprisePolicies
```

**Cleanup automatico (no conferma)**
```powershell
.\cleanup.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -DeleteEnterprisePolicies `
  -Force
```

**Cleanup solo Resource Group**
```powershell
.\cleanup.ps1 -SubscriptionId <YOUR_SUBSCRIPTION_ID>
```

## Struttura progetto

```
Vnet Integration PP/
├── deploy.ps1                            Script deployment
├── cleanup.ps1                           Script cleanup
├── infra/
│   ├── main.bicep                        Template infrastruttura
│   ├── templateEntPolicyPP.json          Template Enterprise Policy
│   └── enterprisePolicy.parameters.json  Parametri policy
├── deployment-info.json                  Output deployment (generato, git ignored)
├── .gitignore                            File esclusi da git
└── README.md                             Documentazione
```

### File generati (non versionati)

Lo script `deploy.ps1` genera file temporanei contenenti informazioni sensibili:
- `deployment-info.json` - Resource IDs delle VNet e subnet deployate
- `temp-policy-params.json` - Parametri temporanei per Enterprise Policy

Questi file sono automaticamente esclusi dal repository tramite `.gitignore`.

## Troubleshooting

### PrincipalNotFound
Causa: Replication delay Azure AD
Soluzione: Lo script attende 10 secondi automaticamente. Se persiste, attendere e rilanciare.

### SubnetMissingRequiredDelegation
Causa: Subnet senza delegation
Soluzione: Il template Bicep include automaticamente le delegation.

### EnterprisePolicyUpdateNotAllowed
Causa: Policy con stesso nome già esistente
Soluzione: Lo script genera nomi univoci con suffisso random.

### EnterprisePolicyDeleteNotAllowed
Causa: Policy collegata a ambiente Power Platform attivo
Soluzione: Scollegare ambiente nel Power Platform Admin Center prima del cleanup.

## Note importanti

### Automazione
- Nome policy generato automaticamente con suffisso random
- VNet IDs estratti da deployment outputs
- UserObjectId risolto automaticamente
- Deployment completamente parametrico

### Subnet delegation
- Irreversibile senza supporto Microsoft
- Subnet dedicate (no altre risorse)
- Subnet uniche per policy

### Sizing
- /27 = 27 IP utilizzabili
- 1 IP per container
- Pianificare picchi di carico

## Riferimenti

- [Power Platform VNet Support](https://learn.microsoft.com/power-platform/admin/vnet-support-overview)
- [Enterprise Policies ARM](https://learn.microsoft.com/azure/templates/microsoft.powerplatform/enterprisepolicies)
- [Subnet Delegation](https://learn.microsoft.com/azure/virtual-network/manage-subnet-delegation)
- [Azure Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## Licenza

Progetto per Power Platform VNet Integration
