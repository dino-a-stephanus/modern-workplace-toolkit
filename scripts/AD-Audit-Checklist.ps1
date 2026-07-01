<#
=====================================================================
 AD AUDIT CHECKLIST - PRA MIGRASI KE AZURE ENTRA ID / M365
 Author: Dino A. Stephanus
 Tujuan: Inventory cepat kondisi AD on-premise sebelum setup
         Azure AD Connect, supaya potensi masalah sinkronisasi
         ketahuan dari awal.

 Cara pakai:
 1. Jalankan di Domain Controller atau server dengan RSAT AD
    Tools terinstall, pakai akun yang punya hak baca AD.
 2. Buka PowerShell as Administrator.
 3. Jalankan: .\AD-Audit-Checklist.ps1
 4. Hasil akan tersimpan di folder yang sama, format CSV/TXT,
    dengan timestamp di nama file.
=====================================================================
#>

Import-Module ActiveDirectory -ErrorAction Stop

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$outputFolder = ".\AD_Audit_$timestamp"
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

Write-Host "=== Memulai AD Audit Checklist ===" -ForegroundColor Cyan
Write-Host "Hasil akan disimpan di: $outputFolder`n"

# 1. Info Domain & Forest
Write-Host "[1/9] Mengecek info domain & forest..." -ForegroundColor Yellow
Get-ADDomain | Select-Object DNSRoot, DomainMode, PDCEmulator |
    Out-File "$outputFolder\01_DomainInfo.txt"
Get-ADForest | Select-Object Name, ForestMode |
    Out-File -Append "$outputFolder\01_DomainInfo.txt"

# 2. Jumlah & daftar Organizational Unit (OU)
Write-Host "[2/9] Menarik daftar OU..." -ForegroundColor Yellow
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName |
    Export-Csv "$outputFolder\02_OU_List.csv" -NoTypeInformation

# 3. Jumlah total user, aktif vs disabled
Write-Host "[3/9] Menghitung user aktif/nonaktif..." -ForegroundColor Yellow
$allUsers = Get-ADUser -Filter * -Properties Enabled, UserPrincipalName, EmailAddress
$activeUsers = $allUsers | Where-Object { $_.Enabled -eq $true }
$disabledUsers = $allUsers | Where-Object { $_.Enabled -eq $false }
"Total User       : $($allUsers.Count)" | Out-File "$outputFolder\03_UserSummary.txt"
"User Aktif       : $($activeUsers.Count)" | Out-File -Append "$outputFolder\03_UserSummary.txt"
"User Nonaktif    : $($disabledUsers.Count)" | Out-File -Append "$outputFolder\03_UserSummary.txt"
$allUsers | Select-Object Name, SamAccountName, UserPrincipalName, EmailAddress, Enabled |
    Export-Csv "$outputFolder\03_UserList.csv" -NoTypeInformation

# 4. User TANPA email (potensi masalah saat migrasi ke M365)
Write-Host "[4/9] Mencari user tanpa email address..." -ForegroundColor Yellow
$allUsers | Where-Object { -not $_.EmailAddress -and $_.Enabled -eq $true } |
    Select-Object Name, SamAccountName, UserPrincipalName |
    Export-Csv "$outputFolder\04_UsersWithoutEmail.csv" -NoTypeInformation

# 5. Cek UPN yang tidak pakai format domain valid (sering bikin sync gagal)
Write-Host "[5/9] Mengecek format UPN..." -ForegroundColor Yellow
$allUsers | Where-Object { $_.UserPrincipalName -notmatch "@.*\..*" } |
    Select-Object Name, SamAccountName, UserPrincipalName |
    Export-Csv "$outputFolder\05_InvalidUPN.csv" -NoTypeInformation

# 6. Cek potensi DUPLICATE proxyAddresses / UPN (penyebab umum sync error)
Write-Host "[6/9] Mengecek duplicate UPN..." -ForegroundColor Yellow
$allUsers | Group-Object UserPrincipalName |
    Where-Object { $_.Count -gt 1 } |
    Select-Object Name, Count |
    Export-Csv "$outputFolder\06_DuplicateUPN.csv" -NoTypeInformation

# 7. Daftar Security Groups & Distribution Groups
Write-Host "[7/9] Menarik daftar grup..." -ForegroundColor Yellow
Get-ADGroup -Filter * -Properties GroupCategory, GroupScope |
    Select-Object Name, GroupCategory, GroupScope, DistinguishedName |
    Export-Csv "$outputFolder\07_GroupList.csv" -NoTypeInformation

# 8. Daftar Group Policy Objects (GPO) - untuk rencana mapping ke Intune
Write-Host "[8/9] Menarik daftar GPO..." -ForegroundColor Yellow
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Get-GPO -All | Select-Object DisplayName, GpoStatus, ModificationTime |
        Export-Csv "$outputFolder\08_GPOList.csv" -NoTypeInformation
} catch {
    "Modul GroupPolicy tidak tersedia di server ini. Jalankan dari DC atau server dengan RSAT GPMC." |
        Out-File "$outputFolder\08_GPOList.csv"
}

# 9. Daftar komputer/device terdaftar di AD
Write-Host "[9/9] Menarik daftar device..." -ForegroundColor Yellow
Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate |
    Select-Object Name, OperatingSystem, LastLogonDate |
    Export-Csv "$outputFolder\09_ComputerList.csv" -NoTypeInformation

Write-Host "`n=== Audit selesai ===" -ForegroundColor Green
Write-Host "Cek folder: $outputFolder"
Write-Host "Perhatikan khusus file 04, 05, 06 - ini sering jadi penyebab"
Write-Host "Azure AD Connect sync error kalau tidak dibersihkan dulu."
Write-Host "`nRekomendasi: jalankan juga tool resmi IDFix dari Microsoft"
Write-Host "untuk validasi tambahan sebelum instalasi Azure AD Connect."
