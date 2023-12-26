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
      // Encode script using: cat vm-setup.sh | gzip | base64
      script: 'H4sIACVWi2UAA6VV23LTMBB991dshYcmgHOj7ZQwhuEPOsNj08koshwLbMnIcpNS8u+s5MSW3TB9oC+p9iKdPWfX++ZiuhFyuqFVFgRMc2r4mimZim01GsNzAPiXK0ZzkHVx8sTh3HMkQnNmlH5a1zqPw8Ugp+RcY8ZHz1wIeTJfeWbKjHgU5gl9WqgkDq89p1GG5msboiTm3QSer4G1Nrwocywgvmxwr0guNuWiXJHlsZLGWiptrC20/3zwHIxrc0dNZp0rsiK+L9l0nlTkfLkseIFFL78yyjIeVxnVPFkRl3L4cARAE6z1n+8779oe+1kVxUL4t/IF8pbqBkfYo76PF6m/sxS7h1od/Ah8u4toJfEjToLcOT2+c9bEDnTyM5xK3xqRXGxPtqbK4BBcNuqlSoMAISEcVfwXzBugxyYbf4ZEtVc3Qluq4nA0uprNZu/FeDxwd3zaoNvzQcdmkbTgMdlyGTWG8FkcJj8qJUkbz1mmgLihEHJ7TITQu8CLfcSrictAXQYNuSIEvgB5mZkoyZGOQMgKaUKeyrKdOpHC/T1EvzFvtMsEy2C35WZM4OHhM5iMy/btqk4U0NJAXSb42kv78Xp3AURPDfei0cDZMmPKajmdboXJ6s2EqWJKtdoIPv/0aTFlOdVCchM1fRkhyqmmu2lB8cvBclUn50KiXMh6H+1vb9Y3V15FFxClyOorCWfKbORIKQ5fgp8DJG8nc0UT4HvOakM3ua/HXhiYnyq1PywrVALv9/AqVhQE+dJmLVXCq4Eg/wkfA0EqA6XmFZeoRgQ7gdJItTvJ1BXhtUVPMzs3LLWD0/XvO9e8Z2bmV01zkQquY2wkByLE3D+AlGEpc4gSuJxcjodt7xiwbY/RnW/yqtK2zVPX7pa9KHxu3z9McrUlsPjydg5vuxodqwitrCDiFthW8/J4S1TgR+EEFRYWK5kQnIGLGMjrUML27TN6nGspV3S/4kEzeQ11Gl5/MV4H/W3YnqLHYnk7u50F3UqcXwfdIsTDcP3NJovroL/25vhJC4LiJ14LbfkBS/xDb4cjjx48AoOVQY5+h8EeWkD2MABkTT04xB+Tv0eHGXtJCAAA'
    }
  }
}
