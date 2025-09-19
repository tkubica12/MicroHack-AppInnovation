# Virtual Machine
resource "azapi_resource" "vm" {
  type      = "Microsoft.Compute/virtualMachines@2023-09-01"
  name      = local.vm_name
  location  = var.location
  parent_id = azapi_resource.rg.id
  body = {
    properties = {
      hardwareProfile = { vmSize = var.vm_size }
      storageProfile = {
        osDisk = {
          createOption = "FromImage"
          deleteOption = "Delete"
          managedDisk  = { storageAccountType = "Premium_LRS" }
        }
        imageReference = {
          publisher = "MicrosoftWindowsServer"
          offer     = "WindowsServer"
          sku       = "2025-datacenter-azure-edition"
          version   = "latest"
        }
      }
      osProfile = {
        computerName  = local.vm_name
        adminUsername = var.admin_username
        adminPassword = var.admin_password
        windowsConfiguration = {
          enableAutomaticUpdates = true
          patchSettings          = { patchMode = "AutomaticByPlatform" }
        }
      }
      networkProfile = {
        networkInterfaces = [
          { id = azapi_resource.nic.id, properties = { primary = true } }
        ]
      }
    }
    identity = {
      type = "SystemAssigned"
    }
  }
  depends_on = [azapi_resource.nic]
}

# Custom Script Extension
resource "azapi_resource" "vm_setup" {
  type      = "Microsoft.Compute/virtualMachines/extensions@2023-09-01"
  name      = "setup"
  location  = var.location
  parent_id = azapi_resource.vm.id
  body = {
    properties = {
      publisher               = "Microsoft.Compute"
      type                    = "CustomScriptExtension"
      typeHandlerVersion      = "1.10"
      autoUpgradeMinorVersion = true
      protectedSettings = {
        fileUris         = local.provisioning_scripts
        commandToExecute = "powershell -ExecutionPolicy Bypass -File setup.ps1"
      }
    }
  }
  depends_on = [azapi_resource.vm]
}
