# 🛡️ Modern Workplace Toolkit
**Microsoft 365 + Intune + MDE + Azure Entra ID — PowerShell Automation**

> Toolkit otomasi setup Modern Workplace berbasis Microsoft untuk UKM, fintech, dan bank menengah.
> Dikembangkan oleh **Dino A. Stephanus** — Cloud & Security Architect

---

## 📋 Deskripsi

Repository ini berisi PowerShell scripts dan checklist untuk men-deploy lingkungan kerja modern yang aman secara end-to-end, mencakup:

- ✅ Identity management terpusat (Azure Entra ID)
- ✅ Email & kolaborasi profesional (Microsoft 365)
- ✅ Device management (Microsoft Intune)
- ✅ Proteksi endpoint (Microsoft Defender for Endpoint)
- ✅ Security baseline & compliance

Cocok untuk proyek greenfield (tanpa infrastruktur sebelumnya) skala 10–100 user.

---

## 📁 Struktur Repository

```
modern-workplace-toolkit/
│
├── scripts/
│   ├── ModernWorkplace-Setup.ps1         # Setup utama: tenant, user, groups, MFA, Intune
│   ├── Assign-License.ps1                # Assign lisensi M365 Business Premium ke semua user
│   ├── SecurityBaseline-Compliance.ps1   # Security baseline: CA, Defender, ASR, Audit Log
│   └── AD-Audit-Checklist.ps1            # Audit AD on-premise (untuk proyek hybrid/migrasi)
│
├── docs/
│   └── Checklist-Eksekusi-M365-Intune-MDE-EntraID.txt  # Checklist eksekusi teknis lengkap
│
├── templates/
│   └── (SOW dan template dokumen — coming soon)
│
└── README.md
```

---

## 🚀 Urutan Eksekusi

Jalankan scripts dalam urutan berikut:

### Step 1 — Setup Utama
```powershell
.\scripts\ModernWorkplace-Setup.ps1
```
Mencakup: buat tenant M365, verifikasi domain, buat 10 user + email profesional, security groups, MFA (Security Defaults), Intune Compliance Policy, DKIM Exchange Online.

### Step 2 — Assign Lisensi
```powershell
.\scripts\Assign-License.ps1
```
Cek ketersediaan lisensi M365 Business Premium, assign ke semua user, verifikasi hasil.

### Step 3 — Security Baseline
```powershell
.\scripts\SecurityBaseline-Compliance.ps1
```
Mencakup: 5 Conditional Access policies, Defender for Office 365 (Anti-phishing, Safe Links, Safe Attachments), Anti-Spam & Anti-Malware, SPF/DKIM/DMARC review, Intune Security Baseline, ASR Rules, Secure Score snapshot, Audit Log.

### Step 4 — (Opsional) Audit AD On-Premise
```powershell
.\scripts\AD-Audit-Checklist.ps1
```
Untuk proyek yang memiliki Active Directory on-premise dan berencana migrasi hybrid ke Entra ID.

---

## ⚙️ Prerequisites

### Install modul PowerShell yang diperlukan:
```powershell
Install-Module Microsoft.Graph           -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement  -Scope CurrentUser -Force
```

### Akun & akses yang diperlukan:
- Akun Global Admin tenant M365 klien
- Domain perusahaan yang sudah terdaftar (atau beli baru)
- Akses DNS management domain
- Lisensi M365 Business Premium sudah dibeli di tenant

---

## 🔧 Konfigurasi

Sebelum menjalankan setiap script, edit bagian `$config` di awal file:

```powershell
$config = @{
    Domain        = "namaperusahaan.com"    # Domain klien
    CompanyName   = "PT Nama Perusahaan"    # Nama perusahaan
    AdminEmail    = "admin@domain.com"      # Email admin untuk notifikasi
    UsageLocation = "ID"                    # Kode negara: ID = Indonesia
    TempPassword  = "TempP@ssw0rd2026!"    # Password sementara user baru
}
```

Dan daftar user di bagian `$users`:
```powershell
$users = @(
    @{ FirstName = "Budi"; LastName = "Santoso"; Username = "budi.santoso"; JobTitle = "CEO"; Department = "Management" },
    # ... tambahkan user sesuai kebutuhan
)
```

---

## 📊 Coverage Security Baseline

| Komponen | Script | Status Default |
|----------|--------|----------------|
| Block Legacy Authentication | SecurityBaseline-Compliance.ps1 | Enabled |
| Require MFA All Users | SecurityBaseline-Compliance.ps1 | Enabled |
| Require Compliant Device | SecurityBaseline-Compliance.ps1 | Report-Only* |
| Block High Risk Sign-in | SecurityBaseline-Compliance.ps1 | Enabled |
| Require MFA Admin Roles | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Phishing Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Safe Links Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Safe Attachments Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Spam Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| Anti-Malware Policy | SecurityBaseline-Compliance.ps1 | Enabled |
| ASR Rules | SecurityBaseline-Compliance.ps1 | Audit Mode* |
| Intune Security Baseline | SecurityBaseline-Compliance.ps1 | Enabled |
| Unified Audit Log | SecurityBaseline-Compliance.ps1 | Enabled |
| Mailbox Auditing | SecurityBaseline-Compliance.ps1 | Enabled |

> *CA003 (Compliant Device): aktifkan ke Enforced setelah semua device enrolled di Intune.
> *ASR Rules: review Audit report 1–2 minggu, lalu switch ke Block.

---

## ⚠️ Catatan Penting

1. **Break-glass account** — buat manual di Entra sebelum jalankan SecurityBaseline script, isi UPN-nya di `$config.BreakGlassUPN`. Simpan kredensialnya secara offline.
2. **DMARC** — mulai dengan `p=none` (monitoring), naik ke `p=quarantine` setelah 2–4 minggu review report.
3. **Credentials user** — file `user-credentials.csv` yang dihasilkan bersifat sensitif. Jangan kirim via WA grup — serahkan secara aman ke masing-masing user.
4. **Cabut akses admin** — setelah handover selesai, cabut akses Global Admin konsultan dari tenant klien.
5. **Lisensi** — pastikan lisensi M365 Business Premium sudah tersedia di tenant sebelum jalankan `Assign-License.ps1`.

---

## 📄 Lisensi

MIT License — bebas digunakan dan dimodifikasi untuk kebutuhan proyek konsultasi.

---

## 👤 Author

**Dino A. Stephanus**
Cloud & Security Architect | Jakarta, Indonesia
20+ tahun pengalaman IT Infrastructure & Cybersecurity

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-blue)](https://linkedin.com/in/dino-stephanus)

---

> Script ini dikembangkan untuk mempercepat eksekusi proyek Modern Workplace setup.
> Selalu lakukan review konfigurasi sebelum deploy ke lingkungan production.
