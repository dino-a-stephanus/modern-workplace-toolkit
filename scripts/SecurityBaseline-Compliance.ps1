<#
=====================================================================
 SECURITY BASELINE & COMPLIANCE SETUP
 M365 + Entra ID + Defender for Office 365 + Intune
 Author : Dino A. Stephanus — Cloud & Security Architect
 Versi  : 1.0

 PREREQUISITE:
   Install-Module Microsoft.Graph     -Scope CurrentUser -Force
   Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

 CARA PAKAI:
   1. Edit bagian CONFIG sesuai data klien
   2. Jalankan: .\SecurityBaseline-Compliance.ps1
   3. Setiap fase ada konfirmasi Y/N sebelum lanjut

 COVERAGE:
   [A] Conditional Access Policies (Entra ID)
   [B] Defender for Office 365 (Anti-phishing, Safe Links, Safe Attachments)
   [C] Anti-Spam & Anti-Malware (Exchange Online)
   [D] DMARC / Email Authentication Review
   [E] Intune Security Baseline (Windows)
   [F] Attack Surface Reduction (ASR) Rules
   [G] Microsoft Secure Score Snapshot
   [H] Audit Log & Compliance Settings
   [I] Laporan Security Baseline
=====================================================================
#>

# =====================================================================
# CONFIG — EDIT SESUAI DATA KLIEN
# =====================================================================

$config = @{
    Domain        = "namaperusahaan.com"
    CompanyName   = "PT Nama Perusahaan"
    AdminEmail    = "admin@namaperusahaan.com"
    UsageLocation = "ID"
    OutputFolder  = ".\SecurityBaseline_$(Get-Date -Format 'yyyyMMdd_HHmm')"

    # Group ID dari script setup sebelumnya
    # Cek di Entra admin center → Groups jika belum tahu ID-nya
    AllStaffGroupId   = ""   # Isi dengan Object ID group All-Staff
    ManagementGroupId = ""   # Isi dengan Object ID group Management
    ITAdminGroupId    = ""   # Isi dengan Object ID group IT-Admin

    # Break-glass account — EXCLUDE dari semua CA policy
    # Buat dulu manual di Entra, lalu isi UPN-nya di sini
    BreakGlassUPN = "breakglass@namaperusahaan.com"
}

# =====================================================================
# INISIALISASI
# =====================================================================

New-Item -ItemType Directory -Path $config.OutputFolder -Force | Out-Null
$logFile    = "$($config.OutputFolder)\security-log.txt"
$reportFile = "$($config.OutputFolder)\security-baseline-report.txt"
$scoreFile  = "$($config.OutputFolder)\secure-score-snapshot.csv"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n$('='*65)" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$('='*65)" -ForegroundColor Cyan
    Write-Log "=== $Text ==="
}

function Confirm-Continue {
    param([string]$Message = "Lanjutkan ke step berikutnya?")
    $r = Read-Host "`n$Message (Y/N)"
    return ($r -eq "Y" -or $r -eq "y")
}

function Write-Status {
    param([string]$Item, [string]$Status, [string]$Note = "")
    $color = switch ($Status) {
        "OK"      { "Green" }
        "SKIP"    { "Yellow" }
        "MANUAL"  { "Cyan" }
        "GAGAL"   { "Red" }
        default   { "White" }
    }
    $line = "  [{0,-6}] {1}" -f $Status, $Item
    if ($Note) { $line += " — $Note" }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line
}

# Tracking status semua komponen untuk laporan akhir
$baselineStatus = [ordered]@{}

Clear-Host
Write-Host @"
=====================================================================
 SECURITY BASELINE & COMPLIANCE SETUP
 $($config.CompanyName)
 Konsultan: Dino A. Stephanus
=====================================================================
"@ -ForegroundColor Cyan

# =====================================================================
# KONEKSI
# =====================================================================

Write-Step "KONEKSI: Microsoft Graph & Exchange Online"

try {
    Connect-MgGraph -Scopes `
        "Policy.ReadWrite.ConditionalAccess",
        "Policy.Read.All",
        "Directory.ReadWrite.All",
        "DeviceManagementConfiguration.ReadWrite.All",
        "SecurityEvents.Read.All",
        "User.Read.All",
        "Group.Read.All",
        "Organization.Read.All",
        "Reports.Read.All" `
        -ErrorAction Stop

    $org = Get-MgOrganization
    Write-Log "Graph: terhubung ke tenant $($org.DisplayName)" "Green"
} catch {
    Write-Log "GAGAL koneksi Graph: $_" "Red"; exit
}

try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Log "Exchange Online: terhubung." "Green"
} catch {
    Write-Log "GAGAL koneksi Exchange Online: $_" "Red"
    Write-Host "Beberapa step (Defender, Anti-spam) akan di-skip." -ForegroundColor Yellow
}

# Ambil break-glass user ID untuk exclude dari CA policy
$breakGlassId = $null
if ($config.BreakGlassUPN) {
    try {
        $bgUser = Get-MgUser -Filter "userPrincipalName eq '$($config.BreakGlassUPN)'"
        $breakGlassId = $bgUser.Id
        Write-Log "Break-glass account ditemukan: $($config.BreakGlassUPN)" "Green"
    } catch {
        Write-Log "Break-glass account tidak ditemukan — CA policy tanpa exclusion." "Yellow"
    }
}

if (-not (Confirm-Continue "Koneksi berhasil. Mulai setup Conditional Access?")) { exit }

# =====================================================================
# [A] CONDITIONAL ACCESS POLICIES
# =====================================================================

Write-Step "[A] Conditional Access Policies (Entra ID)"

# Matikan Security Defaults dulu sebelum buat CA custom
# (CA dan Security Defaults tidak bisa aktif bersamaan)
Write-Host "`nMematikan Security Defaults untuk mengaktifkan Conditional Access custom..." -ForegroundColor Yellow
try {
    Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -IsEnabled:$false
    Write-Log "Security Defaults dimatikan — CA custom akan diaktifkan." "Green"
    Write-Status "Security Defaults OFF" "OK" "Diganti dengan Conditional Access custom"
} catch {
    Write-Log "Gagal matikan Security Defaults: $_" "Yellow"
    Write-Status "Security Defaults" "SKIP" "Matikan manual di Entra → Properties"
}

# Helper: buat CA policy
function New-CAPolicy {
    param(
        [string]$DisplayName,
        [hashtable]$Body
    )
    $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$DisplayName'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "CA Policy '$DisplayName' sudah ada, skip." "Yellow"
        Write-Status "CA: $DisplayName" "SKIP" "Sudah ada"
        return $existing
    }
    try {
        $policy = New-MgIdentityConditionalAccessPolicy -BodyParameter $Body -ErrorAction Stop
        Write-Log "CA Policy '$DisplayName' berhasil dibuat. ID: $($policy.Id)" "Green"
        Write-Status "CA: $DisplayName" "OK"
        return $policy
    } catch {
        Write-Log "GAGAL buat CA '$DisplayName': $_" "Red"
        Write-Status "CA: $DisplayName" "GAGAL" "$_"
        return $null
    }
}

# Exclude break-glass dari semua policy
$excludeUsers = if ($breakGlassId) { @($breakGlassId) } else { @() }

# CA Policy 1: Block Legacy Authentication
$caLegacyBlock = New-CAPolicy -DisplayName "CA001 - Block Legacy Authentication" -Body @{
    displayName = "CA001 - Block Legacy Authentication"
    state       = "enabled"
    conditions  = @{
        users       = @{ includeUsers = @("All"); excludeUsers = $excludeUsers }
        clientAppTypes = @("exchangeActiveSync", "other")
    }
    grantControls = @{ operator = "OR"; builtInControls = @("block") }
}
$baselineStatus["CA001 Block Legacy Auth"] = if ($caLegacyBlock) { "OK" } else { "GAGAL" }

# CA Policy 2: Require MFA for All Users
$caMFA = New-CAPolicy -DisplayName "CA002 - Require MFA All Users" -Body @{
    displayName = "CA002 - Require MFA All Users"
    state       = "enabled"
    conditions  = @{
        users      = @{ includeUsers = @("All"); excludeUsers = $excludeUsers }
        clientAppTypes = @("all")
    }
    grantControls = @{ operator = "OR"; builtInControls = @("mfa") }
}
$baselineStatus["CA002 Require MFA"] = if ($caMFA) { "OK" } else { "GAGAL" }

# CA Policy 3: Require Compliant Device
$caCompliant = New-CAPolicy -DisplayName "CA003 - Require Compliant Device" -Body @{
    displayName = "CA003 - Require Compliant Device"
    state       = "enabledForReportingButNotEnforced"  # Report-only dulu sampai semua device enrolled
    conditions  = @{
        users      = @{ includeUsers = @("All"); excludeUsers = $excludeUsers }
        clientAppTypes = @("all")
    }
    grantControls = @{
        operator        = "OR"
        builtInControls = @("compliantDevice", "domainJoinedDevice")
    }
}
$baselineStatus["CA003 Compliant Device"] = if ($caCompliant) { "OK (Report-Only)" } else { "GAGAL" }

# CA Policy 4: Block High-Risk Sign-in
$caRisk = New-CAPolicy -DisplayName "CA004 - Block High Risk Sign-in" -Body @{
    displayName = "CA004 - Block High Risk Sign-in"
    state       = "enabled"
    conditions  = @{
        users    = @{ includeUsers = @("All"); excludeUsers = $excludeUsers }
        signInRiskLevels = @("high")
        clientAppTypes   = @("all")
    }
    grantControls = @{ operator = "OR"; builtInControls = @("block") }
}
$baselineStatus["CA004 Block High Risk"] = if ($caRisk) { "OK" } else { "GAGAL" }

# CA Policy 5: MFA Required for Admin Roles
$caAdminMFA = New-CAPolicy -DisplayName "CA005 - Require MFA for Admin Roles" -Body @{
    displayName = "CA005 - Require MFA for Admin Roles"
    state       = "enabled"
    conditions  = @{
        users = @{
            includeRoles = @(
                "62e90394-69f5-4237-9190-012177145e10",  # Global Administrator
                "f28a1f50-f6e7-4571-818b-6a12f2af6b6c",  # SharePoint Administrator
                "29232cdf-9323-42fd-ade2-1d097af3e4de",  # Exchange Administrator
                "b0f54661-2d74-4c50-afa3-1ec803f12efe",  # Billing Administrator
                "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3"   # Application Administrator
            )
            excludeUsers = $excludeUsers
        }
        clientAppTypes = @("all")
    }
    grantControls = @{ operator = "OR"; builtInControls = @("mfa") }
}
$baselineStatus["CA005 Admin MFA"] = if ($caAdminMFA) { "OK" } else { "GAGAL" }

Write-Host "`nSemua Conditional Access Policy selesai dibuat." -ForegroundColor Green
Write-Host "CATATAN: CA003 (Compliant Device) dalam mode Report-Only." -ForegroundColor Yellow
Write-Host "Aktifkan ke Enforced setelah semua device enrolled di Intune." -ForegroundColor Yellow

if (-not (Confirm-Continue "CA selesai. Lanjut Defender for Office 365?")) { exit }

# =====================================================================
# [B] DEFENDER FOR OFFICE 365
# =====================================================================

Write-Step "[B] Defender for Office 365 — Anti-Phishing, Safe Links, Safe Attachments"

# B1: Anti-Phishing Policy
try {
    $existingAP = Get-AntiPhishPolicy -Identity "AntiPhish-$($config.CompanyName)" -ErrorAction SilentlyContinue
    if (-not $existingAP) {
        New-AntiPhishPolicy `
            -Name "AntiPhish-$($config.CompanyName)" `
            -Enabled $true `
            -EnableMailboxIntelligence $true `
            -EnableMailboxIntelligenceProtection $true `
            -EnableSpoofIntelligence $true `
            -EnableFirstContactSafetyTips $true `
            -PhishThresholdLevel 2 `
            -ErrorAction Stop | Out-Null

        New-AntiPhishRule `
            -Name "AntiPhishRule-$($config.CompanyName)" `
            -AntiPhishPolicy "AntiPhish-$($config.CompanyName)" `
            -RecipientDomainIs $config.Domain `
            -Priority 0 | Out-Null

        Write-Log "Anti-Phishing policy berhasil dibuat." "Green"
        Write-Status "Anti-Phishing Policy" "OK"
    } else {
        Write-Log "Anti-Phishing policy sudah ada, skip." "Yellow"
        Write-Status "Anti-Phishing Policy" "SKIP" "Sudah ada"
    }
    $baselineStatus["Defender Anti-Phishing"] = "OK"
} catch {
    Write-Log "GAGAL buat Anti-Phishing policy: $_" "Red"
    Write-Status "Anti-Phishing Policy" "GAGAL" "$_"
    $baselineStatus["Defender Anti-Phishing"] = "GAGAL"
}

# B2: Safe Links Policy
try {
    $existingSL = Get-SafeLinksPolicy -Identity "SafeLinks-$($config.CompanyName)" -ErrorAction SilentlyContinue
    if (-not $existingSL) {
        New-SafeLinksPolicy `
            -Name "SafeLinks-$($config.CompanyName)" `
            -IsEnabled $true `
            -ScanUrls $true `
            -EnableForInternalSenders $true `
            -DeliverMessageAfterScan $true `
            -DisableUrlRewrite $false `
            -ErrorAction Stop | Out-Null

        New-SafeLinksRule `
            -Name "SafeLinksRule-$($config.CompanyName)" `
            -SafeLinksPolicy "SafeLinks-$($config.CompanyName)" `
            -RecipientDomainIs $config.Domain `
            -Priority 0 | Out-Null

        Write-Log "Safe Links policy berhasil dibuat." "Green"
        Write-Status "Safe Links Policy" "OK"
    } else {
        Write-Log "Safe Links policy sudah ada, skip." "Yellow"
        Write-Status "Safe Links Policy" "SKIP" "Sudah ada"
    }
    $baselineStatus["Defender Safe Links"] = "OK"
} catch {
    Write-Log "GAGAL buat Safe Links policy: $_" "Red"
    Write-Status "Safe Links Policy" "GAGAL" "$_"
    $baselineStatus["Defender Safe Links"] = "GAGAL"
}

# B3: Safe Attachments Policy
try {
    $existingSA = Get-SafeAttachmentPolicy -Identity "SafeAttach-$($config.CompanyName)" -ErrorAction SilentlyContinue
    if (-not $existingSA) {
        New-SafeAttachmentPolicy `
            -Name "SafeAttach-$($config.CompanyName)" `
            -Enable $true `
            -Action Block `
            -ActionOnError $true `
            -ErrorAction Stop | Out-Null

        New-SafeAttachmentRule `
            -Name "SafeAttachRule-$($config.CompanyName)" `
            -SafeAttachmentPolicy "SafeAttach-$($config.CompanyName)" `
            -RecipientDomainIs $config.Domain `
            -Priority 0 | Out-Null

        Write-Log "Safe Attachments policy berhasil dibuat." "Green"
        Write-Status "Safe Attachments Policy" "OK"
    } else {
        Write-Log "Safe Attachments policy sudah ada, skip." "Yellow"
        Write-Status "Safe Attachments Policy" "SKIP" "Sudah ada"
    }
    $baselineStatus["Defender Safe Attachments"] = "OK"
} catch {
    Write-Log "GAGAL buat Safe Attachments policy: $_" "Red"
    Write-Status "Safe Attachments Policy" "GAGAL" "$_"
    $baselineStatus["Defender Safe Attachments"] = "GAGAL"
}

if (-not (Confirm-Continue "Defender for Office 365 selesai. Lanjut Anti-Spam & Anti-Malware?")) { exit }

# =====================================================================
# [C] ANTI-SPAM & ANTI-MALWARE
# =====================================================================

Write-Step "[C] Anti-Spam & Anti-Malware (Exchange Online)"

# C1: Anti-Spam Policy
try {
    $existingSpam = Get-HostedContentFilterPolicy -Identity "AntiSpam-$($config.CompanyName)" -ErrorAction SilentlyContinue
    if (-not $existingSpam) {
        New-HostedContentFilterPolicy `
            -Name "AntiSpam-$($config.CompanyName)" `
            -SpamAction MoveToJmf `
            -HighConfidenceSpamAction Quarantine `
            -PhishSpamAction Quarantine `
            -HighConfidencePhishAction Quarantine `
            -BulkThreshold 6 `
            -EnableEndUserSpamNotifications $true `
            -EndUserSpamNotificationFrequency 1 `
            -ErrorAction Stop | Out-Null

        New-HostedContentFilterRule `
            -Name "AntiSpamRule-$($config.CompanyName)" `
            -HostedContentFilterPolicy "AntiSpam-$($config.CompanyName)" `
            -RecipientDomainIs $config.Domain `
            -Priority 0 | Out-Null

        Write-Log "Anti-Spam policy berhasil dibuat." "Green"
        Write-Status "Anti-Spam Policy" "OK"
    } else {
        Write-Log "Anti-Spam policy sudah ada, skip." "Yellow"
        Write-Status "Anti-Spam Policy" "SKIP" "Sudah ada"
    }
    $baselineStatus["Anti-Spam"] = "OK"
} catch {
    Write-Log "GAGAL buat Anti-Spam policy: $_" "Red"
    Write-Status "Anti-Spam Policy" "GAGAL" "$_"
    $baselineStatus["Anti-Spam"] = "GAGAL"
}

# C2: Anti-Malware Policy
try {
    $existingMal = Get-MalwareFilterPolicy -Identity "AntiMalware-$($config.CompanyName)" -ErrorAction SilentlyContinue
    if (-not $existingMal) {
        New-MalwareFilterPolicy `
            -Name "AntiMalware-$($config.CompanyName)" `
            -Action DeleteMessage `
            -EnableInternalSenderAdminNotifications $true `
            -InternalSenderAdminAddress $config.AdminEmail `
            -ZapEnabled $true `
            -ErrorAction Stop | Out-Null

        New-MalwareFilterRule `
            -Name "AntiMalwareRule-$($config.CompanyName)" `
            -MalwareFilterPolicy "AntiMalware-$($config.CompanyName)" `
            -RecipientDomainIs $config.Domain `
            -Priority 0 | Out-Null

        Write-Log "Anti-Malware policy berhasil dibuat." "Green"
        Write-Status "Anti-Malware Policy" "OK"
    } else {
        Write-Log "Anti-Malware policy sudah ada, skip." "Yellow"
        Write-Status "Anti-Malware Policy" "SKIP" "Sudah ada"
    }
    $baselineStatus["Anti-Malware"] = "OK"
} catch {
    Write-Log "GAGAL buat Anti-Malware policy: $_" "Red"
    Write-Status "Anti-Malware Policy" "GAGAL" "$_"
    $baselineStatus["Anti-Malware"] = "GAGAL"
}

if (-not (Confirm-Continue "Anti-Spam/Malware selesai. Lanjut cek DMARC & Email Authentication?")) { exit }

# =====================================================================
# [D] EMAIL AUTHENTICATION REVIEW (DMARC / SPF / DKIM)
# =====================================================================

Write-Step "[D] Email Authentication Review (SPF / DKIM / DMARC)"

Write-Host "`nMengecek status email authentication untuk domain $($config.Domain)..." -ForegroundColor Yellow

# Cek DKIM
try {
    $dkim = Get-DkimSigningConfig -Identity $config.Domain -ErrorAction SilentlyContinue
    if ($dkim -and $dkim.Enabled) {
        Write-Status "DKIM" "OK" "Enabled"
        $baselineStatus["DKIM"] = "OK"
    } else {
        Write-Status "DKIM" "GAGAL" "Belum aktif — aktifkan di Exchange admin center → Email Authentication"
        $baselineStatus["DKIM"] = "GAGAL"
    }
} catch {
    Write-Status "DKIM" "GAGAL" "$_"
    $baselineStatus["DKIM"] = "GAGAL"
}

# Cek SPF & DMARC via DNS (nslookup)
Write-Host "`nMengecek SPF & DMARC record via DNS..." -ForegroundColor Yellow

try {
    $spfRecord = Resolve-DnsName -Name $config.Domain -Type TXT -ErrorAction SilentlyContinue |
        Where-Object { $_.Strings -match "v=spf1" }

    if ($spfRecord) {
        Write-Status "SPF" "OK" ($spfRecord.Strings -join " ")
        $baselineStatus["SPF"] = "OK"
    } else {
        Write-Status "SPF" "GAGAL" "SPF record tidak ditemukan di DNS"
        $baselineStatus["SPF"] = "GAGAL"
    }
} catch {
    Write-Status "SPF" "GAGAL" "Tidak bisa cek DNS"
    $baselineStatus["SPF"] = "GAGAL"
}

try {
    $dmarcRecord = Resolve-DnsName -Name "_dmarc.$($config.Domain)" -Type TXT -ErrorAction SilentlyContinue |
        Where-Object { $_.Strings -match "v=DMARC1" }

    if ($dmarcRecord) {
        $policy = if ($dmarcRecord.Strings -match "p=reject") { "reject" }
                  elseif ($dmarcRecord.Strings -match "p=quarantine") { "quarantine" }
                  else { "none (monitoring only)" }
        Write-Status "DMARC" "OK" "Policy: $policy"
        $baselineStatus["DMARC"] = "OK ($policy)"
    } else {
        Write-Status "DMARC" "MANUAL" "Tambahkan TXT record: _dmarc.$($config.Domain)"
        Write-Host "    Value: v=DMARC1; p=none; rua=mailto:$($config.AdminEmail)" -ForegroundColor Yellow
        $baselineStatus["DMARC"] = "MANUAL"
    }
} catch {
    Write-Status "DMARC" "MANUAL" "Tidak bisa cek DNS — tambahkan record manual"
    $baselineStatus["DMARC"] = "MANUAL"
}

if (-not (Confirm-Continue "Email auth selesai. Lanjut Intune Security Baseline?")) { exit }

# =====================================================================
# [E] INTUNE SECURITY BASELINE (Windows)
# =====================================================================

Write-Step "[E] Intune Security Baseline — Windows 10/11"

Write-Host "`nMembuat Intune Security Baseline via Microsoft Graph..." -ForegroundColor Yellow

# Cek template Security Baseline tersedia
try {
    $templates = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/templates?`$filter=templateType eq 'securityBaseline'" `
        -ErrorAction Stop

    $windowsBaseline = $templates.value | Where-Object { $_.displayName -match "Windows 10" } | Select-Object -First 1

    if ($windowsBaseline) {
        Write-Log "Template Security Baseline ditemukan: $($windowsBaseline.displayName)" "Green"

        # Buat instance dari template
        $baselineInstance = @{
            displayName = "Security Baseline - $($config.CompanyName)"
            description = "Windows Security Baseline untuk $($config.CompanyName)"
            templateId  = $windowsBaseline.id
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId       = $config.AllStaffGroupId
                    }
                }
            )
        } | ConvertTo-Json -Depth 10

        $result = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/intents" `
            -Body $baselineInstance `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Log "Intune Security Baseline berhasil dibuat. ID: $($result.id)" "Green"
        Write-Status "Intune Security Baseline" "OK" $windowsBaseline.displayName
        $baselineStatus["Intune Security Baseline"] = "OK"
    } else {
        Write-Log "Template Security Baseline tidak ditemukan via Graph." "Yellow"
        Write-Status "Intune Security Baseline" "MANUAL" "Setup manual di Intune → Endpoint security → Security baselines"
        $baselineStatus["Intune Security Baseline"] = "MANUAL"
    }
} catch {
    Write-Log "GAGAL setup Security Baseline via Graph: $_" "Red"
    Write-Status "Intune Security Baseline" "MANUAL" "Setup manual di Intune → Endpoint security → Security baselines"
    $baselineStatus["Intune Security Baseline"] = "MANUAL"
    Write-Host @"

    Langkah manual:
    1. Buka https://intune.microsoft.com
    2. Endpoint security → Security baselines
    3. Windows 10 Security Baseline → Create profile
    4. Nama: Security Baseline - $($config.CompanyName)
    5. Assign ke group: All-Staff
"@ -ForegroundColor Cyan
}

if (-not (Confirm-Continue "Security Baseline selesai. Lanjut Attack Surface Reduction (ASR)?")) { exit }

# =====================================================================
# [F] ATTACK SURFACE REDUCTION (ASR) RULES
# =====================================================================

Write-Step "[F] Attack Surface Reduction (ASR) Rules — Mode Audit"

Write-Host "Membuat ASR policy via Intune (mode Audit — aman untuk start)..." -ForegroundColor Yellow

$asrBody = @{
    "@odata.type" = "#microsoft.graph.windows10EndpointProtectionConfiguration"
    displayName   = "ASR Rules - $($config.CompanyName)"
    description   = "Attack Surface Reduction rules — mulai dengan Audit mode"

    # ASR Rules — value: 0=Off, 1=Block, 2=Audit
    defenderAdobeReaderLaunchChildProcess                          = "auditMode"
    defenderOfficeAppsExecutableContentCreationOrLaunch           = "auditMode"
    defenderOfficeAppsLaunchChildProcess                          = "auditMode"
    defenderOfficeAppsOtherProcessInjection                       = "auditMode"
    defenderOfficeCommunicationAppsLaunchChildProcess             = "auditMode"
    defenderOfficeMacroCodeAllowWin32Imports                      = "auditMode"
    defenderPreventCredentialStealingType                         = "auditMode"
    defenderProcessCreation                                        = "auditMode"
    defenderScriptObfuscatedMacroCode                             = "auditMode"
    defenderScriptDownloadedPayloadExecution                      = "auditMode"
    defenderUntrustedExecutable                                    = "auditMode"
    defenderUntrustedUSBProcess                                    = "auditMode"
    defenderEmailContentExecution                                  = "auditMode"
    defenderAdvancedRansomewareProtectionType                      = "auditMode"
    defenderGuardMyFoldersType                                     = "auditMode"
} | ConvertTo-Json -Depth 5

try {
    $asrResult = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" `
        -Body $asrBody `
        -ContentType "application/json" `
        -ErrorAction Stop

    Write-Log "ASR Rules berhasil dibuat. ID: $($asrResult.id)" "Green"

    # Assign ke All-Staff group
    if ($config.AllStaffGroupId) {
        $assignBody = @{
            assignments = @(@{
                target = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId       = $config.AllStaffGroupId
                }
            })
        } | ConvertTo-Json -Depth 5

        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($asrResult.id)/assign" `
            -Body $assignBody -ContentType "application/json" | Out-Null
    }

    Write-Status "ASR Rules (Audit Mode)" "OK" "Review di Defender portal setelah 1-2 minggu, lalu switch ke Block"
    $baselineStatus["ASR Rules"] = "OK (Audit Mode)"
} catch {
    Write-Log "GAGAL buat ASR Rules: $_" "Red"
    Write-Status "ASR Rules" "MANUAL" "Setup manual di Intune → Endpoint security → Attack surface reduction"
    $baselineStatus["ASR Rules"] = "MANUAL"
}

if (-not (Confirm-Continue "ASR selesai. Lanjut cek Microsoft Secure Score?")) { exit }

# =====================================================================
# [G] MICROSOFT SECURE SCORE SNAPSHOT
# =====================================================================

Write-Step "[G] Microsoft Secure Score Snapshot"

try {
    $secureScore = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/security/secureScores?`$top=1" `
        -ErrorAction Stop

    if ($secureScore.value.Count -gt 0) {
        $score       = $secureScore.value[0]
        $currentScore = [math]::Round($score.currentScore, 1)
        $maxScore     = [math]::Round($score.maxScore, 1)
        $percentage   = [math]::Round(($currentScore / $maxScore) * 100, 1)

        Write-Host "`nMicrosoft Secure Score:" -ForegroundColor Green
        Write-Host "  Current Score : $currentScore / $maxScore ($percentage%)" -ForegroundColor $(if ($percentage -ge 70) { "Green" } elseif ($percentage -ge 50) { "Yellow" } else { "Red" })
        Write-Host "  Tanggal       : $($score.createdDateTime)"

        Write-Log "Secure Score: $currentScore/$maxScore ($percentage%)" "Green"
        $baselineStatus["Secure Score"] = "$currentScore/$maxScore ($percentage%)"

        # Simpan ke CSV
        "Tanggal,Score,MaxScore,Percentage" | Out-File $scoreFile
        "$($score.createdDateTime),$currentScore,$maxScore,$percentage%" | Out-File $scoreFile -Append

        Write-Host "`nTips: Target score minimal 70% untuk best practice." -ForegroundColor Cyan
        Write-Host "Cek rekomendasi lengkap di: https://security.microsoft.com/securescore" -ForegroundColor Cyan
    }
} catch {
    Write-Log "GAGAL ambil Secure Score: $_" "Yellow"
    Write-Status "Secure Score" "MANUAL" "Cek manual di https://security.microsoft.com/securescore"
    $baselineStatus["Secure Score"] = "MANUAL"
}

if (-not (Confirm-Continue "Secure Score selesai. Lanjut setup Audit Log?")) { exit }

# =====================================================================
# [H] AUDIT LOG & COMPLIANCE
# =====================================================================

Write-Step "[H] Audit Log & Compliance Settings"

# Aktifkan Unified Audit Log
try {
    $auditConfig = Get-AdminAuditLogConfig -ErrorAction SilentlyContinue
    if ($auditConfig.UnifiedAuditLogIngestionEnabled) {
        Write-Log "Unified Audit Log sudah aktif." "Yellow"
        Write-Status "Unified Audit Log" "SKIP" "Sudah aktif"
    } else {
        Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true -ErrorAction Stop
        Write-Log "Unified Audit Log berhasil diaktifkan." "Green"
        Write-Status "Unified Audit Log" "OK"
    }
    $baselineStatus["Audit Log"] = "OK"
} catch {
    Write-Log "GAGAL aktifkan Audit Log: $_" "Red"
    Write-Status "Unified Audit Log" "MANUAL" "Aktifkan di Purview compliance center → Audit"
    $baselineStatus["Audit Log"] = "MANUAL"
}

# Aktifkan Mailbox Auditing
try {
    Set-OrganizationConfig -AuditDisabled $false -ErrorAction Stop
    Write-Log "Mailbox auditing diaktifkan untuk seluruh organisasi." "Green"
    Write-Status "Mailbox Auditing" "OK"
    $baselineStatus["Mailbox Auditing"] = "OK"
} catch {
    Write-Log "GAGAL aktifkan mailbox auditing: $_" "Red"
    Write-Status "Mailbox Auditing" "GAGAL" "$_"
    $baselineStatus["Mailbox Auditing"] = "GAGAL"
}

if (-not (Confirm-Continue "Audit Log selesai. Generate laporan final?")) { exit }

# =====================================================================
# [I] LAPORAN FINAL SECURITY BASELINE
# =====================================================================

Write-Step "[I] Laporan Final Security Baseline"

$okCount     = ($baselineStatus.Values | Where-Object { $_ -like "OK*" }).Count
$manualCount = ($baselineStatus.Values | Where-Object { $_ -eq "MANUAL" }).Count
$failCount   = ($baselineStatus.Values | Where-Object { $_ -eq "GAGAL" }).Count

@"
=====================================================================
 LAPORAN SECURITY BASELINE & COMPLIANCE
 Klien     : $($config.CompanyName)
 Domain    : $($config.Domain)
 Tanggal   : $(Get-Date -Format "dd MMMM yyyy HH:mm")
 Konsultan : Dino A. Stephanus
=====================================================================

RINGKASAN HASIL:
  Total komponen  : $($baselineStatus.Count)
  Berhasil (OK)   : $okCount
  Perlu manual    : $manualCount
  Gagal           : $failCount

DETAIL STATUS PER KOMPONEN:
$(($baselineStatus.GetEnumerator() | ForEach-Object {
    "  [{0,-8}] {1}" -f $_.Value, $_.Key
}) -join "`n")

=====================================================================
CONDITIONAL ACCESS POLICIES:
  CA001 - Block Legacy Authentication   : ENABLED
  CA002 - Require MFA All Users         : ENABLED
  CA003 - Require Compliant Device      : REPORT-ONLY (aktifkan setelah semua device enrolled)
  CA004 - Block High Risk Sign-in       : ENABLED
  CA005 - Require MFA for Admin Roles   : ENABLED

DEFENDER FOR OFFICE 365:
  Anti-Phishing Policy  : Enabled (PhishThreshold Level 2)
  Safe Links Policy     : Enabled (scan URLs + internal senders)
  Safe Attachments      : Enabled (Action: Block)
  Anti-Spam Policy      : Enabled (Quarantine high-confidence)
  Anti-Malware Policy   : Enabled (DeleteMessage + admin notification)

EMAIL AUTHENTICATION:
  SPF   : $($baselineStatus["SPF"])
  DKIM  : $($baselineStatus["DKIM"])
  DMARC : $($baselineStatus["DMARC"])

INTUNE & ENDPOINT:
  Security Baseline : $($baselineStatus["Intune Security Baseline"])
  ASR Rules         : $($baselineStatus["ASR Rules"])
  Audit Log         : $($baselineStatus["Audit Log"])
  Mailbox Auditing  : $($baselineStatus["Mailbox Auditing"])

TINDAK LANJUT YANG DIPERLUKAN:
  1. Tambahkan DMARC TXT record ke DNS jika belum ada
     _dmarc.$($config.Domain) → v=DMARC1; p=none; rua=mailto:$($config.AdminEmail)
  2. Aktifkan CA003 ke Enforced setelah semua device enrolled di Intune
  3. Review ASR Audit report setelah 1-2 minggu di Defender portal
     Lalu switch ASR ke mode Block per rule yang tidak ada false positive
  4. Review Secure Score di https://security.microsoft.com/securescore
     Implementasikan rekomendasi quick-win yang tersedia
  5. Set DMARC policy ke p=quarantine setelah 2-4 minggu monitoring

FILE OUTPUT:
  - security-log.txt              : Log lengkap proses
  - security-baseline-report.txt  : Laporan ini
  - secure-score-snapshot.csv     : Snapshot Secure Score awal

=====================================================================
"@ | Tee-Object -FilePath $reportFile

Write-Log "Laporan tersimpan di: $reportFile"

# Disconnect
try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
try { Disconnect-MgGraph } catch {}

Write-Host @"

=====================================================================
 SECURITY BASELINE SETUP SELESAI!
 Output: $($config.OutputFolder)

 Komponen OK     : $okCount
 Perlu manual    : $manualCount
 Gagal           : $failCount

 Langkah prioritas berikutnya:
 1. Tambah DMARC DNS record (jika belum ada)
 2. Aktifkan CA003 setelah semua device enrolled
 3. Review ASR di Defender portal (2 minggu)
 4. Cek Secure Score & implementasi quick-win
=====================================================================
"@ -ForegroundColor Green
