# ============================================
# RESOURCE GROUP
# Container for every resource in this lab
# Lab 2 references this name — never change it
# ============================================
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ============================================
# VIRTUAL NETWORK
# Private network — 10.0.0.0/16
# 65,536 available addresses
# ============================================
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

# ============================================
# DELIBERATE PAUSE — 45 seconds
# Azure control plane replication delay
# Subnet creation immediately after VNet
# creation causes transient not found errors
# ============================================
resource "time_sleep" "wait_after_vnet" {
  create_duration = "45s"
  depends_on      = [azurerm_virtual_network.vnet]
}
# ============================================
# SUBNET
# 10.0.1.0/24 — 251 usable addresses
# All three VMs live here
# ============================================
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
  depends_on           = [time_sleep.wait_after_vnet]
}

# ============================================
# NETWORK SECURITY GROUP
# ONE inbound rule — RDP from your IP only
# Everything else denied implicitly by Azure
# ============================================
resource "azurerm_network_security_group" "nsg" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP-3389"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.rdp_source
    source_port_range          = "*"
    destination_port_range     = "3389"
    destination_address_prefix = "*"
  }

  depends_on = [time_sleep.wait_after_vnet]
}

# ============================================
# DELIBERATE PAUSE — 45 seconds after NSG
# Same replication delay pattern as VNet
# Public IPs and NICs depend on this
# ============================================
resource "time_sleep" "wait_after_nsg" {
  create_duration = "45s"
  depends_on      = [azurerm_network_security_group.nsg]
}
# ============================================
# PUBLIC IP ADDRESSES
# Standard SKU required for static allocation
# One per VM — needed for RDP from your machine
# ============================================
resource "azurerm_public_ip" "dc01" {
  name                = "dc01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}

resource "azurerm_public_ip" "fs01" {
  name                = "fs01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}

resource "azurerm_public_ip" "client01" {
  name                = "client01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}

# ============================================
# NETWORK INTERFACE CARDS
# DC01 gets a STATIC private IP — 10.0.1.4
# FS01 and CLIENT01 get dynamic private IPs
# ============================================
resource "azurerm_network_interface" "dc01" {
  name                = "dc01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.7"
    public_ip_address_id          = azurerm_public_ip.dc01.id
  }

  depends_on = [time_sleep.wait_after_nsg]
}

resource "azurerm_network_interface" "fs01" {
  name                = "fs01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fs01.id
  }

  depends_on = [time_sleep.wait_after_nsg]
}

resource "azurerm_network_interface" "client01" {
  name                = "client01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client01.id
  }

  depends_on = [time_sleep.wait_after_nsg]
}

# ============================================
# NSG ASSOCIATIONS
# Attaches NSG to every NIC
# Without this the NSG exists but protects nothing
# ============================================
resource "azurerm_network_interface_security_group_association" "dc01" {
  network_interface_id      = azurerm_network_interface.dc01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}

resource "azurerm_network_interface_security_group_association" "fs01" {
  network_interface_id      = azurerm_network_interface.fs01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}

resource "azurerm_network_interface_security_group_association" "client01" {
  network_interface_id      = azurerm_network_interface.client01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}
# ============================================
# DC01 — DOMAIN CONTROLLER
# Windows Server 2022 Azure Edition
# Runs Active Directory, DNS, Group Policy
# Static IP 10.0.1.4 set on NIC above
# ============================================
resource "azurerm_windows_virtual_machine" "dc01" {
  name                  = "DC01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.server_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  depends_on = [time_sleep.wait_after_nsg]
}

# ============================================
# FS01 — FILE SERVER
# Windows Server 2022 Azure Edition
# Hosts SMB shares with NTFS permissions
# Joins lab.local domain after DC01 is ready
# ============================================
resource "azurerm_windows_virtual_machine" "fs01" {
  name                  = "FS01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.server_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.fs01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  depends_on = [time_sleep.wait_after_nsg]
}

# ============================================
# CLIENT01 — WINDOWS 11 WORKSTATION
# Ships with RDP disabled by default
# Extension below enables it automatically
# Test users log in here to verify permissions
# ============================================
resource "azurerm_windows_virtual_machine" "client01" {
  name                  = "CLIENT01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.client_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.client01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }

  depends_on = [time_sleep.wait_after_nsg]
}

# ============================================
# ENABLE RDP ON CLIENT01
# Windows 11 ships with RDP disabled
# This extension runs immediately after boot
# Sets fDenyTSConnections = 0
# Opens Windows Firewall rule for RDP
# Without this RDP attempts time out silently
# ============================================
resource "azurerm_virtual_machine_extension" "client01_enable_rdp" {
  name                 = "enable-rdp"
  virtual_machine_id   = azurerm_windows_virtual_machine.client01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -Command \"Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0; Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'\""
  })

  depends_on = [azurerm_windows_virtual_machine.client01]
}