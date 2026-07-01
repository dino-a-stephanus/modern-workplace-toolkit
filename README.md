# 🛡️ Modern Workplace Toolkit
**Microsoft 365 + Intune + MDE + Azure Entra ID — PowerShell Automation**
> Automation toolkit for deploying Microsoft-based Modern Workplace environments for SMEs, fintechs, and mid-sized banks.
> Developed by **Dino A. Stephanus** — Cloud & Security Architect
---

## 📋 Description

This repository contains PowerShell scripts and checklists for deploying a secure, end-to-end modern work environment, covering:

- ✅ Centralized identity management (Azure Entra ID)
- ✅ Professional email & collaboration (Microsoft 365)
- ✅ Device management (Microsoft Intune)
- ✅ Endpoint protection (Microsoft Defender for Endpoint)
- ✅ Security baseline & compliance

Suitable for greenfield projects (no prior infrastructure) at a scale of 10–100 users.

---

## 📁 Repository Structure

```
modern-workplace-toolkit/
│
├── scripts/
│   ├── ModernWorkplace-Setup.ps1         # Core setup: tenant, users, groups, MFA, Intune
│   ├── Assign-License.ps1                # Assign M365 Business Premium licenses to all users
│   ├── SecurityBaseline-Compliance.ps1   # Security baseline: CA, Defender, ASR, Audit Log
│   └── AD-Audit-Checklist.ps1            # On-premise AD audit (for hybrid/migration projects)
│
├── docs/
│   └── Checklist-Eksekusi-M365-Intune-MDE-EntraID.txt  # Full technical execution checklist
│
├── templates/
│   └── (SOW and document templates — coming soon)
│
└── README.md
```

---

## 🚀 Execution Order

Run the scripts in the following order:

### Step 1 — Core Setup
```powershell
.\scripts\ModernWorkplace-Setup.ps1
```
Covers: creating the M365 tenant, domain verification, creating 10 users + professional email, security groups, MFA (Security Defaults), Intune Compliance Policy, DKIM for Exchange Online.

### Step 2 — Assign Licenses
```powershell
.\scripts\Assign-License.ps1
```
Checks M365 Business Premium license availability, assigns to all users, verifies the result.

### Step 3 — Security Baseline
```powershell
.\scripts\SecurityBaseline-Compliance.ps1
```
Covers: 5 Conditional Access policies, Defender for Office 365 (Anti-phishing, Safe Links, Safe Attachments), Anti-Spam & Anti-Malware, SPF/DKIM/DMARC review, Intune Security Baseline, ASR Rules, Secure Score snapshot, Audit Log.

### Step 4 — (Optional) On-Premise AD Audit
```powershell
.\scripts\AD-Audit-Checklist.ps1
```
For projects with existing on-premise Active Directory planning a hybrid migration to Entra ID.

---

## ⚙️ Prerequisites

### Install the required PowerShell modules:
```powershell
Install-Module Microsoft.Graph           -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement  -Scope CurrentUser -Force
```

### Required accounts & access:
- Global Admin account for the client's M365 tenant
- A registered company domain (or a new one to be purchased)
- DNS management access for the domain
- M365 Business Premium licenses already purchased in the tenant

---

## 🔧 Configuration

Before running each script, edit the `$config` section at the top of the file:

```powershell
$config = @{
    Domain        = "companyname.com"       # Client domain
    CompanyName   = "PT Company Name"        # Company name
    AdminEmail    = "admin@domain.com"      # Admin email for notifications
    UsageLocation = "ID"                    # Country code: ID = Indonesia
    TempPassword  = "TempP@ssw0rd2026!"    # Temporary password for new users
}
```

And the user list in the `$users` section:
```powershell
$users = @(
    @{ FirstName = "Budi"; LastName = "Santoso"; Username = "budi.santoso"; JobTitle = "CEO"; Department = "Management" },
    # ... add users as needed
)
```

---

## 📊 Security Baseline Coverage

| Component | Script | Default Status |
|-----------|--------|-----------------|
| Block Legacy Authentication | SecurityBaseline-Compliance.ps1 | Enabled |
| Require MFA for All Users | SecurityBaseline-Compliance.ps1 | Enabled |
| Require Compliant Device | SecurityBaseline-Compliance.ps1 | Report-Only* |
| Block High-Risk Sign-in | SecurityBaseline-Compliance.ps1 | Enabled |
| Require MFA for Admin Roles | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Phishing Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Safe Links Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Safe Attachments Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Spam Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Malware Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| ASR Rules | SecurityBaseline-Compliance.ps1 | Audit Mode* |
| Intune Security Baseline | SecurityBaseline-Compliance.ps1 | Enabled |
| Unified Audit Log | SecurityBaseline-Compliance.ps1 | Enabled |
| Mailbox Auditing | SecurityBaseline-Compliance.ps1 | Enabled |

> *CA003 (Compliant Device): switch to Enforced once all devices are enrolled in Intune.
> *ASR Rules: review the Audit report for 1–2 weeks, then switch to Block mode.

---

## ⚠️ Important Notes

1. **Break-glass account** — create this manually in Entra before running the SecurityBaseline script, and set its UPN in `$config.BreakGlassUPN`. Store its credentials offline.
2. **DMARC** — start with `p=none` (monitoring), then move to `p=quarantine` after 2–4 weeks of reviewing reports.
3. **User credentials** — the generated `user-credentials.csv` file is sensitive. Do not send it via a WhatsApp group — hand it over securely to each user individually.
4. **Revoke admin access** — after handover is complete, revoke the consultant's Global Admin access from the client's tenant.
5. **Licensing** — make sure M365 Business Premium licenses are already available in the tenant before running `Assign-License.ps1`.

---

## 📄 License

MIT License — free to use and modify for consulting project needs.

---

## 👤 Author

**Dino A. Stephanus**
Cloud & Security Architect | Jakarta, Indonesia
20+ years of experience in IT Infrastructure & Cybersecurity

---

> This toolkit was built to speed up execution of Modern Workplace setup projects.
> Always review the configuration before deploying to a production environment.
