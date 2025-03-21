@description('The name of the App Gateway that will be deployed')
param appGatewayName string

@description('The name of the IP address that will be deployed')
param ipAddressName string

@description('The subnet ID that will be used for the App Gateway configuration')
param subnetId string

@description('The subnet ID of the Container App Environment that will be used for the Private Link service')
param envSubnetId string

@description('The name of the Private Link Service')
param privateLinkServiceName string

@description('The location where the App Gateway will be deployed')
param location string

@description('The tags that will be applied to the App Gateway')
param tags object

@description('collection of backend pools with name and fqdn')
param backendPools array

@description('collection of path maps with backend pool name and mapping path]')
param pathMaps array

var backendPoolsConfig = [
  for pool in backendPools: {
    name: pool.name
    properties: {
      backendAddresses: [
        {
          fqdn: pool.fqdn
        }
      ]
    }
  }
]

var pathRulesConfig = [
  for path in pathMaps: {
    name: path.name
    properties: {
      paths: [
        path.path
      ]
      backendAddressPool: {
        id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, path.backendPoolName)
      }
      backendHttpSettings: {
        id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'my-agw-backend-setting')
      }
      rewriteRuleSet: {
        id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', appGatewayName, 'my-agw-rewrite-set')
      }
    }
  }
]

var rewriteRuleSet = [
  for (path, pathIdx) in pathMaps: {
      ruleSequence: pathIdx+1
      conditions: [
        {
          variable: 'var_uri_path'
          pattern: '${path.pathRewrite}'
          ignoreCase: true
          negate: false
        }
      ]
      name: 'rule-${pathIdx+1}'
      actionSet: {
        requestHeaderConfigurations: []
        responseHeaderConfigurations: []
        urlConfiguration: {
          modifiedPath: '/{var_uri_path_1}'
          reroute: false
        }
      }
  }
] 

resource appGateway 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGatewayName
  location: location
  tags: tags
  zones: [
    '1'
  ]
  properties: {
    sku: {
      tier: 'Standard_v2'
      capacity: 1
      name: 'Standard_v2'
    }
    gatewayIPConfigurations: [
      { 
        name: 'appgateway-subnet'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      { 
        name: 'my-frontend'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
          privateLinkConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/privateLinkConfigurations', appGatewayName, privateLinkServiceName)
          }
        }
      }
    ]
    privateLinkConfigurations: [
      { 
        name: privateLinkServiceName
        properties: {
          ipConfigurations: [
            { 
              name: 'my-agw-private-link-config'
              properties: {
                primary: true
                privateIPAllocationMethod: 'Dynamic'
                subnet: {
                  id: subnetId
                }
              }
            }
          ]
        }
      }
    ]
    frontendPorts: [
      { 
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: backendPoolsConfig

    backendHttpSettingsCollection: [
      { 
        name: 'my-agw-backend-setting'
        properties: {
          protocol: 'Https'
          port: 443
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
          pickHostNameFromBackendAddress: true
        }
      }
    ]
    httpListeners: [
      { 
        name: 'my-agw-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'my-frontend')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    urlPathMaps: [
      { 
        name: 'my-agw-url-path-map'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, pathMaps[0].backendPoolName)
          }
          defaultBackendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'my-agw-backend-setting')
          }
          defaultRewriteRuleSet: {
            id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', appGatewayName, 'my-agw-rewrite-set')
          }
          pathRules: pathRulesConfig
        }
      }
    ]
    requestRoutingRules: [
      { 
        name: 'my-agw-routing-rule'
        properties: {
          priority: 1
          ruleType: 'PathBasedRouting'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'my-agw-listener')
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', appGatewayName, 'my-agw-url-path-map')
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: 'my-agw-rewrite-set'
        properties: {
          rewriteRules: rewriteRuleSet
        }
      }
    ]
    enableHttp2: true
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: ipAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
  ]
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

