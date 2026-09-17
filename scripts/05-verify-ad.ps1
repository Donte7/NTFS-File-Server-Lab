Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Import-Module ActiveDirectory

# ============================================
# ACTIVE DIRECTORY VERIFICATION
# Checks every OU, group, user, and membership
# Prints [PASS] or [FAIL] for each check
# Exit code 1 if ANY check fails
# ============================================
$pass = $true

Write-Host "`n=== Active Directory Verification ===" -ForegroundColor Cyan

# ============================================
# CHECK 1 — ORGANIZATIONAL UNITS
# ============================================
Write-Host "`n[ Organizational Units ]" -ForegroundColor White

foreach ($ou in @("Lab Users", "Lab Groups", "Lab Computers")) {
    $exists = [bool](Get-ADOrganizationalUnit `
        -Filter "Name -eq '$ou'" `
        -ErrorAction SilentlyContinue)

    if ($exists) {
        Write-Host "  [PASS] OU exists: $ou" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] OU missing: $ou" -ForegroundColor Red
        $pass = $false
    }
}

# ============================================
# CHECK 2 — SECURITY GROUPS
# ============================================
Write-Host "`n[ Security Groups ]" -ForegroundColor White

foreach ($group in @("GRP_Finance", "GRP_HR", "GRP_Sales", "GRP_IT")) {
    $exists = [bool](Get-ADGroup `
        -Filter "Name -eq '$group'" `
        -ErrorAction SilentlyContinue)

    if ($exists) {
        Write-Host "  [PASS] Group exists: $group" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Group missing: $group" -ForegroundColor Red
        $pass = $false
    }
}

# ============================================
# CHECK 3 — USERS AND GROUP MEMBERSHIPS
# Verifies user exists AND is in correct group
# Both checks must pass for each user
# ============================================
Write-Host "`n[ Users and Group Memberships ]" -ForegroundColor White

$expectedUsers = @(
    @{Username="john.smith";  Group="GRP_IT"     },
    @{Username="sarah.jones"; Group="GRP_Finance" },
    @{Username="mike.brown";  Group="GRP_Finance" },
    @{Username="lisa.white";  Group="GRP_HR"      },
    @{Username="tom.davis";   Group="GRP_Sales"   }
)

foreach ($u in $expectedUsers) {
    $user = Get-ADUser `
        -Filter "SamAccountName -eq '$($u.Username)'" `
        -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Host "  [FAIL] User missing: $($u.Username)" -ForegroundColor Red
        $pass = $false
        continue
    }

    $members = Get-ADGroupMember `
        -Identity $u.Group | Select-Object -ExpandProperty SamAccountName

    if ($members -contains $u.Username) {
        Write-Host "  [PASS] $($u.Username) -> $($u.Group)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($u.Username) NOT in $($u.Group)" -ForegroundColor Red
        $pass = $false
    }
}

# ============================================
# FINAL RESULT
# ============================================
Write-Host "`n======================================" -ForegroundColor Cyan
if ($pass) {
    Write-Host "  AD VERIFICATION PASSED" -ForegroundColor Green
} else {
    Write-Host "  AD VERIFICATION FAILED" -ForegroundColor Red
    Write-Host "  Fix failures above and re-run" -ForegroundColor Yellow
}
Write-Host "======================================`n" -ForegroundColor Cyan