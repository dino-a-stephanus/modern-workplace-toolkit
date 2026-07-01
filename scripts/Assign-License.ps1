<#
=====================================================================
 ASSIGN LISENSI M365 BUSINESS PREMIUM
 Author : Dino A. Stephanus — Cloud & Security Architect
 Versi  : 1.0

 PREREQUISITE:
   Install-Module Microsoft.Graph -Scope CurrentUser -Force

 CARA PAKAI:
   1. Edit bagian CONFIG sesuai data klien
   2. Jalankan: .\Assign-License.ps1
   3. Script akan:
      - Cek ketersediaan lisensi di tenant
      - Assign lisensi ke semua user yang belum punya
      - Generate laporan hasil assignment

 CATATAN:
   - Pastikan lisensi sudah dibeli/tersedia di tenant sebelum jalankan
   - Cek jumlah lisensi tersedia di M365 admin center → Billing → Licenses
   - SKU M365 Business Premium: SPB atau
     cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46
=====================================================================
#>

# =====================================================================
# CONFIG — EDIT SESUAI DATA KLIEN
# =====================================================================

$config = @{
    Domain       = "namaperusahaan.com"
    CompanyName  = "PT Nama Perusahaan"
    OutputFolder = ".\LicenseOutput_$(Get-Date -Format 'yyyyMMdd_HHmm')"

    # Lokasi user (wajib diset sebelum assign lisensi)
    UsageLocation = "ID"  # Indonesia
}

# Daftar email user yang akan di-assign lisensi
# Sesuaikan dengan user yang sudah dibuat
$userEmails = @(
    "budi.santoso@$($config.Domain)",
    "sari.dewi@$($config.Domain)",
    "ahmad.fauzi@$($config.Domain)",
    "rina.wulandari@$($config.Domain)",
    "doni.prasetyo@$($config.Domain)",
    "maya.kusuma@$($config.Domain)",
    "hendra.wijaya@$($config.Domain)",
    "fitri.rahayu@$($config.Domain)",
    "bagus.nugroho@$($config.Domain)",
    "lestari.agung@$($config.Domain)"
)

# =====================================================================
# INISIALISASI
# =====================================================================

New-Item -ItemType Directory -Path $config.OutputFolder -Force | Out-Null
$logFile    = "$($config.OutputFolder)\license-log.txt"
$reportFile = "$($config.OutputFolder)\license-report.csv"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n$('='*60)" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$('='*60)" -ForegroundColor Cyan
    Write-Log "=== $Text ==="
}

Clear-Host
Write-Host @"
=====================================================================
 ASSIGN LISENSI M365 BUSINESS PREMIUM
 $($config.CompanyName)
 Konsultan: Dino A. Stephanus
=====================================================================
"@ -ForegroundColor Cyan

# =====================================================================
# STEP 1 — KONEKSI
# =====================================================================

Write-Step "STEP 1: Koneksi ke Microsoft Graph"

try {
    Connect-MgGraph -Scopes `
        "User.ReadWrite.All",
        "Directory.ReadWrite.All",
        "Organization.Read.All" `
        -ErrorAction Stop

    $org = Get-MgOrganization
    Write-Log "Terhubung ke tenant: $($org.DisplayName)" "Green"
} catch {
    Write-Log "GAGAL koneksi: $_" "Red"
    exit
}

# =====================================================================
# STEP 2 — CEK LISENSI TERSEDIA DI TENANT
# =====================================================================

Write-Step "STEP 2: Cek Ketersediaan Lisensi di Tenant"

$allSkus = Get-MgSubscribedSku
$targetSkus = @(
    "SPB",                                   # M365 Business Premium (nama pendek)
    "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46"  # M365 Business Premium (GUID)
)

$m365Sku = $allSkus | Where-Object {
    $_.SkuPartNumber -eq "SPB" -or
    $_.SkuId -eq "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46"
}

if (-not $m365Sku) {
    Write-Log "TIDAK DITEMUKAN lisensi M365 Business Premium di tenant ini!" "Red"
    Write-Host @"

Lisensi M365 Business Premium belum tersedia di tenant.
Beli lisensi dulu di: https://admin.microsoft.com → Billing → Purchase services
Cari: Microsoft 365 Business Premium

Atau minta klien untuk membeli langsung sebelum script ini dijalankan.
"@ -ForegroundColor Yellow

    Write-Host "`nSemua lisensi yang tersedia di tenant ini:" -ForegroundColor Yellow
    $allSkus | ForEach-Object {
        $avail = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
        Write-Host "  $($_.SkuPartNumber) | Total: $($_.PrepaidUnits.Enabled) | Terpakai: $($_.ConsumedUnits) | Tersedia: $avail"
    }
    exit
}

$totalLicenses   = $m365Sku.PrepaidUnits.Enabled
$usedLicenses    = $m365Sku.ConsumedUnits
$availLicenses   = $totalLicenses - $usedLicenses
$neededLicenses  = $userEmails.Count

Write-Host @"

Lisensi M365 Business Premium ditemukan:
  Total lisensi   : $totalLicenses
  Sudah terpakai  : $usedLicenses
  Tersedia        : $availLicenses
  Dibutuhkan      : $neededLicenses user
"@ -ForegroundColor Green

if ($availLicenses -lt $neededLicenses) {
    Write-Log "PERINGATAN: Lisensi tidak cukup! Tersedia $availLicenses, dibutuhkan $neededLicenses." "Red"
    Write-Host "Tambah lisensi di M365 admin center sebelum melanjutkan." -ForegroundColor Red
    $confirm = Read-Host "Tetap lanjutkan assign ke user yang bisa? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") { exit }
}

# =====================================================================
# STEP 3 — SET USAGE LOCATION & ASSIGN LISENSI
# =====================================================================

Write-Step "STEP 3: Assign Lisensi ke Semua User"

"Email,Status,Keterangan" | Out-File $reportFile
$successCount = 0
$skipCount    = 0
$failCount    = 0

$licensePayload = @{
    AddLicenses    = @(@{ SkuId = $m365Sku.SkuId })
    RemoveLicenses = @()
}

foreach ($email in $userEmails) {
    try {
        # Cari user
        $user = Get-MgUser -Filter "userPrincipalName eq '$email'" `
            -Property "Id,DisplayName,UserPrincipalName,AssignedLicenses,UsageLocation" `
            -ErrorAction Stop

        if (-not $user) {
            Write-Log "User tidak ditemukan: $email" "Yellow"
            "$email,SKIP,User tidak ditemukan di tenant" | Out-File $reportFile -Append
            $skipCount++
            continue
        }

        # Cek apakah sudah punya lisensi M365 Business Premium
        $hasLicense = $user.AssignedLicenses | Where-Object { $_.SkuId -eq $m365Sku.SkuId }
        if ($hasLicense) {
            Write-Log "SKIP: $($user.DisplayName) sudah punya lisensi M365 Business Premium." "Yellow"
            "$email,SKIP,Sudah punya lisensi" | Out-File $reportFile -Append
            $skipCount++
            continue
        }

        # Set UsageLocation jika belum diset (wajib sebelum assign lisensi)
        if (-not $user.UsageLocation) {
            Update-MgUser -UserId $user.Id -UsageLocation $config.UsageLocation
            Write-Log "Usage location diset ke $($config.UsageLocation) untuk $($user.DisplayName)." "Cyan"
        }

        # Assign lisensi
        Set-MgUserLicense -UserId $user.Id `
            -AddLicenses $licensePayload.AddLicenses `
            -RemoveLicenses $licensePayload.RemoveLicenses `
            -ErrorAction Stop

        Write-Log "BERHASIL: Lisensi di-assign ke $($user.DisplayName) ($email)" "Green"
        "$email,BERHASIL,Lisensi M365 Business Premium di-assign" | Out-File $reportFile -Append
        $successCount++

    } catch {
        Write-Log "GAGAL assign ke $email : $_" "Red"
        "$email,GAGAL,$_" | Out-File $reportFile -Append
        $failCount++
    }
}

# =====================================================================
# STEP 4 — VERIFIKASI HASIL
# =====================================================================

Write-Step "STEP 4: Verifikasi Hasil Assignment"

Write-Host "`nVerifikasi lisensi semua user..." -ForegroundColor Yellow
Write-Host ("{0,-35} {1,-20} {2}" -f "Email", "Nama", "Status Lisensi") -ForegroundColor Cyan
Write-Host ("-" * 75)

foreach ($email in $userEmails) {
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$email'" `
            -Property "DisplayName,AssignedLicenses" -ErrorAction SilentlyContinue

        if ($user) {
            $hasLicense = $user.AssignedLicenses | Where-Object { $_.SkuId -eq $m365Sku.SkuId }
            $status     = if ($hasLicense) { "✓ Licensed" } else { "✗ No License" }
            $color      = if ($hasLicense) { "Green" } else { "Red" }
            Write-Host ("{0,-35} {1,-20} {2}" -f $email, $user.DisplayName, $status) -ForegroundColor $color
        }
    } catch {
        Write-Host ("{0,-35} {1,-20} {2}" -f $email, "-", "Error cek status") -ForegroundColor Red
    }
}

# =====================================================================
# STEP 5 — LAPORAN FINAL
# =====================================================================

Write-Step "STEP 5: Laporan Final"

$summaryFile = "$($config.OutputFolder)\license-summary.txt"
@"
=====================================================================
 LAPORAN ASSIGN LISENSI M365 BUSINESS PREMIUM
 Klien     : $($config.CompanyName)
 Tanggal   : $(Get-Date -Format "dd MMMM yyyy HH:mm")
 Konsultan : Dino A. Stephanus
=====================================================================

RINGKASAN:
  Total user diproses  : $($userEmails.Count)
  Berhasil di-assign   : $successCount
  Sudah punya lisensi  : $skipCount
  Gagal                : $failCount

STATUS LISENSI TENANT SETELAH ASSIGNMENT:
  SKU            : M365 Business Premium (SPB)
  Total lisensi  : $totalLicenses
  Terpakai       : $($usedLicenses + $successCount)
  Tersisa        : $($availLicenses - $successCount)

FILE OUTPUT:
  - license-report.csv  : Detail status per user
  - license-log.txt     : Log lengkap proses
  - license-summary.txt : Ringkasan ini

LANGKAH BERIKUTNYA:
  1. Verifikasi di M365 admin center → Users → Active users
     (pastikan semua user status Licensed)
  2. Minta user login pertama kali & ganti password
  3. Setup MFA (Microsoft Authenticator) di HP masing-masing
  4. Lanjut ke setup Intune device enrollment
=====================================================================
"@ | Out-File $summaryFile

Write-Host @"

=====================================================================
 SELESAI!

 Berhasil   : $successCount user
 Skip       : $skipCount user (sudah punya lisensi)
 Gagal      : $failCount user

 Output folder: $($config.OutputFolder)
 - license-report.csv
 - license-summary.txt
 - license-log.txt
=====================================================================
"@ -ForegroundColor Green

Write-Log "Script selesai. Berhasil: $successCount | Skip: $skipCount | Gagal: $failCount"

Disconnect-MgGraph | Out-Null
