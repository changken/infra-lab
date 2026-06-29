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
# NIC-level NSG（RDP 3389 + 可選 WinRM + extra ports）
# 不依賴 azure-vnet 的 subnet NSG，模組自帶網路隔離
#--------------------------------------------------------------
resource "azurerm_network_security_group" "vm" {
  name                = "${var.name_prefix}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.enable_winrm ? [1] : []
    content {
      name                       = "AllowWinRMHttps"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5986" # HTTPS only — 5985 (HTTP cleartext) 刻意排除
      source_address_prefix      = var.my_ip
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = { for idx, port in var.extra_inbound_ports : tostring(idx) => port }
    content {
      name                       = "AllowPort${security_rule.value}"
      priority                   = 200 + tonumber(security_rule.key)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = tostring(security_rule.value)
      source_address_prefix      = var.my_ip
      destination_address_prefix = "*"
    }
  }
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
# NIC ↔ NSG 關聯
#--------------------------------------------------------------
resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

#--------------------------------------------------------------
# Windows Virtual Machine
#--------------------------------------------------------------
resource "azurerm_windows_virtual_machine" "vm" {
  name                  = "${var.name_prefix}-vm"
  computer_name         = "${var.name_prefix}-vm"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = local.effective_password
  timezone              = var.timezone
  network_interface_ids = [azurerm_network_interface.vm.id]
  tags                  = local.common_tags

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

  # Azure Edition hotpatch 映像強制要求 AutomaticByPlatform
  patch_mode = "AutomaticByPlatform"

  # Trusted Launch（Windows Server 2019+ 支援）
  secure_boot_enabled = true
  vtpm_enabled        = true
}
