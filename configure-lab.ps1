<#
.SYNOPSIS
    Orchestration script for the NTFS File Server Lab.

.DESCRIPTION
    This is the "foreman" script. It does not configure anything itself directly —
    it pushes each numbered script in .\scripts\ to the correct VM (DC01, FS01,
    or CLIENT01) using az vm run-command, waits for each stage to complete, and
    reports PASS/FAIL at the end.

    Why az vm run-command instead of RDP or WinRM?
        The lab's NSG only opens port 3389 (RDP) inbound from your IP. WinRM
        (port 5985) is blocked entirely. az vm run-command executes scripts
        through the Azure VM Agent, which is already installed on every Azure
        VM and talks to the VM over the Azure control plane — not the network
        data plane — so it bypasses the NSG completely. This is the same
        mechanism production automation tools (Azure Automation, Ansible's
        azure_rm modules, etc.) rely on when direct network access is locked
        down for security.

.PARAMETER KeyVaultName
    The Key Vault name output by 'terraform output key_vault_name' after apply.
    Required — there is no default because it is unique per deployment.

.PARAMETER ResourceGroup
    Defaults to RG-FileServerLab to match main.tf. Override only if you renamed
    the resource group in terraform.tfvars.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [string]$ResourceGroup = "RG-FileServerLab"
)

# Track total runtime so we can report it at the end — useful for judging
# whether a re-run is faster than the first (it should be, since AD/DNS
# propagation delays are the biggest variable cost).
$startTime = Get-Date

# ---------------------------------------------------------------------------
# STEP 0 — Retrieve the VM admin password from Key Vault
# ---------------------------------------------------------------------------
# Security note: the password is pulled at RUNTIME using your own logged-in
# 'az login' identity (RBAC-authorized as Key Vault Secrets Officer in
# keyvault.tf). It is never stored in this script, in terraform.tfvars, or
# in source control. It only ever lives in memory for the duration of this
# script's execution.
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Retrieving credentials from Key Vault..." -ForegroundColor Cyan

$AdminPassword = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name "vm-admin-password" `
    --query "value" `
    -o tsv

# Fail fast and loudly if the vault read didn't work — usually means the
# operator forgot 'az login' or their token expired mid-lab.
if (-not $AdminPassword -or $LASTEXITCODE -ne 0) {
    throw "Could not retrieve password from Key Vault. Run az login first."
}
Write-Host "  Credentials retrieved." -ForegroundColor Green


# ---------------------------------------------------------------------------
# FUNCTION: Invoke-VMScript
# ---------------------------------------------------------------------------
# Pushes a local .ps1 file to a remote VM and executes it there via the Azure
# VM Agent. This is the single reusable building block every "STEP" below
# calls — write it once, use it seven times.
function Invoke-VMScript {
    param(
        [string]$VMName,                       # e.g. "DC01", "FS01", "CLIENT01"
        [string]$ScriptPath,                   # local path to the .ps1 to run remotely
        [string]$Description,                  # human-readable label for console output
        [hashtable]$Replacements = @{}         # placeholder -> real value substitutions
    )

    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] >>> $Description" -ForegroundColor Cyan

    # Read the script as raw text so we can do string replacement on it before
    # it ever touches disk on the remote VM.
    $script = Get-Content $ScriptPath -Raw

    # Swap placeholders like SAFE_MODE_PASSWORD / ADMIN_PASSWORD for the real
    # secret retrieved above. [regex]::Escape prevents special characters in
    # the password (like $ or \) from being misinterpreted as regex syntax.
    foreach ($key in $Replacements.Keys) {
        $script = $script -replace $key, [regex]::Escape($Replacements[$key])
    }

    # Write the "hydrated" script to a throwaway temp file. This file exists
    # only locally and briefly — it's what actually gets uploaded to the VM.
    $tempFile = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName() + ".ps1"
    $script | Out-File -FilePath $tempFile -Encoding UTF8

    try {
        # The actual remote execution call. --scripts "@$tempFile" tells the
        # Azure CLI to read the script FROM a file rather than pass it inline
        # (inline would risk truncation and shows up in shell history/logs).
        $jsonLines = az vm run-command invoke `
            --resource-group $ResourceGroup `
            --name $VMName `
            --command-id RunPowerShellScript `
            --scripts "@$tempFile" `
            --output json `
            --only-show-errors

        if ($LASTEXITCODE -ne 0) {
            throw "az vm run-command failed on $VMName"
        }

        # az vm run-command returns stdout/stderr as separate "code" entries
        # inside a JSON array — pull each one out for display.
        $result = ($jsonLines -join "`n") | ConvertFrom-Json
        $stdout = ($result.value | Where-Object { $_.code -like "*StdOut*" }).message
        $stderr = ($result.value | Where-Object { $_.code -like "*StdErr*" }).message

        if ($stdout) { Write-Host $stdout }
        if ($stderr -and $stderr.Trim() -ne "") {
            Write-Warning "  VM StdErr: $stderr"
        }
    }
    finally {
        # Always clean up the temp file, even if the remote call throws.
        # This avoids leaving decrypted secrets sitting in %TEMP% locally.
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}


# ---------------------------------------------------------------------------
# FUNCTION: Wait-VMOnline
# ---------------------------------------------------------------------------
# Polls Azure every 15 seconds until the target VM reports "VM running".
# Needed after any step that triggers a reboot (AD DS promotion, domain join)
# because az vm run-command will simply fail/hang if it's called against a
# VM that's mid-restart.
function Wait-VMOnline {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 360
    )

    Write-Host "  Waiting for $VMName..." -ForegroundColor Yellow
    $elapsed = 0

    do {
        Start-Sleep -Seconds 15
        $elapsed += 15
        try {
            $state = (az vm show -g $ResourceGroup -n $VMName -d `
                --query "powerState" -o tsv --only-show-errors 2>$null).Trim()
        }
        catch {
            $state = ""
        }
        Write-Host "    $VMName -> $state ($elapsed s)" -ForegroundColor DarkGray
    } while ($state -ne "VM running" -and $elapsed -lt $TimeoutSeconds)

    if ($state -ne "VM running") {
        throw "Timeout: $VMName did not return within ${TimeoutSeconds}s"
    }
    Write-Host "  $VMName is online." -ForegroundColor Green
}


# ===========================================================================
# STEP 1 — Promote DC01 to a Domain Controller
# ===========================================================================
# This step is EXPECTED to "fail" from run-command's perspective: promoting a
# server to a DC triggers an automatic reboot mid-script, which kills the
# Azure Agent's active session before it can report success. That's why this
# call is wrapped in try/catch with a friendly warning instead of letting the
# whole orchestration script die here.
Write-Host "`n[STEP 1] Promoting DC01 to Domain Controller" -ForegroundColor Magenta
try {
    Invoke-VMScript -VMName "DC01" `
        -ScriptPath ".\scripts\00-promote-dc.ps1" `
        -Description "Promoting DC01" `
        -Replacements @{ "SAFE_MODE_PASSWORD" = $AdminPassword }
}
catch {
    Write-Host "  DC01 disconnected -- expected after promotion." -ForegroundColor Yellow
}

# Give Windows time to actually start rebooting before we start polling for
# "online" (otherwise Wait-VMOnline might catch it mid-shutdown and think
# it's already back).
Start-Sleep -Seconds 60
Wait-VMOnline -VMName "DC01"
# Extra buffer after boot — AD DS/DNS services take longer to become
# query-able than the OS itself takes to report "running".
Start-Sleep -Seconds 90


# ===========================================================================
# STEP 2 — Create OUs, security groups, and test users on DC01
# ===========================================================================
Write-Host "`n[STEP 2] Creating OUs, Groups, and Users" -ForegroundColor Magenta
Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\01-create-ad-users-groups.ps1" `
    -Description "Creating AD objects"


# ===========================================================================
# STEP 3 — Join FS01 to the lab.local domain
# ===========================================================================
Write-Host "`n[STEP 3] Joining FS01 to lab.local" -ForegroundColor Magenta
Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\04-domain-join.ps1" `
    -Description "Joining FS01" `
    -Replacements @{ "ADMIN_PASSWORD" = $AdminPassword }

# Domain join also triggers a reboot — same wait pattern as Step 1, just
# shorter because it's a lighter-weight operation than DC promotion.
Start-Sleep -Seconds 30
Wait-VMOnline -VMName "FS01"
Start-Sleep -Seconds 30


# ===========================================================================
# STEP 4 — Create SMB shares and apply NTFS permissions on FS01
# ===========================================================================
Write-Host "`n[STEP 4] Configuring shares and NTFS on FS01" -ForegroundColor Magenta
Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\02-configure-shares-and-permissions.ps1" `
    -Description "Creating shares and NTFS"


# ===========================================================================
# STEP 5 — Join CLIENT01 to the lab.local domain
# ===========================================================================
Write-Host "`n[STEP 5] Joining CLIENT01 to lab.local" -ForegroundColor Magenta
Invoke-VMScript -VMName "CLIENT01" `
    -ScriptPath ".\scripts\04-domain-join.ps1" `
    -Description "Joining CLIENT01" `
    -Replacements @{ "ADMIN_PASSWORD" = $AdminPassword }

Start-Sleep -Seconds 30
Wait-VMOnline -VMName "CLIENT01"
Start-Sleep -Seconds 30


# ===========================================================================
# STEP 5b — Grant Domain Users RDP rights on CLIENT01
# ===========================================================================
# Run separately from the GPO step (Step 6) because this has to execute
# LOCALLY on CLIENT01 — DC01 can't reach into CLIENT01's local group via
# Invoke-Command since WinRM is blocked by the NSG, same reasoning as the
# az vm run-command choice at the top of this file.
Write-Host "`n[STEP 5b] Granting Domain Users RDP on CLIENT01" -ForegroundColor Magenta
Invoke-VMScript -VMName "CLIENT01" `
    -ScriptPath ".\scripts\06-add-rdp-users.ps1" `
    -Description "Adding Domain Users to RDP group"


# ===========================================================================
# STEP 6 — Create and link the RDP Group Policy Object on DC01
# ===========================================================================
Write-Host "`n[STEP 6] Configuring RDP GPO on DC01" -ForegroundColor Magenta
Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\03-configure-rdp-gpo.ps1" `
    -Description "Creating RDP GPO"


# ===========================================================================
# STEP 7 — Automated verification (AD objects + share/NTFS permissions)
# ===========================================================================
# Running verification as the LAST step means you get one consolidated
# PASS/FAIL report without ever having to RDP into DC01 or FS01 manually.
Write-Host "`n[STEP 7] Running automated verification" -ForegroundColor Magenta
Invoke-VMScript -VMName "DC01" `
    -ScriptPath ".\scripts\05-verify-ad.ps1" `
    -Description "Verifying AD"

Invoke-VMScript -VMName "FS01" `
    -ScriptPath ".\scripts\05-verify-shares.ps1" `
    -Description "Verifying shares"


# ---------------------------------------------------------------------------
# Wrap-up — report total elapsed time and next action for the operator
# ---------------------------------------------------------------------------
$duration = (Get-Date) - $startTime
Write-Host "`n=== LAB FULLY CONFIGURED ($([math]::Round($duration.TotalMinutes, 1)) min) ===" -ForegroundColor Green
Write-Host "RDP into CLIENT01 as: LAB\sarah.jones  Password: P@ssw0rd123!"




