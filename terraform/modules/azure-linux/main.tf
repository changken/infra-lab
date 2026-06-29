#--------------------------------------------------------------
# Public IP（可選，由 create_public_ip 控制）
#--------------------------------------------------------------
resource "azurerm_public_ip" "vm" {
  count               = var.create_public_ip ? 1 : 0
  name                = "${var.name_prefix}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

#--------------------------------------------------------------
# Network Interface
#--------------------------------------------------------------
resource "azurerm_network_interface" "vm" {
  name                = "${var.name_prefix}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.vm[0].id : null
  }
}

#--------------------------------------------------------------
# Linux Virtual Machine
#--------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "${var.name_prefix}-vm"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm.id]
  tags                            = local.common_tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.effective_public_key
  }

  os_disk {
    name                 = "${var.name_prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  custom_data = var.user_data != null ? base64encode(var.user_data) : null

  # Trusted Launch（Ubuntu 20.04+ 支援）
  secure_boot_enabled = true
  vtpm_enabled        = true
}
