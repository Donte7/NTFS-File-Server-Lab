# ============================================
# CURRENT CLIENT IDENTITY
# Dynamically resolves whoever ran az login
# Used to grant Key Vault access to deployer
# ============================================
data "azurerm_client_config" "current" {}

# ============================================
# RANDOM SUFFIX FOR KEY VAULT NAME
# Key Vault names must be globally unique
# across ALL of Azure — not just your account
# 4 bytes = 8 hex characters of randomness
# ============================================
resource "random_id" "kv_suffix" {
  byte_length = 4
}

# ============================================
# KEY VAULT
# Stores admin password as encrypted secret
# configure-lab.ps1 retrieves it at runtime
# RBAC model enabled — required for modern auth
# ============================================
resource "azurerm_key_vault" "lab_kv" {
  name                       = "kv-fslab-${random_id.kv_suffix.hex}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# ============================================
# ROLE ASSIGNMENT
# Grants YOUR identity permission to write
# secrets into the Key Vault
# Without this — 403 Forbidden on secret write
# current.object_id = whoever ran az login
# ============================================
resource "azurerm_role_assignment" "kv_deployer_access" {
  scope                = azurerm_key_vault.lab_kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================
# SECRET — ADMIN PASSWORD
# Stored once, retrieved at runtime
# depends_on ensures role assignment propagates
# before Terraform tries to write the secret
# Without depends_on you get 403 even with
# correct role assignment
# ============================================
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.lab_kv.id

  depends_on = [azurerm_role_assignment.kv_deployer_access]

  tags = {
    ManagedBy = "Terraform"
  }
}