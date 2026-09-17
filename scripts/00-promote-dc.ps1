Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# STEP 1 — Install Active Directory role
# AD-Domain-Services is the Windows feature
# that enables Active Directory functionality
# IncludeManagementTools adds PowerShell
# cmdlets like New-ADUser, Get-ADGroup etc
# ============================================
Write-Host "Installing AD DS role..." -ForegroundColor Yellow
Install-WindowsFeature `
    -Name AD-Domain-Services `
    -IncludeManagementTools `
    -Verbose:$false

# ============================================
# STEP 2 — Convert password to secure string
# SAFE_MODE_PASSWORD is replaced at runtime
# by configure-lab.ps1 with value from
# Key Vault — never hardcoded here
# ============================================
$safeModePassword = ConvertTo-SecureString `
    "SAFE_MODE_PASSWORD" `
    -AsPlainText `
    -Force

# ============================================
# STEP 3 — Import AD deployment module
# Required before Install-ADDSForest
# ============================================
Import-Module ADDSDeployment

# ============================================
# STEP 4 — Promote DC01 to Domain Controller
# Creates lab.local forest from scratch
# InstallDns:$true — DC01 becomes DNS server
# NoRebootOnCompletion:$false — reboots after
# configure-lab.ps1 detects disconnect
# and waits for DC01 to come back online
# ============================================
Write-Host "Promoting DC01 to Domain Controller..." -ForegroundColor Yellow
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword $safeModePassword `
    -Force:$true `
    -NoRebootOnCompletion:$false

# DC01 reboots here automatically
# configure-lab.ps1 waits for it to
# come back online before proceeding