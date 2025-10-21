# Testing Power Platform Private Connectivity to Azure SQL

This guide explains how to test private connectivity from Power Platform to Azure SQL Database using VNet Integration.

## Prerequisites

- Completed VNet infrastructure deployment (`deploy.ps1`)
- Enterprise Policy created and available
- Power Platform environment with appropriate license

## Step 1: Deploy Azure SQL with Private Endpoint

Run the deployment script:

```powershell
.\deploy-sql-private.ps1 `
  -SubscriptionId <YOUR_SUBSCRIPTION_ID> `
  -SqlAdminUsername "sqladmin" `
  -SqlAdminPassword (ConvertTo-SecureString "YourStrongP@ssw0rd123!" -AsPlainText -Force)
```

### What gets deployed:

- **New Subnets**: `subnet-private-endpoints-west` (10.0.2.0/24) and `subnet-private-endpoints-north` (10.1.2.0/24)
- **SQL Server**: With public access disabled
- **SQL Database**: Basic tier with sample TestData table
- **Private Endpoint**: In West Europe subnet
- **Private DNS Zone**: `privatelink.database.windows.net` linked to both VNets

### Architecture:

```
vnet-pp-westeurope (10.0.0.0/16)
├── subnet-westeurope (10.0.1.0/27) 
│   └── DELEGATED to Microsoft.PowerPlatform/enterprisePolicies
└── subnet-private-endpoints-west (10.0.2.0/24)
    └── Private Endpoint for SQL (10.0.2.x)

vnet-pp-northeurope (10.1.0.0/16)
├── subnet-northeurope (10.1.1.0/27)
│   └── DELEGATED to Microsoft.PowerPlatform/enterprisePolicies
└── subnet-private-endpoints-north (10.1.2.0/24)
    └── Available for additional endpoints
```

## Step 2: Configure Power Platform Environment

1. Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)

2. Create or edit an environment:
   - Click **Environments** > **New** (or select existing)
   - Fill in environment details
   - Expand **Advanced settings**
   - Under **Network injection**, select your Enterprise Policy (e.g., `pp-network-injection-policy-4990`)
   - Click **Save**

3. Wait for provisioning (10-30 minutes)

4. Verify environment status shows "Ready"

## Step 3: Test Connection from Power Apps

### Option A: Canvas App with SQL Connector

1. Go to [Power Apps](https://make.powerapps.com)

2. Select your VNet-enabled environment

3. Create a new Canvas App

4. Add Data Source:
   - Click **Data** > **Add data**
   - Search for **SQL Server**
   - Select **SQL Server** connector

5. Configure connection:
   - **Connection type**: Connect directly (cloud services)
   - **SQL Server name**: `sql-pp-XXXX.database.windows.net` (from sql-connection-info.json)
   - **Database name**: `db-powerplatform-test`
   - **Authentication**: SQL Server Authentication
   - **Username**: `sqladmin`
   - **Password**: Your password
   - **Gateway**: None (uses VNet Integration)

6. Click **Connect**

7. Select the `TestData` table

8. Add a Gallery control and bind it to the TestData table:
   ```
   Gallery1.Items = TestData
   ```

9. You should see the 3 test records!

### Option B: Power Automate Flow

1. Go to [Power Automate](https://make.powerautomate.com)

2. Select your VNet-enabled environment

3. Create a new instant flow:
   - **Flow name**: Test SQL Private Connection
   - **Trigger**: Manually trigger a flow

4. Add action:
   - Search for **SQL Server**
   - Select **Execute a SQL query**
   - Create new connection using the same details as above

5. Configure query:
   ```sql
   SELECT * FROM TestData
   ```

6. Add a **Compose** action to show results

7. Save and test the flow

8. Check the output - you should see the test records

### Option C: Custom Connector (Advanced)

For applications requiring direct SQL queries without the standard connector:

1. Create a Custom Connector in Power Platform
2. Use Azure SQL REST API or create an Azure Function as middleware
3. The Azure Function would use the VNet integration to access SQL privately

## Step 4: Verify Private Connectivity

### DNS Resolution Test

From a VM inside the VNet, verify DNS resolves to private IP:

```powershell
Resolve-DnsName sql-pp-XXXX.database.windows.net
```

Expected: Should return the private IP (10.0.2.x)

### Connectivity Test

Test from within the VNet:

```powershell
Test-NetConnection -ComputerName sql-pp-XXXX.database.windows.net -Port 1433
```

Expected: `TcpTestSucceeded: True`

### From Power Platform

In Power Apps, the connection should work WITHOUT any gateway, confirming it's using the private endpoint through VNet integration.

## Troubleshooting

### Connection Fails from Power Apps

**Issue**: "Unable to connect to SQL Server"

**Solutions**:
- Verify environment is linked to Enterprise Policy
- Wait 30+ minutes after environment provisioning
- Check SQL Server allows the authentication method
- Verify Private DNS Zone is linked to both VNets
- Check NSG rules aren't blocking traffic

### DNS Not Resolving to Private IP

**Issue**: DNS returns public IP or no record

**Solutions**:
- Wait 5 minutes for DNS propagation
- Verify Private DNS Zone has A record for SQL server
- Check VNet links are active in DNS Zone
- Try `Clear-DnsClientCache` on test VM

### Authentication Fails

**Issue**: "Login failed for user 'sqladmin'"

**Solutions**:
- Verify username/password are correct
- Check SQL Server allows SQL Authentication (not Azure AD only)
- If using Azure AD, verify user is configured as admin

### Subnet Delegation Error

**Issue**: Cannot create Private Endpoint in delegated subnet

**Solution**: Use the separate `subnet-private-endpoints-west` subnet created by the script, NOT the Power Platform delegated subnet.

## Sample SQL Queries for Testing

### Basic read test:
```sql
SELECT * FROM TestData
```

### Insert test:
```sql
INSERT INTO TestData (Name) VALUES ('Power Platform Test')
```

### Count test:
```sql
SELECT COUNT(*) as TotalRecords FROM TestData
```

### Metadata test:
```sql
SELECT @@VERSION as SqlVersion
```

## Security Best Practices

1. **Use Azure AD Authentication**: Enable and prefer Azure AD over SQL auth
2. **Rotate Passwords**: Change SQL admin password regularly
3. **Least Privilege**: Create dedicated SQL users for Power Platform with minimal permissions
4. **Monitor Access**: Enable SQL auditing and log analytics
5. **Backup**: Ensure automated backups are configured
6. **Firewall**: Verify public access is disabled (`publicNetworkAccess: Disabled`)

## Cleanup

To remove the SQL resources:

```powershell
# Delete SQL Server (includes database and private endpoint)
az sql server delete `
  --name sql-pp-XXXX `
  --resource-group rg-pp-vnet `
  --yes

# Delete Private DNS Zone
az network private-dns zone delete `
  --name privatelink.database.windows.net `
  --resource-group rg-pp-vnet `
  --yes

# Optional: Delete Private Endpoint subnets
az network vnet subnet delete `
  --name subnet-private-endpoints-west `
  --vnet-name vnet-pp-westeurope `
  --resource-group rg-pp-vnet
```

Or use the main cleanup script with additional flags (if extended).

## Additional Resources

- [Power Platform VNet Support](https://learn.microsoft.com/power-platform/admin/vnet-support-overview)
- [Azure SQL Private Endpoint](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview)
- [SQL Server Connector Reference](https://learn.microsoft.com/connectors/sql/)
- [Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-overview)

## Notes

- Private connectivity works only for environments with VNet integration enabled
- The Enterprise Policy must be properly configured and linked
- DNS resolution happens automatically via Private DNS Zones
- No on-premises data gateway required
- Latency should be lower than gateway-based connections
- Costs: Private Endpoint (~$7/month), DNS Zone (~$0.50/month), SQL Database (varies by tier)
