# ============================================
# DC01 PUBLIC IP
# Use this to RDP directly into the domain
# controller if needed for troubleshooting
# ============================================
output "dc01_public_ip" {
  value       = azurerm_public_ip.dc01.ip_address
  description = "DC01 public IP address."
}

# ============================================
# DC01 PRIVATE IP
# Always 10.0.1.4 — static
# FS01 and CLIENT01 point DNS here
# ============================================
output "dc01_private_ip" {
  value       = azurerm_network_interface.dc01.private_ip_address
  description = "DC01 static private IP — always 10.0.1.4."
}

# ============================================
# FS01 PUBLIC IP
# Use this to RDP into file server
# if needed for troubleshooting shares
# ============================================
output "fs01_public_ip" {
  value       = azurerm_public_ip.fs01.ip_address
  description = "FS01 public IP address."
}

# ============================================
# CLIENT01 PUBLIC IP
# THIS is the machine you RDP into
# Log in as test users here to verify
# NTFS permissions in Step 9
# ============================================
output "client01_public_ip" {
  value       = azurerm_public_ip.client01.ip_address
  description = "CLIENT01 public IP — RDP here as test users."
}

# ============================================
# KEY VAULT NAME
# COPY THIS IMMEDIATELY after terraform apply
# Pass it to configure-lab.ps1 like this:
# .\configure-lab.ps1 -KeyVaultName "kv-fslab-xxxxxxxx"
# ============================================
output "key_vault_name" {
  value       = azurerm_key_vault.lab_kv.name
  description = "Pass to configure-lab.ps1 with -KeyVaultName flag."
}
