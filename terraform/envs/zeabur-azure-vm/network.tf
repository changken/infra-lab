resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "snet-${local.name_prefix}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  dynamic "security_rule" {
    for_each = local.inbound_rule_ssh

    content {
      name                       = "allow-${replace(security_rule.key, "_", "-")}-inbound"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*" # TCP + UDP（NodePort 可能有 UDP service）
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = var.allowed_source_prefix_ssh
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = local.inbound_rules

    content {
      name                       = "allow-${replace(security_rule.key, "_", "-")}-inbound"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*" # TCP + UDP（NodePort 可能有 UDP service）
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = var.allowed_source_prefix
      destination_address_prefix = "*"
    }
  }
}

# NSG 掛在兩個 subnet 上，之後 subnet2 開 VM 也吃同一套規則
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = azurerm_subnet.this

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.this.id
}
