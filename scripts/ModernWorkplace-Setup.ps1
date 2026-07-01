<#
=====================================================================
 MODERN WORKPLACE SETUP SCRIPT
 M365 + Intune + MDE + Azure Entra ID — 10 User
 Author : Dino A. Stephanus — Cloud & Security Architect
 Versi  : 1.0

 PREREQUISITE (jalankan sekali sebelum script ini):
   Install-Module Microsoft.Graph -Scope CurrentUser -Force
   Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

 CARA PAKAI:
   1. Edit bagian CONFIG di bawah sesuai data klien
   2. Buka PowerShell as Administrator
   3. Jalankan: .\ModernWorkplace-Setup.ps1
   4. Script akan berjalan step by step dengan konfirmasi di setiap fase

 CATATAN:
   - Intune & MDE policy sebagian besar dikonfigurasi via Microsoft Graph
   - Beberapa langkah (device enrollment, MDE onboarding per device)
     tetap harus dilakukan manual di portal karena butuh akses fisik ke device
   - Script ini mengotomasi bagian yang bisa diotomasi:
     user creation, groups, MFA, Conditional Access, compliance policy
=====================================================================
#>

# =====================================================================
# KONFIGURASI — EDIT BAGIAN INI SESUAI DATA KLIEN
# =====================================================================

$config = @{
    # Domain perusahaan klien (harus sudah diverifikasi di M365 tenant)
    Domain          = "namaperusahaan.com"

    # Nama perusahaan (untuk nama group, Teams, dll)
    CompanyName     = "PT Nama Perusahaan"

    # Email admin yang akan menerima notifikasi alert MDE
    AdminEmail      = "admin@namaperusahaan.com"

    # Password sementara untuk semua user baru
    # (user akan diminta ganti saat login pertama)
    TempPassword    = "TempP@ssw0rd2026!"

    # Output folder untuk log & dokumen hasil
    OutputFolder    = ".\Output_$(Get-Date -Format 'yyyyMMdd_HHmm')"
}

# Daftar 10 user — edit sesuai data klien
$users = @(
    @{ FirstName = "Budi";    LastName = "Santoso";   Username = "budi.santoso";   JobTitle = "CEO";             Department = "Management" },
    @{ FirstName = "Sari";    LastName = "Dewi";      Username = "sari.dewi";      JobTitle = "CFO";             Department = "Management" },
    @{ FirstName = "Ahmad";   LastName = "Fauzi";     Username = "ahmad.fauzi";    JobTitle = "IT Manager";      Department = "IT" },
    @{ FirstName = "Rina";    LastName = "Wulandari"; Username = "rina.wulandari"; JobTitle = "HR Manager";      Department = "HR" },
    @{ FirstName = "Doni";    LastName = "Prasetyo";  Username = "doni.prasetyo";  JobTitle = "Sales Manager";   Department = "Sales" },
    @{ FirstName = "Maya";    LastName = "Kusuma";    Username = "maya.kusuma";    JobTitle = "Marketing";       Department = "Marketing" },
    @{ FirstName = "Hendra";  LastName = "Wijaya";    Username = "hendra.wijaya";  JobTitle = "Finance Staff";   Department = "Finance" },
    @{ FirstName = "Fitri";   LastName = "Rahayu";    Username = "fitri.rahayu";   JobTitle = "Admin Staff";     Department = "Admin" },
    @{ FirstName = "Bagus";   LastName = "Nugroho";   Username = "bagus.nugroho";  JobTitle = "IT Support";      Department = "IT" },
    @{ FirstName = "Lestari"; LastName = "Agung";     Username = "lestari.agung";  JobTitle = "Customer Service"; Department = "CS" }
)

# =====================================================================
# INISIALISASI
# =====================================================================

New-Item -ItemType Directory -Path $config.OutputFolder -Force | Out-Null
$logFile = "$($config.OutputFolder)\setup-log.txt"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Write-Host $logEntry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logEntry
}

function Write-Step {
    param([string]$Step)
    Write-Host "`n$('='*60)" -ForegroundColor Cyan
    Write-Host " $Step" -ForegroundColor Cyan
    Write-Host "$('='*60)" -ForegroundColor Cyan
    Write-Log "=== $Step ==="
}

function Confirm-Continue {
    param([string]$Message = "Lanjutkan ke step berikutnya?")
    $response = Read-Host "`n$Message (Y/N)"
    return $response -eq "Y" -or $response -eq "y"
}

function Write-Summary {
    param([string]$Title, [hashtable]$Data)
    Write-Host "`n--- $Title ---" -ForegroundColor Yellow
    foreach ($key in $Data.Keys) {
        Write-Host "  $key : $($Data[$key])"
    }
}

Clear-Host
Write-Host @"
=====================================================================
 MODERN WORKPLACE SETUP
 $($config.CompanyName)
 M365 + Intune + MDE + Azure Entra ID
 Konsultan: Dino A. Stephanus
=====================================================================
"@ -ForegroundColor Cyan

Write-Log "Script dimulai untuk klien: $($config.CompanyName)"

# =====================================================================
# STEP 1 — KONEKSI KE MICROSOFT GRAPH
# =====================================================================

Write-Step "STEP 1: Koneksi ke Microsoft 365 (Microsoft Graph)"

Write-Host "`nMenghubungkan ke Microsoft Graph dengan scope yang diperlukan..."
Write-Host "Browser akan terbuka untuk login — gunakan akun Global Admin tenant klien." -ForegroundColor Yellow

try {
    Connect-MgGraph -Scopes `
        "User.ReadWrite.All",
        "Group.ReadWrite.All",
        "Directory.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "RoleManagement.ReadWrite.Directory",
        "Mail.ReadWrite",
        "Organization.Read.All" `
        -ErrorAction Stop

    $org = Get-MgOrganization
    Write-Log "Berhasil terhubung ke tenant: $($org.DisplayName)" "Green"
    Write-Host "`nTerhubung ke tenant: $($org.DisplayName)" -ForegroundColor Green
} catch {
    Write-Log "GAGAL koneksi ke Microsoft Graph: $_" "Red"
    Write-Host "Error: $_" -ForegroundColor Red
    exit
}

if (-not (Confirm-Continue "Koneksi berhasil. Lanjut buat Security Groups?")) { exit }

# =====================================================================
# STEP 2 — BUAT SECURITY GROUPS
# =====================================================================

Write-Step "STEP 2: Membuat Security Groups"

$groups = @(
    @{ Name = "All-Staff";   Description = "Semua karyawan $($config.CompanyName)" },
    @{ Name = "Management";  Description = "Tim Management $($config.CompanyName)" },
    @{ Name = "IT-Admin";    Description = "Tim IT & Admin $($config.CompanyName)" }
)

$createdGroups = @{}

foreach ($group in $groups) {
    try {
        $existing = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "Group '$($group.Name)' sudah ada, skip." "Yellow"
            $createdGroups[$group.Name] = $existing.Id
        } else {
            $newGroup = New-MgGroup -DisplayName $group.Name `
                -Description $group.Description `
                -MailEnabled:$false `
                -SecurityEnabled:$true `
                -MailNickname ($group.Name -replace " ", "") `
                -ErrorAction Stop
            $createdGroups[$group.Name] = $newGroup.Id
            Write-Log "Group '$($group.Name)' berhasil dibuat. ID: $($newGroup.Id)" "Green"
        }
    } catch {
        Write-Log "GAGAL buat group '$($group.Name)': $_" "Red"
    }
}

Write-Host "`nGroups yang tersedia:" -ForegroundColor Green
$createdGroups.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key) : $($_.Value)" }

if (-not (Confirm-Continue "Groups selesai. Lanjut buat 10 User?")) { exit }

# =====================================================================
# STEP 3 — BUAT 10 USER
# =====================================================================

Write-Step "STEP 3: Membuat 10 User dengan Email Profesional"

$credentialFile = "$($config.OutputFolder)\user-credentials.csv"
"Nama,Email,Password Sementara,Department,Job Title" | Out-File $credentialFile

$createdUserIds = @{}

$passwordProfile = @{
    Password                      = $config.TempPassword
    ForceChangePasswordNextSignIn = $true
}

foreach ($user in $users) {
    $upn = "$($user.Username)@$($config.Domain)"
    try {
        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "User '$upn' sudah ada, skip." "Yellow"
            $createdUserIds[$upn] = $existing.Id
        } else {
            $newUser = New-MgUser `
                -DisplayName "$($user.FirstName) $($user.LastName)" `
                -GivenName $user.FirstName `
                -Surname $user.LastName `
                -UserPrincipalName $upn `
                -MailNickname $user.Username `
                -JobTitle $user.JobTitle `
                -Department $user.Department `
                -PasswordProfile $passwordProfile `
                -AccountEnabled:$true `
                -UsageLocation "ID" `
                -ErrorAction Stop

            $createdUserIds[$upn] = $newUser.Id
            Write-Log "User '$upn' berhasil dibuat." "Green"

            # Simpan ke CSV
            "$($user.FirstName) $($user.LastName),$upn,$($config.TempPassword),$($user.Department),$($user.JobTitle)" |
                Out-File $credentialFile -Append
        }

        # Tambahkan ke group All-Staff
        if ($createdGroups["All-Staff"]) {
            try {
                New-MgGroupMember -GroupId $createdGroups["All-Staff"] `
                    -DirectoryObjectId $createdUserIds[$upn] -ErrorAction SilentlyContinue
            } catch { }
        }

        # Tambahkan ke group Management jika departemennya Management
        if ($user.Department -eq "Management" -and $createdGroups["Management"]) {
            try {
                New-MgGroupMember -GroupId $createdGroups["Management"] `
                    -DirectoryObjectId $createdUserIds[$upn] -ErrorAction SilentlyContinue
            } catch { }
        }

        # Tambahkan ke group IT-Admin jika departemennya IT
        if ($user.Department -eq "IT" -and $createdGroups["IT-Admin"]) {
            try {
                New-MgGroupMember -GroupId $createdGroups["IT-Admin"] `
                    -DirectoryObjectId $createdUserIds[$upn] -ErrorAction SilentlyContinue
            } catch { }
        }

    } catch {
        Write-Log "GAGAL buat user '$upn': $_" "Red"
    }
}

Write-Host "`nKredensial user tersimpan di: $credentialFile" -ForegroundColor Yellow
Write-Host "PENTING: Jangan kirim file ini via WA grup — serahkan secara aman ke masing-masing user." -ForegroundColor Red

if (-not (Confirm-Continue "User selesai dibuat. Lanjut setup MFA & Security Defaults?")) { exit }

# =====================================================================
# STEP 4 — AKTIFKAN SECURITY DEFAULTS (MFA)
# =====================================================================

Write-Step "STEP 4: Aktifkan Security Defaults (MFA untuk semua user)"

try {
    $securityDefaults = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
    if ($securityDefaults.IsEnabled) {
        Write-Log "Security Defaults sudah aktif." "Yellow"
    } else {
        Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -IsEnabled:$true
        Write-Log "Security Defaults berhasil diaktifkan." "Green"
    }
    Write-Host "Security Defaults (MFA) AKTIF — semua user wajib setup MFA saat login pertama." -ForegroundColor Green
} catch {
    Write-Log "GAGAL aktifkan Security Defaults: $_" "Red"
    Write-Host "Aktifkan manual di: Entra admin center → Identity → Overview → Properties → Manage Security Defaults" -ForegroundColor Yellow
}

Write-Host @"

CATATAN: Jika ingin pakai Conditional Access custom (lebih fleksibel),
matikan Security Defaults terlebih dahulu lalu buat CA policy manual
di Entra admin center → Protection → Conditional Access.

Untuk skala 10 user, Security Defaults sudah sangat cukup.
"@ -ForegroundColor Cyan

if (-not (Confirm-Continue "MFA selesai. Lanjut setup Intune Compliance Policy?")) { exit }

# =====================================================================
# STEP 5 — INTUNE COMPLIANCE POLICY (via Graph)
# =====================================================================

Write-Step "STEP 5: Setup Intune Compliance Policy via Microsoft Graph"

Write-Host "Membuat compliance policy untuk Windows 10/11..." -ForegroundColor Yellow

$compliancePolicyBody = @{
    "@odata.type"                          = "#microsoft.graph.windows10CompliancePolicy"
    displayName                            = "Windows Compliance Policy - $($config.CompanyName)"
    description                            = "Compliance policy untuk semua device Windows"
    bitLockerEnabled                       = $true
    secureBootEnabled                      = $true
    codeIntegrityEnabled                   = $true
    storageRequireEncryption               = $true
    passwordRequired                       = $true
    passwordMinimumLength                  = 8
    passwordRequiredType                   = "alphanumeric"
    passwordMinutesOfInactivityBeforeLock  = 15
    osMinimumVersion                       = "10.0.19041"
} | ConvertTo-Json -Depth 5

try {
    $result = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" `
        -Body $compliancePolicyBody `
        -ContentType "application/json"

    Write-Log "Compliance Policy berhasil dibuat. ID: $($result.id)" "Green"
    Write-Host "Compliance Policy berhasil dibuat!" -ForegroundColor Green

    # Assign ke All-Staff group
    if ($createdGroups["All-Staff"]) {
        $assignBody = @{
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId       = $createdGroups["All-Staff"]
                    }
                }
            )
        } | ConvertTo-Json -Depth 5

        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($result.id)/assign" `
            -Body $assignBody `
            -ContentType "application/json" | Out-Null

        Write-Log "Compliance Policy di-assign ke group All-Staff." "Green"
    }
} catch {
    Write-Log "GAGAL buat Compliance Policy via Graph: $_" "Red"
    Write-Host "Buat manual di: Intune admin center → Devices → Compliance policies" -ForegroundColor Yellow
}

if (-not (Confirm-Continue "Compliance Policy selesai. Lanjut setup MDE Alert Notification?")) { exit }

# =====================================================================
# STEP 6 — MDE: CATATAN & PANDUAN ONBOARDING
# =====================================================================

Write-Step "STEP 6: Microsoft Defender for Endpoint (MDE) — Panduan Onboarding"

Write-Host @"

MDE onboarding device tidak bisa sepenuhnya diotomasi via script
karena butuh akses fisik ke masing-masing device.

Langkah yang harus dilakukan MANUAL di portal:

1. Login ke: https://security.microsoft.com
2. Settings → Endpoints → Onboarding
3. Pilih metode: Microsoft Intune
   (device yang sudah enrolled di Intune akan otomatis onboard ke MDE
    melalui Endpoint Security policy)

Atau via Intune admin center:
1. https://intune.microsoft.com
2. Endpoint security → Endpoint detection and response
3. Create policy → Windows 10 and later → EDR
4. Assign ke group All-Staff

Setelah device onboard, verifikasi di:
Microsoft Defender portal → Assets → Devices
(semua 10 device harus muncul dengan status: Onboarded)

"@ -ForegroundColor Cyan

# Buat file panduan MDE
$mdePanduan = "$($config.OutputFolder)\MDE-Onboarding-Panduan.txt"
@"
PANDUAN MDE ONBOARDING — $($config.CompanyName)

1. Pastikan semua device sudah enrolled di Intune
2. Login ke https://intune.microsoft.com
3. Endpoint security → Endpoint detection and response → Create policy
   - Platform: Windows 10 and later
   - Profile: Endpoint detection and response
   - Name: MDE Policy - $($config.CompanyName)
   - Microsoft Defender for Endpoint client config: Auto from connector
4. Assign ke group: All-Staff
5. Verifikasi di https://security.microsoft.com → Assets → Devices

Device yang harus onboard:
$(($users | ForEach-Object { "- $($_.FirstName) $($_.LastName) ($($_.Department))" }) -join "`n")
"@ | Out-File $mdePanduan

Write-Log "Panduan MDE onboarding tersimpan di: $mdePanduan" "Green"

if (-not (Confirm-Continue "Lanjut connect ke Exchange Online untuk konfigurasi email?")) { exit }

# =====================================================================
# STEP 7 — EXCHANGE ONLINE: DKIM & KONFIGURASI EMAIL
# =====================================================================

Write-Step "STEP 7: Exchange Online — Konfigurasi Email & DKIM"

try {
    Write-Host "Menghubungkan ke Exchange Online..." -ForegroundColor Yellow
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Log "Berhasil terhubung ke Exchange Online." "Green"

    # Aktifkan DKIM
    Write-Host "Mengaktifkan DKIM untuk domain $($config.Domain)..." -ForegroundColor Yellow
    try {
        Set-DkimSigningConfig -Identity $config.Domain -Enabled $true -ErrorAction Stop
        Write-Log "DKIM berhasil diaktifkan untuk $($config.Domain)." "Green"
        Write-Host "DKIM AKTIF." -ForegroundColor Green
    } catch {
        # Jika belum ada config, buat dulu
        try {
            New-DkimSigningConfig -DomainName $config.Domain -Enabled $true -ErrorAction Stop
            Write-Log "DKIM signing config baru dibuat dan diaktifkan." "Green"
        } catch {
            Write-Log "GAGAL aktifkan DKIM: $_" "Red"
            Write-Host "Aktifkan DKIM manual di Exchange admin center → Email authentication" -ForegroundColor Yellow
        }
    }

    # Tampilkan CNAME record DKIM untuk ditambahkan ke DNS
    Write-Host "`nTambahkan CNAME record berikut ke DNS domain klien:" -ForegroundColor Yellow
    Write-Host "  selector1._domainkey.$($config.Domain)  →  selector1-$($config.Domain -replace '\.', '-')._domainkey.$($config.Domain).onmicrosoft.com"
    Write-Host "  selector2._domainkey.$($config.Domain)  →  selector2-$($config.Domain -replace '\.', '-')._domainkey.$($config.Domain).onmicrosoft.com"

    # Cek status email
    Write-Host "`nMenguji koneksi email..." -ForegroundColor Yellow
    $mailboxes = Get-EXOMailbox -ResultSize 10
    Write-Log "Mailbox aktif: $($mailboxes.Count)" "Green"
    Write-Host "Mailbox aktif: $($mailboxes.Count)" -ForegroundColor Green

    Disconnect-ExchangeOnline -Confirm:$false

} catch {
    Write-Log "GAGAL koneksi Exchange Online: $_" "Red"
    Write-Host "Konfigurasi Exchange Online perlu dilakukan manual di: https://admin.exchange.microsoft.com" -ForegroundColor Yellow
}

if (-not (Confirm-Continue "Exchange selesai. Lanjut generate laporan final?")) { exit }

# =====================================================================
# STEP 8 — LAPORAN FINAL
# =====================================================================

Write-Step "STEP 8: Generate Laporan Final"

$reportFile = "$($config.OutputFolder)\Setup-Report.txt"

@"
=====================================================================
 LAPORAN SETUP MODERN WORKPLACE
 Klien    : $($config.CompanyName)
 Domain   : $($config.Domain)
 Tanggal  : $(Get-Date -Format "dd MMMM yyyy HH:mm")
 Konsultan: Dino A. Stephanus
=====================================================================

STATUS KOMPONEN:
[ ] M365 Tenant          : Aktif
[ ] Custom Domain        : Terverifikasi
[ ] DNS (MX/SPF/DKIM)   : Dikonfigurasi (DMARC: manual — p=none)
[ ] 10 User dibuat       : Email aktif di $($config.Domain)
[ ] Security Groups      : All-Staff, Management, IT-Admin
[ ] MFA (Security Default): Aktif
[ ] Intune Compliance    : Policy dibuat & di-assign
[ ] MDE Onboarding       : Lihat panduan di file MDE-Onboarding-Panduan.txt
[ ] Exchange Online      : DKIM aktif
[ ] SharePoint & Teams   : Setup manual di portal (lihat checklist)

DAFTAR USER:
$(($users | ForEach-Object { "  $($_.FirstName) $($_.LastName) | $($_.Username)@$($config.Domain) | $($_.JobTitle) | $($_.Department)" }) -join "`n")

FILE YANG DIHASILKAN:
- user-credentials.csv   : Daftar user & password sementara
- MDE-Onboarding-Panduan.txt : Panduan onboarding device ke MDE
- setup-log.txt          : Log lengkap proses setup

LANGKAH MANUAL YANG MASIH DIPERLUKAN:
1. Tambahkan DKIM CNAME record ke DNS domain
2. Tambahkan DMARC record ke DNS (p=none dulu)
3. Setup SharePoint site & Teams channel di portal
4. Enroll 10 device ke Intune (manual di masing-masing device)
5. Onboarding device ke MDE via Intune EDR policy
6. Assign lisensi M365 Business Premium ke semua user di admin center
7. Training admin & karyawan

PENTING SETELAH PROYEK SELESAI:
- Cabut akses Global Admin Dino dari tenant
- Serahkan break-glass account credentials secara offline ke klien
- Tawarkan paket maintenance bulanan

=====================================================================
"@ | Out-File $reportFile

Write-Log "Laporan final tersimpan di: $reportFile" "Green"

# =====================================================================
# SELESAI
# =====================================================================

Write-Host @"

=====================================================================
 SETUP SCRIPT SELESAI
 Output folder: $($config.OutputFolder)

 File yang dihasilkan:
 - user-credentials.csv         (RAHASIA — serahkan aman ke klien)
 - MDE-Onboarding-Panduan.txt
 - Setup-Report.txt
 - setup-log.txt

 Langkah berikutnya:
 1. Tambahkan DKIM & DMARC record ke DNS
 2. Enroll device ke Intune (manual per device)
 3. Setup SharePoint & Teams di portal
 4. Onboarding MDE via Intune EDR policy
 5. Training admin & karyawan
 6. Handover & cabut akses admin Dino
=====================================================================
"@ -ForegroundColor Green

Write-Log "Script selesai. Output: $($config.OutputFolder)"
