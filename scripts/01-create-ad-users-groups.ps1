
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ============================================
# VARIABLES
# Domain info used throughout this script
# ============================================
$domain   = "lab.local"
$domainDN = "DC=lab,DC=local"
$password = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# ============================================
# STEP 1 — CREATE ORGANIZATIONAL UNITS
# OUs are like departments in your company
# They let you apply Group Policy to specific
# sets of users or computers independently
# ============================================
Write-Host "`nCreating Organizational Units..." -ForegroundColor Yellow

foreach ($ou in @("Lab Users", "Lab Computers", "Lab Groups")) {
    New-ADOrganizationalUnit `
        -Name $ou `
        -Path $domainDN `
        -ProtectedFromAccidentalDeletion $false
    Write-Host "  Created OU: $ou" -ForegroundColor Cyan
}

# ============================================
# STEP 2 — CREATE SECURITY GROUPS
# Groups let you manage permissions for
# hundreds of users by changing ONE membership
# instead of editing every file individually
# All groups go in Lab Groups OU
# ============================================
Write-Host "`nCreating Security Groups..." -ForegroundColor Yellow

foreach ($group in @("GRP_Finance", "GRP_HR", "GRP_Sales", "GRP_IT")) {
    New-ADGroup `
        -Name $group `
        -GroupScope Global `
        -GroupCategory Security `
        -Path "OU=Lab Groups,$domainDN"
    Write-Host "  Created group: $group" -ForegroundColor Cyan
}

# ============================================
# STEP 3 — CREATE USERS AND ASSIGN TO GROUPS
# Each user represents a real business role
# Group membership drives ALL file permissions
# Add user to group = instant access to shares
# Remove from group = instant access revoked
# ============================================
Write-Host "`nCreating Users..." -ForegroundColor Yellow

$users = @(
    @{First="John";  Last="Smith"; Username="john.smith"; Group="GRP_IT"     },
    @{First="Sarah"; Last="Jones"; Username="sarah.jones";Group="GRP_Finance" },
    @{First="Mike";  Last="Brown"; Username="mike.brown"; Group="GRP_Finance" },
    @{First="Lisa";  Last="White"; Username="lisa.white"; Group="GRP_HR"      },
    @{First="Tom";   Last="Davis"; Username="tom.davis";  Group="GRP_Sales"   }
)

foreach ($user in $users) {
    New-ADUser `
        -GivenName $user.First `
        -Surname $user.Last `
        -Name "$($user.First) $($user.Last)" `
        -SamAccountName $user.Username `
        -UserPrincipalName "$($user.Username)@$domain" `
        -Path "OU=Lab Users,$domainDN" `
        -AccountPassword $password `
        -Enabled $true `
        -PasswordNeverExpires $true

    Add-ADGroupMember `
        -Identity $user.Group `
        -Members $user.Username

    Write-Host "  Created: $($user.Username) -> $($user.Group)" -ForegroundColor Cyan
}

Write-Host "`nAD objects created successfully." -ForegroundColor Green