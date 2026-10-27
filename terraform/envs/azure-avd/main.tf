#==============================================================
# env: azure-avd — Azure Virtual Desktop 長駐環境
#
# 拓樸：
#   你的電腦 / 瀏覽器
#     │  HTTPS via AVD Gateway（Microsoft 管理，不需開 Port）
#     ▼
#   AVD Workspace ──► App Group ──► Host Pool
#                                       │
#                               Session Host VM(s)
#                               Windows 11 multi-session + M365
#                               VNet 10.60.0.0/16（Private，無 Public IP）
#==============================================================

# ── Resource Group ────────────────────────────────────────────
resource "azurerm_resource_group" "avd" {
  name     = "${var.project}-rg"
  location = var.location
  tags     = local.common_tags
}

# ── VNet ─────────────────────────────────────────────────────
resource "azurerm_virtual_network" "avd" {
  name                = "${var.project}-vnet"
  resource_group_name = local.rg
  location            = local.location
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "avd" {
  name                 = "${var.project}-subnet"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.subnet_cidr]
}

# ── NSG（AVD 不需要 Inbound，只需 Outbound 443 到 AVD Gateway）
resource "azurerm_network_security_group" "avd" {
  name                = "${var.project}-nsg"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.common_tags

  # 允許 VNet 內部通訊（Session Host ↔ 其他服務）
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

  # ⚠️ 無需開放 RDP 3389（流量走 AVD Gateway HTTPS，不直連）
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  subnet_id                 = azurerm_subnet.avd.id
  network_security_group_id = azurerm_network_security_group.avd.id
}

# ── NIC（無 Public IP）────────────────────────────────────────
resource "azurerm_network_interface" "session_host" {
  count               = var.vm_count
  name                = "${var.project}-nic-${count.index}"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.avd.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ── Session Host VM(s) ────────────────────────────────────────
# Windows 11 multi-session + M365，Entra ID Join（SystemAssigned identity）
resource "azurerm_windows_virtual_machine" "session_host" {
  count               = var.vm_count
  name                = "${var.project}-vm-${count.index}"
  computer_name       = "avd-sh-${count.index}" # 最多 15 字元
  resource_group_name = local.rg
  location            = local.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  license_type        = "Windows_Client" # AVD multi-session 授權
  secure_boot_enabled = true             # Trusted Launch
  vtpm_enabled        = true             # Trusted Launch
  tags                = local.common_tags

  network_interface_ids = [azurerm_network_interface.session_host[count.index].id]

  additional_capabilities {
    hibernation_enabled = false
    ultra_ssd_enabled   = false
  }

  identity {
    type = "SystemAssigned" # Entra ID Join 需要
  }

  os_disk {
    name                 = "${var.project}-osdisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "office-365"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }
}

# ── Session Host Extensions ──────────────────────────────────
# 1. 加入 Microsoft Entra ID (Azure AD)
resource "azurerm_virtual_machine_extension" "aad_login" {
  count                      = var.vm_count
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  tags                       = local.common_tags
}

# 2. 自動註冊 Session Host 到 AVD Host Pool
resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                      = var.vm_count
  name                       = "AVD-Agent"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true
  tags                       = local.common_tags

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://raw.githubusercontent.com/Azure/RDS-Templates/master/wvd-templates/DSC/Configuration.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName": "${azurerm_virtual_desktop_host_pool.avd.name}",
        "aadJoin": true
      }
    }
  SETTINGS

  protected_settings = <<-PROTECTED_SETTINGS
    {
      "properties": {
        "registrationInfoToken": "${azurerm_virtual_desktop_host_pool_registration_info.avd.token}"
      }
    }
  PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_machine_extension.aad_login
  ]
}

# ── AVD Host Pool ────────────────────────────────────────────
resource "azurerm_virtual_desktop_host_pool" "avd" {
  name                     = "${var.project}-hostpool"
  resource_group_name      = local.rg
  location                 = local.location
  type                     = var.host_pool_type
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = var.max_sessions
  preferred_app_group_type = "Desktop"
  start_vm_on_connect      = false
  tags                     = local.common_tags

  # Entra ID SSO + 多螢幕 + 磁碟機轉接 + WebAuthn
  custom_rdp_properties = "drivestoredirect:s:*;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;devicestoredirect:s:*;redirectcomports:i:1;redirectsmartcards:i:1;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;enablerdsaadauth:i:1;"
}

# ── Host Pool Registration Token（Session Host 加入 Pool 用）──
resource "time_offset" "avd_token_expiration" {
  offset_days = 2
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "avd" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.avd.id
  expiration_date = time_offset.avd_token_expiration.rfc3339
}

# ── AVD Workspace ────────────────────────────────────────────
resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = "${var.project}-workspace"
  resource_group_name = local.rg
  location            = local.location
  friendly_name       = "AVD Workspace"
  tags                = local.common_tags
}

# ── AVD Application Group（Desktop 類型）────────────────────
resource "azurerm_virtual_desktop_application_group" "avd" {
  name                         = "${var.project}-appgroup"
  resource_group_name          = local.rg
  location                     = local.location
  type                         = "Desktop"
  host_pool_id                 = azurerm_virtual_desktop_host_pool.avd.id
  friendly_name                = "Desktop"
  default_desktop_display_name = "SessionDesktop"
  tags                         = local.common_tags
}

# ── Workspace ↔ App Group 關聯 ───────────────────────────────
resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.avd.id
}
