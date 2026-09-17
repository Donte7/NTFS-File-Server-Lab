Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# VARIABLES
# ============================================
$gpoName = "Lab - Allow RDP for Domain Users"
$ouPath  = "OU=Lab Computers,DC=lab,DC=local"

# ============================================
# STEP 1 — CREATE THE GPO
# Creates an empty policy object
# Name is descriptive — tells admins exactly
# what this policy does at a glance
# ============================================
Write-Host "`nCreating GPO..." -ForegroundColor Yellow
New-GPO -Name $gpoName | Out-Null
Write-Host "  Created: $gpoName" -ForegroundColor Cyan

# ============================================
# STEP 2 — LINK GPO TO LAB COMPUTERS OU
# Linking makes the policy ACTIVE
# Any computer in Lab Computers OU
# receives this policy automatically
# Creating a GPO without linking = no effect
# ============================================
Write-Host "`nLinking GPO to Lab Computers OU..." -ForegroundColor Yellow
New-GPLink -Name $gpoName -Target $ouPath
Write-Host "  Linked to: $ouPath" -ForegroundColor Cyan

# ============================================
# STEP 3 — SET REGISTRY VALUE VIA GPO
# fDenyTSConnections = 0 means RDP allowed
# fDenyTSConnections = 1 means RDP denied
# GPO pushes this registry change to all
# computers in the linked OU automatically
# ============================================
Write-Host "`nConfiguring RDP registry setting..." -ForegroundColor Yellow
Set-GPRegistryValue `
    -Name $gpoName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" `
    -Type DWord `
    -Value 0
Write-Host "  fDenyTSConnections set to 0 (RDP enabled)" -ForegroundColor Cyan

# ============================================
# STEP 4 — MOVE CLIENT01 TO LAB COMPUTERS OU
# GPO only applies to computers IN this OU
# CLIENT01 starts in default Computers container
# Moving it here triggers GPO application
# FS01 stays in default location — servers
# do not need this RDP policy
# ============================================
Write-Host "`nMoving CLIENT01 to Lab Computers OU..." -ForegroundColor Yellow
$computer = Get-ADComputer `
    -Filter { Name -eq "CLIENT01" } `
    -ErrorAction SilentlyContinue

if ($computer) {
    $computer | Move-ADObject -TargetPath $ouPath
    Write-Host "  Moved CLIENT01 to: $ouPath" -ForegroundColor Cyan
} else {
    Write-Warning "  CLIENT01 not found in AD yet — may still be joining domain"
    Write-Warning "  Run gpupdate /force on CLIENT01 after domain join completes"
}

Write-Host "`nGPO configuration complete." -ForegroundColor Green