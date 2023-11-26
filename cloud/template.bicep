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
      script: 'IyEvYmluL2Jhc2gKCmNyZWF0ZV9jb25maWdzKCkgewogICAgbG9jYWwgbnVtX2NvbmZpZ3M9JDEKICAgIGxvY2FsIGRpcmVjdG9yeV91cmw9JDIKICAgIGxvY2FsIG51bV9wZWVycz0kMwogICAgbG9jYWwgbWluX3BlZXJzPSQ0CiAgICBsb2NhbCBhY3Rpdml0eV9wZXJpb2Q9JDUKICAgIGxvY2FsIHRvdGFsX2FjdGlvbnM9JDYKCiAgICBsb2NhbCBjb25maWdfdGVtcGxhdGU9J3sKICAgIFwibGlicDJwXCI6IHsKICAgICAgICBcInBvcnRcIjogJHBvcnQsCiAgICAgICAgXCJjZXJ0UGF0aFwiOiBcIlwiLAogICAgICAgIFwiZGJQYXRoXCI6IFwiZmlsZTo6bWVtb3J5Oj9jYWNoZT1zaGFyZWRcIgogICAgfSwKICAgIFwiYWRtaW5cIjogewogICAgICAgIFwicG9ydFwiOiAkYWRtaW5fcG9ydAogICAgfSwKICAgIFwic2FtcGxlQXBwXCI6IHsKICAgICAgICBcImRpcmVjdG9yeVwiOiBcIiRkaXJlY3RvcnlfdXJsXCIsCiAgICAgICAgXCJudW1QZWVyc1wiOiAkbnVtX3BlZXJzLAogICAgICAgIFwibWluUGVlcnNcIjogJG1pbl9wZWVycywKICAgICAgICBcImFjdGl2aXR5UGVyaW9kU2Vjc1wiOiAkYWN0aXZpdHlfcGVyaW9kLAogICAgICAgIFwidG90YWxBY3Rpb25zXCI6ICR0b3RhbF9hY3Rpb25zCiAgICB9Cn0KJwoKICAgIGZvciBpIGluICQoc2VxIDEgJG51bV9jb25maWdzKTsgZG8KICAgICAgICBsb2NhbCBwb3J0PSQoKDQwMDAraSkpCiAgICAgICAgbG9jYWwgYWRtaW5fcG9ydD0kKCg4MDAwK2kpKQogICAgICAgIGxvY2FsIGNvbmZpZ19uYW1lPSJnZW4tY29uZmlnJHtpfS5qc29uIgogICAgICAgIGVjaG8gImNyZWF0aW5nIGNvbmZpZyAkY29uZmlnX25hbWUiCiAgICAgICAgZXZhbCAiZWNobyBcIiRjb25maWdfdGVtcGxhdGVcIiIgPiAiJGNvbmZpZ19uYW1lIgogICAgZG9uZQp9CgppbnN0YWxsX2FwcCgpIHsKICAgIGlmIFtbIC16ICIkKHdoaWNoIHdnZXQpIiBdXTsgdGhlbgogICAgICAgIHN1ZG8gYXB0IHVwZGF0ZQogICAgICAgIHN1ZG8gYXB0IGluc3RhbGwgd2dldCAteQogICAgZmkKCiAgICB3Z2V0IGh0dHBzOi8vZ2l0aHViLmNvbS9hcm9iaWUxOTkyL2NsYXJpbmV0LXNhbXBsZS1hcHAvcmF3L21haW4vY2xhcmluZXQtc2FtcGxlLWFwcC1saW51eC14ODZfNjQKICAgIGlmIFtbICEgLWYgImNsYXJpbmV0LXNhbXBsZS1hcHAtbGludXgteDg2XzY0IiBdXTsgdGhlbgogICAgICAgIGVjaG8gImZhaWxlZCB0byBkb3dubG9hZCBleGVjdXRhYmxlIgogICAgICAgIGV4aXQgMQogICAgZmkKICAgIGNobW9kICt4IGNsYXJpbmV0LXNhbXBsZS1hcHAtbGludXgteDg2XzY0Cn0KCnN0YXJ0X25vZGVzKCkgewogICAgaWYgW1sgISAtZiAiY2xhcmluZXQtc2FtcGxlLWFwcC1saW51eC14ODZfNjQiIF1dOyB0aGVuCiAgICAgICAgZWNobyAiYXBwIG5vdCBwcmVzZW50IC0tIHdpbGwgbm93IGluc3RhbGwiCiAgICAgICAgaW5zdGFsbF9hcHAKICAgIGZpCgogICAgZm9yIGNmIGluIGdlbi1jb25maWcqLmpzb247IGRvCiAgICAgICAgbG9jYWwgcXVhbGlmaWVyPSIkKGVjaG8gJGNmIHwgY3V0IC1mMSAtZCAnLicpIgogICAgICAgIGVjaG8gInN0YXJ0aW5nICRjZiIKICAgICAgICAuL2NsYXJpbmV0LXNhbXBsZS1hcHAtbGludXgteDg2XzY0ICIkY2YiID4gIm5vZGUtJHtxdWFsaWZpZXJ9LmxvZyIgMj4mMSAmCiAgICAgICAgaWYgW1sgIiQocHMgLWVmIHwgZ3JlcCAiJGNmIiAtbSAxIHwgY3V0IC1mIDIgLWQgIi4iKSIgIT0gIi9jbGFyaW5ldC1zYW1wbGUtYXBwLWxpbnV4LXg4Nl82NCAkcXVhbGlmaWVyIiBdXTsgdGhlbgogICAgICAgICAgICBlY2hvICJmYWlsZWQgdG8gc3RhcnQgJGNmIgogICAgICAgICAgICBleGl0IDEKICAgICAgICBmaQogICAgZG9uZQp9CgpudW1fY29uZmlncz0zCmRpcmVjdG9yeV91cmw9ZGlyZWN0b3J5LXZtOjgwODAKbnVtX3BlZXJzPTUKbWluX3BlZXJzPTIKYWN0aXZpdHlfcGVyaW9kPTUKdG90YWxfYWN0aW9ucz0xMAoKbWtkaXIgL2NsYXJpbmV0CmNkIC9jbGFyaW5ldApjcmVhdGVfY29uZmlncyAiJG51bV9jb25maWdzIiAiJGRpcmVjdG9yeV91cmwiICIkbnVtX3BlZXJzIiAiJG1pbl9wZWVycyIgIiRhY3Rpdml0eV9wZXJpb2QiICIkdG90YWxfYWN0aW9ucyIKc3RhcnRfbm9kZXMK'
    }
  }
}
