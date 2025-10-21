// Bicep template for Azure SQL with Private Endpoint
// Creates subnets for Private Endpoints, SQL Server, Database, Private Endpoint and DNS configuration

@description('Location for SQL resources')
param location string = 'westeurope'

@description('Primary VNet name')
param primaryVnetName string = 'vnet-pp-westeurope'

@description('Secondary VNet name')
param secondaryVnetName string = 'vnet-pp-northeurope'

@description('SQL Server name (must be globally unique)')
param sqlServerName string = 'sql-pp-${uniqueString(resourceGroup().id)}'

@description('SQL Database name')
param databaseName string = 'db-powerplatform-test'

@description('SQL Admin username')
@secure()
param sqlAdminUsername string

@description('SQL Admin password')
@secure()
param sqlAdminPassword string

@description('Enable Azure AD authentication')
param enableAzureAD bool = true

@description('Azure AD admin object ID')
param azureAdAdminObjectId string = ''

@description('Azure AD admin email')
param azureAdAdminEmail string = ''

// Reference existing VNets
resource primaryVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: primaryVnetName
}

resource secondaryVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: secondaryVnetName
}

// Create subnet for Private Endpoints in primary VNet (West Europe)
resource privateEndpointSubnetWest 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: primaryVnet
  name: 'subnet-private-endpoints-west'
  properties: {
    addressPrefix: '10.0.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Create subnet for Private Endpoints in secondary VNet (North Europe)
resource privateEndpointSubnetNorth 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: secondaryVnet
  name: 'subnet-private-endpoints-north'
  properties: {
    addressPrefix: '10.1.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled' // Disable public access
    restrictOutboundNetworkAccess: 'Disabled'
    administrators: enableAzureAD && !empty(azureAdAdminObjectId) ? {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: azureAdAdminEmail
      sid: azureAdAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: false
    } : null
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Private DNS Zone for SQL
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  properties: {}
}

// Link DNS Zone to primary VNet
resource dnsZoneLinkWest 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-to-${primaryVnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: primaryVnet.id
    }
  }
}

// Link DNS Zone to secondary VNet
resource dnsZoneLinkNorth 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-to-${secondaryVnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: secondaryVnet.id
    }
  }
}

// Private Endpoint for SQL (West Europe)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${sqlServerName}-west'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetWest.id
    }
    privateLinkServiceConnections: [
      {
        name: 'sql-private-connection'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
  dependsOn: [
    sqlDatabase
  ]
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Note: Sample table should be created manually or via Azure Data Studio after deployment
// Deployment scripts require storage account configuration which may have auth restrictions

// Outputs
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlDatabase.name
output privateEndpointId string = privateEndpoint.id
output privateDnsZoneName string = privateDnsZone.name
output connectionStringTemplate string = 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database=${databaseName};User Id=<USERNAME>;Password=<PASSWORD>;Encrypt=True;TrustServerCertificate=False;'
