Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# SHARE AND NTFS VERIFICATION
# Checks SMB shares exist and NTFS permissions
# match the expected permission model exactly
# Uses bitwise AND for permission checks
# Windows combines rights into flags so exact
# string matching produces false failures
# ============================================
$basePath = "C:\Shares"
$pass     = $true

Write-Host "`n=== Share and NTFS Verification ===" -ForegroundColor Cyan

# ============================================
# EXPECTED PERMISSION MODEL
# Maps each share to its required ACEs
# Right values use FileSystemRights enum
# ============================================
$expectedACLs = @{
    "Finance" = @(
        @{Identity="LAB\GRP_Finance";    Right=[System.Security.AccessControl.FileSystemRights]::Modify     },
        @{Identity="LAB\GRP_HR";         Right=[System.Security.AccessControl.FileSystemRights]::Read       },
        @{Identity="LAB\GRP_IT";         Right=[System.Security.AccessControl.FileSystemRights]::FullControl}
    )
    "HR" = @(
        @{Identity="LAB\GRP_HR";         Right=[System.Security.AccessControl.FileSystemRights]::Modify     },
        @{Identity="LAB\GRP_IT";         Right=[System.Security.AccessControl.FileSystemRights]::FullControl}
    )
    "Sales" = @(
        @{Identity="LAB\GRP_Sales";      Right=[System.Security.AccessControl.FileSystemRights]::Modify     },
        @{Identity="LAB\GRP_IT";         Right=[System.Security.AccessControl.FileSystemRights]::FullControl}
    )
    "IT" = @(
        @{Identity="LAB\GRP_IT";         Right=[System.Security.AccessControl.FileSystemRights]::FullControl}
    )
}

# ============================================
# CHECK EACH SHARE
# ============================================
foreach ($share in $expectedACLs.Keys) {
    Write-Host "`n[ $share Share ]" -ForegroundColor White

    # CHECK 1 — SMB share exists
    $smb = Get-SmbShare -Name $share -ErrorAction SilentlyContinue
    if ($smb) {
        Write-Host "  [PASS] SMB share exists: \\FS01\$share" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] SMB share missing: $share" -ForegroundColor Red
        $pass = $false
        continue
    }

    # CHECK 2 — NTFS permissions match expected
    $acl = (Get-Acl "$basePath\$share").Access

    foreach ($expected in $expectedACLs[$share]) {
        $ace = $acl | Where-Object {
            $_.IdentityReference.Value -eq $expected.Identity -and
            $_.AccessControlType -eq "Allow"
        }

        if (-not $ace) {
            Write-Host "  [FAIL] No ACE found for: $($expected.Identity)" -ForegroundColor Red
            $pass = $false
            continue
        }

        # Bitwise AND handles combined permission flags
        $hasRight = ($ace.FileSystemRights -band $expected.Right) -eq $expected.Right

        if ($hasRight) {
            Write-Host "  [PASS] $($expected.Identity) -> $($expected.Right)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($expected.Identity) has wrong rights" -ForegroundColor Red
            $pass = $false
        }
    }
}

# ============================================
# FINAL RESULT
# ============================================
Write-Host "`n======================================" -ForegroundColor Cyan
if ($pass) {
    Write-Host "  SHARE VERIFICATION PASSED" -ForegroundColor Green
} else {
    Write-Host "  SHARE VERIFICATION FAILED" -ForegroundColor Red
    Write-Host "  Fix failures above and re-run" -ForegroundColor Yellow
}
Write-Host "======================================`n" -ForegroundColor Cyan