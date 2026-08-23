data "azurerm_resource_group" "build" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "build" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "build" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.build.name
  resource_group_name  = var.resource_group_name
}

data "azurerm_user_assigned_identity" "citrix_build" {
  name                = var.citrix_build_identity_name
  resource_group_name = var.citrix_build_identity_resource_group
}

resource "azurerm_network_interface" "vm" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  accelerated_networking_enabled = true
  dns_servers                     = [var.dns_server]

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = data.azurerm_subnet.build.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  computer_name       = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  admin_username = "azureuser"
  admin_password = var.admin_password

  network_interface_ids = [azurerm_network_interface.vm.id]

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.citrix_build.id]
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  secure_boot_enabled = true
  vtpm_enabled        = true
  provision_vm_agent  = true

  patch_assessment_mode = "ImageDefault"
  patch_mode            = "AutomaticByOS"

  boot_diagnostics {
    storage_account_uri = null
  }

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Windows2022-Test"
  }
}
