#--------------------------------------------------------------
# Resource Group（可選：create_resource_group = false 時複用已有 RG）
#--------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group ? 1 : 0
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

#--------------------------------------------------------------
# Virtual Network
#--------------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name_prefix}-vnet"
  address_space       = [var.vnet_cidr]
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = local.common_tags
}

#--------------------------------------------------------------
# Public Subnets
#--------------------------------------------------------------
resource "azurerm_subnet" "public" {
  for_each = var.public_subnets

  name                 = "${var.name_prefix}-${each.key}"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]
}

#--------------------------------------------------------------
# Private Subnets
#--------------------------------------------------------------
resource "azurerm_subnet" "private" {
  for_each = var.private_subnets

  name                 = "${var.name_prefix}-${each.key}"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]
}

#--------------------------------------------------------------
# NSG — Public（允許 my_ip SSH + 自訂 port）
#--------------------------------------------------------------
resource "azurerm_network_security_group" "public" {
  name                = "${var.name_prefix}-public-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = { for idx, port in var.extra_public_ports : tostring(idx) => port }
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
# NSG — Private（僅允許 VNet 內部流量）
#--------------------------------------------------------------
resource "azurerm_network_security_group" "private" {
  name                = "${var.name_prefix}-private-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

#--------------------------------------------------------------
# NSG 關聯 — Public Subnets
#--------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "public" {
  for_each = azurerm_subnet.public

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.public.id
}

#--------------------------------------------------------------
# NSG 關聯 — Private Subnets
#--------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "private" {
  for_each = azurerm_subnet.private

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.private.id
}
