// sample usage: az deployment group create --resource-group {your resource group} --template-file template.bicep --parameters adminUsername={your username} qualifier=1

param location string = 'eastus'
param qualifier string

param adminUsername string
@secure()
param adminPassword string

var vmName = 'nodes-vm-${qualifier}'

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: 'clarinet-vnet'
}

resource nic 'Microsoft.Network/networkInterfaces@2022-11-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
            properties: {
              deleteOption: 'Delete'
            }
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2019-02-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIpAddresses@2020-08-01' = {
  name: '${vmName}-ip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
  ]
}

resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      osDisk: {
        createOption: 'fromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  zones: [
    '1'
  ]
}

resource setup 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: '${vmName}-ext'
  location: location
  parent: vm
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: 'H4sIAESXY2UAA6VV23LTMBB991dshYcmtM6tlynpGIY/6AyPhMkoshwLbMnIcpNS+u+s5MSW3TB9oC+p9qI9e86u9e5suhFyuqFVFgRMc2r4mimZim01GsNzAPiXK0ZzkHVx9MTh3HMkQnNmlH5a1zqPw8Ugp+RcY8aVZy6EPJqvPTNlRjwK84Q+LVQShzee0yhD87UNURLzbgPP18BaG16UOTYQnze4VyQXm3JRrsjy0EljLZU21hbafy49B+PaPFCTWeeKrIjvSzadJxU5Xy4LXmDTy8+MsozHVUY1T1bEpbxcHgDQBHv9Z33nXdtjP6ui2Aj/Ur5C3lLd4Ah71PfxIvUPlmJXqNXBj8DaXUQriR9xFOTB6fGVsyZ2oJOf4VT60ojkYnuyNV0GL8F5o16qNAgQEsJRxX/BvAF6GLLxPSSqvboR2lIVh6PR9Ww2uxDj8cDd8WmD7k4HHYZF0oLHZMtl1BjCZ/Ey+VEpSdp4zjIFxC2FkNtDIoTeBV7sI15NXAbqMhjIFSHwCcjrzERJjnQEQlZIE/JUlu3WiRS+fYPoN+aNdplgGey23IwJfP9+Dybjsq1d1YkCWhqoywSrvbYfrncXQPTUcC8aDZwtM6asltPpVpis3kyYKqZUq43g848fF1OWUy0kN1EzlxGinGq6mxYUvxwsV3VyKiTKhaz30f7udn177XV0BlGKrL6RcKLNRo6U4vIl+DlA8nYyVzQBvuesNnST+3rshYH5sVP7w7JCJXCxhzexoiDIlzZrqRJeDQT5T/gYCFIZKDWvuEQ1ItgJlEaq3VGmrglvLHqa2b1hqV2cbn4/uOE9sTO/apqLVHAd4yA5ECHm/gGkDFuZQ5TA+eR8PBx7x4Ade4zufJM3lbZjnrpxt+xF4XNb/2WSqy2Bxaf3c3jf9ehYRWhlBRG3wLaal4dbogI/CkeosLBYyYTgDpzFQN6GEra1T+hxaqRc0/2OB8PkDdRxef2H8Srov4btKXoslnezu1nQPYk3QfcOLoLh43cT9F+8+SwIip94H7R9ByzxD73HGwn0cBEYvBXk4HfV7aGFYg8DLNbUA0P8/fgLWRltokIIAAA='
    }
  }
}
