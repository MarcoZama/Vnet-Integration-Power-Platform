// Main Bicep template for VNet integration project
// Creates a resource group, VNets in West and North Europe with subnets, SQL Database, and RBAC assignment

@description('Location for the primary resources (Western Europe)')
param primaryLocation string = 'westeurope'

@description('Location for the secondary resources (North Europe)')
param secondaryLocation string = 'northeurope'

@description('Primary virtual network name (West Europe)')
param primaryVnetName string = 'vnet-pp-westeurope'

@description('Secondary virtual network name (North Europe)')  
param secondaryVnetName string = 'vnet-pp-northeurope'

@description('User email for RBAC assignment')
param userEmail string = ''


// Virtual Network in West Europe with subnet (24+ IPs)
resource primaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: primaryVnetName
  location: primaryLocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-westeurope'
        properties: {
          addressPrefix: '10.0.1.0/27'  // /27 gives 32 addresses, 27 usable (24+ required)
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
            }
          ]
          delegations: [
            {
              name: 'delegation-powerplatform'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}

// Virtual Network in North Europe with subnet (24+ IPs)
resource secondaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: secondaryVnetName
  location: secondaryLocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-northeurope'
        properties: {
          addressPrefix: '10.1.1.0/27'  // /27 gives 32 addresses, 27 usable (24+ required)
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
            }
          ]
          delegations: [
            {
              name: 'delegation-powerplatform'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}


// VNet Peering: West Europe to North Europe
resource vnetPeeringWestToNorth 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: primaryVirtualNetwork
  name: 'west-to-north-peering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: secondaryVirtualNetwork.id
    }
  }
}

// VNet Peering: North Europe to West Europe
resource vnetPeeringNorthToWest 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: secondaryVirtualNetwork
  name: 'north-to-west-peering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: primaryVirtualNetwork.id
    }
  }
}

// RBAC assignment - Reader role for the specified user on the resource group
resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, userEmail, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: userObjectId
    principalType: 'User'
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output primaryVirtualNetworkId string = primaryVirtualNetwork.id
output secondaryVirtualNetworkId string = secondaryVirtualNetwork.id
output westEuropeSubnetId string = primaryVirtualNetwork.properties.subnets[0].id
output northEuropeSubnetId string = secondaryVirtualNetwork.properties.subnets[0].id
