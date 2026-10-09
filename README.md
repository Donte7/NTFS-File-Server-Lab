# Lab 1 — NTFS File Server Lab

![Lab Status](https://img.shields.io/badge/Status-Complete-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Azure-blue)
![IaC](https://img.shields.io/badge/IaC-Terraform-purple)
![OS](https://img.shields.io/badge/OS-Windows%20Server%202022-blue)
[![CI/CD Pipeline](https://github.com/Donte7/ntfs-file-server-lab/actions/workflows/deploy.yml/badge.svg)](https://github.com/Donte7/ntfs-file-server-lab/actions/workflows/deploy.yml)

> **Series:** 5-Lab Azure Infrastructure Series | **Lab:** 1 of 5 | **Builds toward:** Lab 2 — Azure RBAC

---

## Overview

This lab deploys a fully functional enterprise Windows file server environment on Azure using Infrastructure as Code. You will build a three-VM architecture — a Domain Controller, File Server, and Windows 11 Workstation — wired together with Active Directory, NTFS permissions, SMB shares, and Group Policy. Every resource is provisioned with Terraform and configured with PowerShell automation.

This is not a click-through-the-portal lab. Every resource is defined as code, every configuration is automated, and every permission is verifiable.

---

## The Business Problem This Lab Solves

Every organization running Windows infrastructure faces the same challenge: controlling who can access what data. Finance data should only be readable by Finance staff. HR files should be invisible to Sales. IT staff need administrative access everywhere to do their jobs.

The solution — still widely deployed in enterprise environments today — is a Windows File Server backed by Active Directory groups with NTFS permissions. This lab puts you through the complete workflow a systems administrator follows when building this from scratch using modern cloud infrastructure and Infrastructure as Code.

---

## Lab Metadata

| Field | Value |
|---|---|
| Domain | `lab.local` |
| Region | Central US |
| VMs | DC01 · FS01 · CLIENT01 |
| Deploy Time | 10–15 min (terraform) + 10–20 min (configure-lab.ps1) |
| Estimated Cost | ~$0.30/hr while all three VMs are running |
| VM Size | Standard_D2s_v3 |
| OS — Servers | Windows Server 2022 Azure Edition |
| OS — Workstation | Windows 11 Pro (24H2) |
| Lab Document | NTFS-LAB-001 |

---

## Lab Series Relationships

| Lab | What it deploys | Relationship |
|---|---|---|
| **Lab 1 — NTFS File Server** | DC01, FS01, CLIENT01, VNet, NSG, Key Vault in RG-FileServerLab | Standalone — creates all infrastructure from scratch |
| Lab 2 — Azure RBAC | 3 role assignments on FS01 only — no new VMs | Depends on Lab 1 — reads Lab 1 resources using data sources |
| AUM Lab — Azure Update Manager | DC01, WS01, WS02, VNet, Key Vault in rg-aumlab | Standalone — fully independent |

> ⚠️ **If you plan to do Lab 2:** Stop the VMs instead of destroying when you finish. Lab 2 needs FS01 to already exist. Stopped VMs have no compute charges.

---

## Architecture

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add architecture diagram screenshot here -->
![alt text](../../screenshots_digrams/NTFS-File-Sever/architecture-diagram.png)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Resource Group: RG-FileServerLab              │
│                                                                   │
│  ┌──────────────┐   Domain Auth   ┌──────────────┐  Domain Join  │
│  │     DC01     │ ──────────────► │     FS01     │ ◄──────────── │
│  │   Domain     │                 │  File Server │               │
│  │  Controller  │                 │              │               │
│  └──────────────┘                 └──────────────┘               │
│         │                                │                        │
│  Active Directory                 \\FS01\Finance ◄── sarah.jones  │
│  lab.local                        \\FS01\HR     ◄── lisa.white    │
│         │                         \\FS01\IT     ◄── john.smith    │
│  GRP_Finance                      \\FS01\Sales  ◄── tom.davis     │
│  GRP_HR                                                           │
│  GRP_IT                           ┌──────────────┐               │
│  GRP_Sales                        │   CLIENT01   │               │
│                                   │  Windows 11  │               │
│                                   │  Workstation │               │
│                                   └──────────────┘               │
│                                                                   │
│  VNet: 10.0.0.0/16 │ Subnet: 10.0.1.0/24 │ NSG: RDP → Your IP  │
└─────────────────────────────────────────────────────────────────┘

Flow: User logs into CLIENT01 → authenticates via DC01 → accesses 
      FS01 share → NTFS permissions enforced per AD group
```

---

## What You Will Learn

| Skill | Why it matters in a real environment |
|---|---|
| Deploy Active Directory with Terraform | In production, AD is provisioned as code so it can be recreated identically across environments without manual configuration drift |
| Create OUs and security groups | OUs let you apply Group Policy to specific sets of users or computers. Groups let you manage permissions for hundreds of users by changing one group membership |
| Configure NTFS permissions | NTFS is the actual enforcement layer on Windows file systems. Understanding inheritance, group permissions, and icacls is required knowledge for any Windows sysadmin role |
| Create and secure SMB shares | SMB is the protocol Windows uses for file sharing across a network. Knowing how share-level and NTFS-level permissions interact is a job interview topic |
| Deploy infrastructure with Terraform | IaC means the environment is reproducible, version-controlled, and auditable |
| Store secrets in Azure Key Vault | Hard-coding passwords in scripts is a security failure. Key Vault is the correct pattern |
| Use az vm run-command for automation | In real Azure environments you often cannot RDP directly into VMs due to network restrictions. The Azure agent provides a secure, firewall-bypassing channel |

---

## The Business Scenario Behind the Test Users

The five test users represent a real org chart scenario:

| User | Department | Access Level | Business Reason |
|---|---|---|---|
| sarah.jones | Finance | Read/Write on Finance | Finance staff need full access to Finance data |
| mike.brown | Finance | Read/Write on Finance | Finance staff need full access to Finance data |
| lisa.white | HR | Read/Write on HR, Read-only on Finance | HR needs own data plus Finance for cross-department reporting |
| john.smith | IT | Full Control everywhere | IT admins need access to everything to do their jobs |
| tom.davis | Sales | No access to Finance or HR | Sales has zero business need for Finance or HR data |

---

## Prerequisites

Before starting verify these are installed and working:

```bash
terraform -version   # Must be >= 1.5.0
az version           # Azure CLI — any recent version
az account show      # Confirm correct subscription
```

---

## Project Structure

```
ntfs-file-server-lab/
├── backend.tf                              ← Remote state — Azure Blob Storage
├── versions.tf                             ← Provider versions and constraints
├── variables.tf                            ← All input variables
├── main.tf                                 ← VMs, VNet, NSG, NICs, Public IPs
├── keyvault.tf                             ← Key Vault + secret + RBAC assignment
├── outputs.tf                              ← IPs and Key Vault name after apply
├── terraform.tfvars.example               ← Safe template — commit this
├── terraform.tfvars                        ← Your real values — NEVER commit
├── .gitignore                              ← Protects sensitive files
├── configure-lab.ps1                       ← The only script you run manually
└── scripts/
    ├── 00-promote-dc.ps1                   ← DC01: installs AD DS, promotes DC
    ├── 01-create-ad-users-groups.ps1       ← DC01: OUs, groups, test users
    ├── 02-configure-shares-and-permissions.ps1 ← FS01: SMB shares + NTFS ACLs
    ├── 03-configure-rdp-gpo.ps1            ← DC01: RDP Group Policy Object
    ├── 04-domain-join.ps1                  ← FS01 + CLIENT01: domain join
    ├── 05-verify-ad.ps1                    ← DC01: PASS/FAIL check of AD objects
    ├── 05-verify-shares.ps1                ← FS01: PASS/FAIL check of permissions
    └── 06-add-rdp-users.ps1                ← CLIENT01: domain users → RDP group
```

---

## Step-by-Step Deployment

### Step 1 — Clone the Repository and Open in VS Code

```bash
cd your-project-folder
code .
```

Open the integrated terminal in VS Code:
```
Terminal → New Terminal  (or Ctrl + `)
```
![alt text](<Screenshot 2026-10-09 at 9.44.15 AM.png>)
---

### Step 2 — Set Up Remote State Storage

Run these commands once. Remote state stores your Terraform state file in Azure Blob Storage so it is encrypted, backed up, and accessible from any machine.

```bash
az group create --name RG-TerraformState --location "centralus"

az storage account create \
  --name tfstatentfsnerdlab \
  --resource-group RG-TerraformState \
  --location "centralus" \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name tfstate \
  --account-name tfstatentfsnerdlab \
  --auth-mode login
```

Verify the container exists:
```bash
az storage container list \
  --account-name tfstatentfsnerdlab \
  --auth-mode login \
  --query "[].name" \
  -o tsv
```

Expected output:
```
tfstate
```

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of terminal showing tfstate container created successfully -->
![alt text](../../screenshots_digrams/NTFS-File-Sever/ts_state.png)

---

### Step 3 — Update backend.tf

Open `backend.tf` and replace `REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME` with your storage account name:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TerraformState"
    storage_account_name = "tfstatentfsnerdlab"
    container_name       = "tfstate"
    key                  = "ntfs-lab.terraform.tfstate"
  }
}
```

> ⚠️ **Do this BEFORE running `terraform init`** — init will fail if the storage account name is still a placeholder.

---

### Step 4 — Configure Variables

Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Get your public IPv4 address:
```bash
curl -s -4 ifconfig.me
```

> ⚠️ **Always use `-4` flag** to force IPv4. Azure NSG rules do not accept IPv6 addresses and will fail with `SecurityRuleInvalidAddressPrefix` if you provide an IPv6 address.

Open `terraform.tfvars` and set your real IP:
```hcl
location       = "Central US"
server_vm_size = "Standard_D2s_v3"
client_vm_size = "Standard_D2s_v3"
rdp_source     = "YOUR.REAL.IP.HERE/32"
```

Set your admin password as an environment variable — **never in a file:**
```bash
export TF_VAR_admin_password='YourStrongPassword@2024!'
```

Password requirements:
- Minimum 12 characters
- Must contain uppercase + lowercase + number + symbol
- Use single quotes on Mac to prevent special character interpretation

Verify it is set:
```bash
echo $TF_VAR_admin_password
```

> ⚠️ **This variable disappears when you close the terminal.** Re-export it at the start of every session before running Terraform commands.

---

### Step 5 — Initialize Terraform

```bash
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

Verify all three providers locked in:
```bash
cat .terraform.lock.hcl | grep "provider"
```

---

### Step 6 — Review the Plan

```bash
terraform plan
```

Expected summary:
```
Plan: 24 to add, 0 to change, 0 to destroy.
```

Review the output carefully. Every resource should show `+` (create). If you see any errors fix them before applying.

> ⚠️ **Common plan errors:**
> - `SecurityRuleInvalidAddressPrefix` — your IP in tfvars is IPv6, use `curl -s -4 ifconfig.me` to get IPv4
> - `PlatformImageNotFound` — your region doesn't have that Windows SKU, run `az vm image list --publisher MicrosoftWindowsDesktop --offer windows-11 --location centralus --all --query "[].sku" -o tsv` to find available ones
> - `No value for required variable` — password env var not set, re-export it

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of terraform plan output showing 24 resources -->
![> *Screenshot: terraform plan showing 24 resources to add*](../../screenshots_digrams/NTFS-File-Sever/terraform_plan.png)

---

### Step 7 — Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Takes 10–15 minutes.

When complete, copy and save the outputs immediately:

```
Outputs:

client01_public_ip = "xx.xx.xx.xx"    ← RDP here for Step 9 testing
dc01_private_ip    = "10.0.1.4"       ← Always static — DC01 DNS address
dc01_public_ip     = "xx.xx.xx.xx"
fs01_public_ip     = "xx.xx.xx.xx"
key_vault_name     = "kv-fslab-xxxxxxxx"  ← COPY THIS — needed for Step 8
```

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of terraform apply completion with outputs visible -->
![> *Screenshot: terraform apply complete with all outputs*](../../screenshots_digrams/NTFS-File-Sever/terraform_apply.png)

---

### Step 8 — Run Lab Configuration

This single command configures all three VMs automatically — promotes DC01, creates AD objects, joins machines to the domain, configures shares and permissions, and runs automated verification. Takes 10–20 minutes, fully unattended.

```bash
./configure-lab.ps1 -KeyVaultName "kv-fslab-xxxxxxxx"
```

Replace `kv-fslab-xxxxxxxx` with your actual Key Vault name from Step 7 outputs.

Expected completion output:
```
================================================
  LAB FULLY CONFIGURED
  Duration: XX.X minutes
================================================
Next Step — RDP into CLIENT01:
  Run: terraform output client01_public_ip
  RDP as: LAB\sarah.jones
  Password: P@ssw0rd123!
  Then test: \\FS01\Finance
```

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of configure-lab.ps1 completion output -->
![> *Screenshot: configure-lab.ps1 showing LAB FULLY CONFIGURED*](../../screenshots_digrams/NTFS-File-Sever/lab_fully_configured.png)

> ⚠️ **Known issue with `Win2016` functional level:** If you see `The specified argument 'DomainLevel' was not recognized`, open `scripts/00-promote-dc.ps1` and change both `-ForestMode "WinThreshold"` and `-DomainMode "WinThreshold"` to `"Win2016"`. Re-run the script.

> ⚠️ **Known issue with `enable-rdp` extension stuck:** If `az vm run-command` returns a `Conflict` error, check for a stuck extension: `az vm extension list --resource-group RG-FileServerLab --vm-name CLIENT01 --query "[].{Name:name,State:provisioningState}" -o table`. If `enable-rdp` shows `Updating`, delete it: `az vm extension delete --resource-group RG-FileServerLab --vm-name CLIENT01 --name enable-rdp`. RDP still works — the extension already applied its registry change.

---

### Step 9 — Verify the Lab

RDP into CLIENT01 using the public IP from terraform output.

**On Mac:** Use Microsoft Remote Desktop app.
```
PC Name:  <client01_public_ip>
Username: azureadmin
Password: <your TF_VAR_admin_password>
```

Once inside CLIENT01, sign out of azureadmin and log in as each test user to validate permissions.

All test user passwords: `P@ssw0rd123!`

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of Microsoft Remote Desktop connecting to CLIENT01 -->
![> *Screenshot: Microsoft Remote Desktop connected to CLIENT01*](../../screenshots_digrams/NTFS-File-Sever/remote_desktop.png)

**Permission Verification Matrix:**

| Log in as | Navigate to | Expected | Why |
|---|---|---|---|
| `LAB\sarah.jones` | `\\FS01\Finance` | ✅ Read and write | Member of GRP_Finance — Modify NTFS |
| `LAB\sarah.jones` | `\\FS01\HR` | ❌ Access Denied | Not in GRP_HR — no ACE on HR share |
| `LAB\lisa.white` | `\\FS01\Finance` | ✅ Read only | GRP_HR has Read on Finance share |
| `LAB\lisa.white` | `\\FS01\HR` | ✅ Read and write | Member of GRP_HR — Modify NTFS |
| `LAB\john.smith` | `\\FS01\IT` | ✅ Full Control | Member of GRP_IT — Full Control NTFS |
| `LAB\tom.davis` | `\\FS01\Finance` | ❌ Access Denied | GRP_Sales has no entry on Finance |

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of sarah.jones accessing \\FS01\Finance successfully -->
> *Screenshot: sarah.jones with read/write access to Finance share*

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of sarah.jones getting Access Denied on \\FS01\HR -->
> *Screenshot: sarah.jones receiving Access Denied on HR share*

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of tom.davis getting Access Denied on \\FS01\Finance -->
> *Screenshot: tom.davis receiving Access Denied on Finance share*

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of john.smith with Full Control on \\FS01\IT -->
> *Screenshot: john.smith with Full Control on IT share*

---

## Step 10 — Pause or Tear Down

### Continuing to Lab 2? Stop — do not destroy.

Lab 2 needs `RG-FileServerLab` and `FS01` to exist. Stopped VMs have no compute charges.

```bash
# Stop all VMs — no compute charges while stopped
az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait

# Restart before Lab 2
az vm start --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
```

### Full teardown — only when completely done with both labs

```bash
terraform destroy
```

> ⚠️ **Do not run `terraform destroy` if you plan to do Lab 2.** This deletes FS01 and Lab 2 cannot create role assignments on a VM that does not exist.

---

## NTFS Permission Model

```
NTFS rights applied per group:

Finance share:
  GRP_Finance  = (OI)(CI)M  — Modify (read + write)
  GRP_HR       = (OI)(CI)R  — Read only
  GRP_IT       = (OI)(CI)F  — Full Control
  Administrators = (OI)(CI)F — Full Control

HR share:
  GRP_HR       = (OI)(CI)M  — Modify
  GRP_IT       = (OI)(CI)F  — Full Control
  Administrators = (OI)(CI)F — Full Control

Sales share:
  GRP_Sales    = (OI)(CI)M  — Modify
  GRP_IT       = (OI)(CI)F  — Full Control
  Administrators = (OI)(CI)F — Full Control

IT share:
  GRP_IT       = (OI)(CI)F  — Full Control
  Administrators = (OI)(CI)F — Full Control

(OI) = Object Inherit  — files inside folder inherit this rule
(CI) = Container Inherit — subfolders inherit this rule
M    = Modify — read + write + delete (cannot change permissions)
R    = Read only
F    = Full Control — everything including changing permissions
```

> **Key concept:** Share permissions are set to `Everyone Full Control` intentionally. Real security enforcement happens at the NTFS layer. When both layers apply, Windows uses the most restrictive result.

---

## Active Directory Structure

```
lab.local (DC=lab,DC=local)
│
├── OU=Lab Users
│   ├── sarah.jones    → GRP_Finance
│   ├── mike.brown     → GRP_Finance
│   ├── lisa.white     → GRP_HR
│   ├── john.smith     → GRP_IT
│   └── tom.davis      → GRP_Sales
│
├── OU=Lab Groups
│   ├── GRP_Finance
│   ├── GRP_HR
│   ├── GRP_IT
│   └── GRP_Sales
│
└── OU=Lab Computers
    └── CLIENT01
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---|---|---|
| `terraform init` fails | `backend.tf` still has placeholder name | Open `backend.tf`, confirm storage account name is correct |
| `SecurityRuleInvalidAddressPrefix` | IPv6 address in rdp_source | Run `curl -s -4 ifconfig.me`, update `terraform.tfvars`, re-apply |
| `PlatformImageNotFound` | Windows 11 SKU not available in your region | Run `az vm image list --publisher MicrosoftWindowsDesktop --offer windows-11 --location centralus --all --query "[].sku" -o tsv` and pick an available SKU |
| `DomainLevel not recognized` | WinThreshold not supported on this image | Change `ForestMode` and `DomainMode` to `"Win2016"` in `00-promote-dc.ps1` |
| Cannot RDP to VMs | IP changed or rdp_source mismatch | Run `curl -s -4 ifconfig.me`, update `terraform.tfvars rdp_source`, run `terraform apply -target=azurerm_network_security_group.nsg` |
| `Conflict` on run-command | Previous extension stuck in Updating | `az vm extension delete --resource-group RG-FileServerLab --vm-name CLIENT01 --name enable-rdp` |
| Domain join fails — DNS not resolving | DC01 still finishing promotion | Wait 2 minutes and re-run — AD services need time to fully initialize after reboot |
| Access Denied unexpected | User not in the right group | Inside RDP run `whoami /groups` to confirm group membership |
| GPO not applying | Policy cache not refreshed | Run `gpupdate /force` inside the VM, then `gpresult /r` |
| `Missing closing '}'` in PowerShell script | Backtick line continuations corrupted by `sed` | Use Python `.replace()` for password injection instead of `sed` |

---

## Security Notes

- NSG restricts inbound RDP (port 3389) to your IP only — all other inbound traffic is implicitly denied
- Admin password is stored in Azure Key Vault with RBAC authorization — never written to disk or source control
- `terraform.tfvars` is gitignored — your real IP and settings never get committed
- `enable_rbac_authorization = true` is required on Key Vault — without it role assignments are silently ignored and all secret operations return 403
- Share permissions are set to `Everyone Full Control` intentionally — all real access control is enforced at the NTFS layer
- VM images use `2022-datacenter-azure-edition` which includes the Azure VM agent pre-installed — required for `az vm run-command` automation

---

---

## CI/CD Pipeline — GitHub Actions

This lab includes a GitHub Actions pipeline that automates the entire deployment. Instead of running `terraform apply` manually from your terminal, every push to `main` triggers the pipeline automatically.

![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF)
![Pipeline](https://img.shields.io/badge/Pipeline-4%20Jobs-brightgreen)

---
![alt text](../../screenshots_digrams/NTFS-File-Sever/cicd-pipeline-diagram.png)
### How the Pipeline Works

```
Developer pushes code to main
         ↓
┌─────────────────────────────────────────────────────┐
│                  GitHub Actions                      │
│                                                      │
│  Job 1 — Validate   Job 2 — Plan                    │
│  ├── fmt check      ├── terraform init               │
│  ├── tf validate    ├── terraform plan               │
│  └── syntax check   └── post plan to PR             │
│           ↓                   ↓                      │
│  Job 3 — Deploy (main only — NOT on PRs)            │
│  ├── terraform apply                                 │
│  ├── capture outputs                                 │
│  └── post summary to GitHub                         │
│                                                      │
│  Job 4 — Destroy (manual trigger only)              │
│  └── terraform destroy                               │
└─────────────────────────────────────────────────────┘
```

### 🧒 Simple Version — What each job does

```bash
Validate  →  The spell checker
              Makes sure your Terraform code has no syntax errors
              and is formatted correctly BEFORE touching Azure

Plan      →  The blueprint review
              Shows exactly what will be created, changed, or
              destroyed — no actual changes yet
              On PRs: posts the plan as a comment automatically

Deploy    →  The construction crew
              Applies the exact plan that was already reviewed
              Only runs on push to main — never on PRs

Destroy   →  The demolition crew
              Only runs when YOU manually trigger it
              Never runs automatically — requires human decision
```

---

### Pipeline Triggers

| Event | Validate | Plan | Deploy | Destroy |
|---|---|---|---|---|
| Push to `main` | ✅ | ✅ | ✅ | ❌ |
| Pull Request | ✅ | ✅ (posts to PR) | ❌ | ❌ |
| Manual — deploy | ✅ | ✅ | ✅ | ❌ |
| Manual — destroy | ✅ | ❌ | ❌ | ✅ |

> ⚠️ **Destroy never runs automatically.** It requires a manual `workflow_dispatch` trigger with `action = destroy` explicitly selected. This prevents accidental infrastructure deletion.

---

### Step 1 — Create an Azure Service Principal

The pipeline authenticates to Azure using a Service Principal — a dedicated identity with exactly the permissions it needs and nothing more.

```bash
az ad sp create-for-rbac \
  --name "sp-ntfs-lab-pipeline" \
  --role "Contributor" \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" \
  --sdk-auth
```

This outputs a JSON block. Copy it — you need it in the next step:

```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

> ⚠️ **Security — why a Service Principal and not your personal account:**
> Your personal Azure account has broad permissions across your entire subscription. A Service Principal is scoped to exactly what the pipeline needs — `Contributor` on this subscription only. If the Service Principal credentials ever leak, the blast radius is contained. Your personal account credentials leaking is catastrophic.

---

### Step 2 — Add GitHub Secrets

Go to your GitHub repository:

```
Settings → Secrets and variables → Actions → New repository secret
```

Add each of these secrets:

| Secret Name | Value | Where to find it |
|---|---|---|
| `ARM_CLIENT_ID` | `clientId` from Service Principal JSON | Previous step output |
| `ARM_CLIENT_SECRET` | `clientSecret` from Service Principal JSON | Previous step output |
| `ARM_SUBSCRIPTION_ID` | `subscriptionId` from Service Principal JSON | Previous step output |
| `ARM_TENANT_ID` | `tenantId` from Service Principal JSON | Previous step output |
| `TF_VAR_admin_password` | Your VM admin password | The same password you used locally |
| `RDP_SOURCE_IP` | Your public IP in CIDR format | `curl -s -4 ifconfig.me` then add `/32` |

<!-- SCREENSHOT PLACEHOLDER -->
<!-- Add screenshot of GitHub repository Secrets page with all 6 secrets added -->
> *Screenshot: GitHub Actions secrets configured*

> ⚠️ **Always use `-4` flag** when getting your IP: `curl -s -4 ifconfig.me`. IPv6 addresses will fail the NSG rule with `SecurityRuleInvalidAddressPrefix`.

---

### Step 3 — Add Pipeline Protection (Recommended)

Set up a GitHub Environment to require manual approval before deploy runs.

```
Settings → Environments → New environment
Name: production
```

Under Protection rules:
- Check **Required reviewers**
- Add yourself as a required reviewer

This means even on a push to `main`, the deploy job pauses and waits for you to click **Approve** before any infrastructure changes happen. This is the correct production pattern.


---

### Step 4 — Add the Workflow File

The pipeline file lives at `.github/workflows/deploy.yml` in your repository. It is already included in this project.

Verify it exists:

```bash
ls .github/workflows/deploy.yml
```

Your updated project structure:

```
ntfs-file-server-lab/
├── .github/
│   └── workflows/
│       └── deploy.yml          ← CI/CD pipeline definition
├── backend.tf
├── versions.tf
├── variables.tf
├── main.tf
├── keyvault.tf
├── outputs.tf
├── terraform.tfvars.example
├── terraform.tfvars            ← gitignored — never committed
├── .gitignore
├── configure-lab.ps1
└── scripts/
    └── ...
```

---

### Step 5 — Trigger the Pipeline

Push any change to `main` to trigger the pipeline:

```bash
git add .github/workflows/deploy.yml
git commit -m "feat: add GitHub Actions CI/CD pipeline"
git push origin main
```

Watch it run:

```
GitHub → your repo → Actions tab
```

You will see four jobs appear. Validate and Plan run immediately. Deploy waits for your approval if you set up the environment protection.


---

### Step 6 — Pull Request Workflow

When you create a pull request targeting `main`, the pipeline automatically posts the Terraform plan as a PR comment:

```
PR Comment (posted automatically by pipeline):

## Terraform Plan
Plan: 24 to add, 0 to change, 0 to destroy.

+ azurerm_resource_group.rg
+ azurerm_virtual_network.vnet
+ azurerm_subnet.subnet
...
```

This means every infrastructure change gets reviewed before it is applied. The reviewer can see exactly what will happen in Azure before approving the merge.

---

### Step 7 — Manual Destroy

When you are completely done with the lab:

```
GitHub → Actions → NTFS Lab — Deploy Infrastructure
→ Run workflow → action: destroy → Run workflow
```

This triggers `terraform destroy` and removes all resources from `RG-FileServerLab`. The remote state storage account in `RG-TerraformState` is preserved.


---

### Pipeline Security Model

| Concern | How the pipeline addresses it |
|---|---|
| Credentials in code | Zero — all secrets live in GitHub Secrets, never in files |
| Accidental destroy | Destroy requires explicit manual trigger — never automatic |
| Unreviewed changes | PRs show plan before merge — no surprises on apply |
| Overprivileged identity | Service Principal scoped to Contributor only — not Owner |
| State file exposure | Remote state in Azure Blob Storage — pipeline reads it directly, state never hits GitHub |
| Password in logs | `TF_VAR_admin_password` is a GitHub Secret — masked in all logs automatically |

---

### ⚠️ Common Pipeline Errors

| Error | Cause | Fix |
|---|---|---|
| `AuthorizationFailed` on apply | Service Principal missing permissions | Run `az role assignment create --role Contributor` for the SP |
| `Backend config changed` | State key mismatch | Confirm `backend.tf` key matches what was used on first init |
| `RDP_SOURCE_IP` NSG error | IPv6 address in secret | Update `RDP_SOURCE_IP` secret — run `curl -s -4 ifconfig.me` to get IPv4 |
| Plan artifact not found | Plan job failed before upload | Check Plan job logs — fix the error and re-trigger |
| Deploy blocked at approval | Environment protection active | Go to Actions → pending deployment → Review → Approve |
| `No value for required variable` | `TF_VAR_admin_password` secret missing | Add the secret in Settings → Secrets → Actions |

---


---

## What's Next — Lab 2: Azure RBAC

Lab 2 builds directly on this infrastructure. It adds three Azure RBAC role assignments to FS01 — no new VMs are deployed. Before starting Lab 2:

1. Stop VMs (do not destroy): `az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait`
2. Keep `RG-FileServerLab` intact
3. Keep the same remote state storage account

Lab 2 uses `data` sources to read Lab 1 resources and reuses the same Terraform state storage account with a different state key: `rbac-lab.terraform.tfstate`
---

*NTFS-LAB-001 | Lab 1 of 5 | Azure Infrastructure Series*
