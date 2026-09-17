Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# VARIABLES
# ============================================
$rdpGroup    = "Remote Desktop Users"
$domainUsers = "LAB\Domain Users"

# ============================================
# STEP 1 — CHECK IF ALREADY ADDED
# Script is safe to re-run multiple times
# Checks before adding to prevent duplicates
# Duplicate group members cause no harm but
# clean scripts check before acting
# ============================================
Write-Host "`nChecking Remote Desktop Users group..." -ForegroundColor Yellow

$existing = Get-LocalGroupMember `
    -Group $rdpGroup `
    -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $domainUsers }

# ============================================
# STEP 2 — ADD DOMAIN USERS IF NOT PRESENT
# ============================================
if ($existing) {
    Write-Host "  $domainUsers already in $rdpGroup" -ForegroundColor Yellow
    Write-Host "  No changes needed." -ForegroundColor Yellow
} else {
    Add-LocalGroupMember `
        -Group $rdpGroup `
        -Member $domainUsers
    Write-Host "  Added: $domainUsers -> $rdpGroup" -ForegroundColor Green
}

# ============================================
# STEP 3 — CONFIRM FINAL GROUP MEMBERSHIP
# Shows current members so you can verify
# ============================================
Write-Host "`nCurrent Remote Desktop Users members:" -ForegroundColor Cyan
Get-LocalGroupMember -Group $rdpGroup | Select-Object Name, ObjectClass | Format-Table -AutoSize

Write-Host "`nRDP access configured successfully." -ForegroundColor Green