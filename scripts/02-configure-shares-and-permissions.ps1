Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# VARIABLES
# ============================================
$domain   = "LAB"
$basePath = "C:\Shares"

# ============================================
# STEP 1 — CREATE BASE FOLDER
# All four share folders live under C:\Shares
# ============================================
Write-Host "`nCreating share folders..." -ForegroundColor Yellow
New-Item -Path $basePath -ItemType Directory -Force

foreach ($folder in @("Finance", "HR", "Sales", "IT")) {
    New-Item -Path "$basePath\$folder" -ItemType Directory -Force
    Write-Host "  Created: $basePath\$folder" -ForegroundColor Cyan
}

# ============================================
# STEP 2 — CREATE SMB SHARES
# Share level = Everyone Full Control
# INTENTIONAL — real security comes from NTFS
# Mixing share and NTFS restrictions causes
# confusing access denied errors that are
# hard to troubleshoot
# ============================================
Write-Host "`nCreating SMB shares..." -ForegroundColor Yellow

foreach ($folder in @("Finance", "HR", "Sales", "IT")) {
    New-SmbShare `
        -Name $folder `
        -Path "$basePath\$folder" `
        -FullAccess "Everyone"
    Write-Host "  Shared: \\FS01\$folder" -ForegroundColor Cyan
}

# ============================================
# HELPER FUNCTION — SET NTFS PERMISSIONS
# Removes ALL default permissions first
# Then applies only what we explicitly define
# (OI)(CI) = Object Inherit + Container Inherit
# Files AND subfolders inherit these rules
# ============================================
function Set-FolderPermissions {
    param(
        [string]$path,
        [array]$permissions
    )

    # Remove inheritance — folder manages own ACL
    icacls $path /inheritance:d

    # Remove default groups that allow broad access
    icacls $path /remove "BUILTIN\Users"
    icacls $path /remove "Everyone"
    icacls $path /remove "NT AUTHORITY\Authenticated Users"

    # Apply each explicit permission entry
    foreach ($p in $permissions) {
        icacls $path /grant "$($p.Identity)`:$($p.Rights)"
    }

    Write-Host "  Permissions set on: $path" -ForegroundColor Cyan
}

# ============================================
# STEP 3 — APPLY NTFS PERMISSIONS PER SHARE
#
# FINANCE:
#   GRP_Finance = Modify     (read + write)
#   GRP_HR      = Read only  (cross-dept reporting)
#   GRP_IT      = Full Control
#   Administrators = Full Control
#
# HR:
#   GRP_HR  = Modify
#   GRP_IT  = Full Control
#   Administrators = Full Control
#
# SALES:
#   GRP_Sales = Modify
#   GRP_IT    = Full Control
#   Administrators = Full Control
#
# IT:
#   GRP_IT = Full Control
#   Administrators = Full Control
# ============================================
Write-Host "`nApplying NTFS permissions..." -ForegroundColor Yellow

Set-FolderPermissions -path "$basePath\Finance" -permissions @(
    @{Identity="$domain\GRP_Finance";    Rights="(OI)(CI)M"},
    @{Identity="$domain\GRP_HR";         Rights="(OI)(CI)R"},
    @{Identity="$domain\GRP_IT";         Rights="(OI)(CI)F"},
    @{Identity="BUILTIN\Administrators"; Rights="(OI)(CI)F"}
)

Set-FolderPermissions -path "$basePath\HR" -permissions @(
    @{Identity="$domain\GRP_HR";         Rights="(OI)(CI)M"},
    @{Identity="$domain\GRP_IT";         Rights="(OI)(CI)F"},
    @{Identity="BUILTIN\Administrators"; Rights="(OI)(CI)F"}
)

Set-FolderPermissions -path "$basePath\Sales" -permissions @(
    @{Identity="$domain\GRP_Sales";      Rights="(OI)(CI)M"},
    @{Identity="$domain\GRP_IT";         Rights="(OI)(CI)F"},
    @{Identity="BUILTIN\Administrators"; Rights="(OI)(CI)F"}
)

Set-FolderPermissions -path "$basePath\IT" -permissions @(
    @{Identity="$domain\GRP_IT";         Rights="(OI)(CI)F"},
    @{Identity="BUILTIN\Administrators"; Rights="(OI)(CI)F"}
)

Write-Host "`nShares and permissions configured." -ForegroundColor Green