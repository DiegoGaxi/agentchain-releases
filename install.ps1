#Requires -Version 5.1
<#
    AgentChain one-command installer (Windows)

        irm https://get.agentchain.app/install.ps1 | iex

    Downloads the latest Windows release from GitHub, verifies its SHA-256
    checksum against the published SHA256SUMS file, then runs the NSIS
    installer.

    Asset naming contract (must match the release builder exactly):
        Windows: AgentChain-Setup-${version}.exe
#>

$ErrorActionPreference = 'Stop'

# ── Configuration ───────────────────────────────────────────────────────────
$Repo   = 'DiegoGaxi/agentchain-releases'
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

# ── Pretty output ───────────────────────────────────────────────────────────
function Write-Info  { param([string]$m) Write-Host "$([char]0x2192) $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "$([char]0x2713) $m" -ForegroundColor Green }
function Write-Warn  { param([string]$m) Write-Host "! $m" -ForegroundColor Yellow }
function Die         { param([string]$m) Write-Host "x $m" -ForegroundColor Red; exit 1 }

function Show-Banner {
    Write-Host ""
    Write-Host "  AgentChain" -ForegroundColor Cyan -NoNewline
    Write-Host " — one-command installer" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Platform guard ──────────────────────────────────────────────────────────
function Assert-Windows {
    $isWin = $true
    # On PowerShell 6+ $IsWindows exists; on 5.1 it doesn't (always Windows).
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        $isWin = $IsWindows
    }
    if (-not $isWin) {
        Die "This installer is for Windows. On Linux/macOS use: curl -fsSL https://get.agentchain.app | bash"
    }
}

# ── GitHub release metadata ─────────────────────────────────────────────────
function Get-LatestRelease {
    Write-Info "Querying latest release from $Repo ..."
    $headers = @{
        'User-Agent' = 'agentchain-installer'
        'Accept'     = 'application/vnd.github+json'
    }
    try {
        return Invoke-RestMethod -Uri $ApiUrl -Headers $headers -UseBasicParsing
    } catch {
        Die "Could not reach the GitHub release API: $($_.Exception.Message)"
    }
}

# Find an asset by exact name; returns its browser_download_url (or $null).
function Get-AssetUrl {
    param($Release, [string]$Name)
    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($asset) { return $asset.browser_download_url }
    return $null
}

# ── Download helper ─────────────────────────────────────────────────────────
function Get-File {
    param([string]$Url, [string]$Dest)
    Write-Info "Downloading $(Split-Path $Dest -Leaf) ..."
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # huge speed-up for Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing `
            -Headers @{ 'User-Agent' = 'agentchain-installer' }
    } catch {
        Die "Download failed: $($_.Exception.Message)"
    } finally {
        $ProgressPreference = $oldPref
    }
}

# ── Checksum verification ───────────────────────────────────────────────────
# Returns 'ok', 'mismatch', or 'skip'.
function Test-Checksum {
    param([string]$File, [string]$Name, [string]$SumsFile)

    if (-not (Test-Path $SumsFile)) { return 'skip' }

    $expected = $null
    foreach ($line in Get-Content -LiteralPath $SumsFile) {
        # Format: "<sha256>  <name>"  (an optional '*' precedes binary names)
        if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
            if ($Matches[2] -eq $Name) { $expected = $Matches[1].ToLower(); break }
        }
    }
    if (-not $expected) { return 'skip' }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLower()
    if ($actual -eq $expected) { return 'ok' }
    return 'mismatch'
}

# ── Main ────────────────────────────────────────────────────────────────────
Show-Banner
Assert-Windows

$release = Get-LatestRelease
$version = $release.tag_name
if ([string]::IsNullOrWhiteSpace($version)) {
    Die "Could not determine the latest release tag."
}
# The release TAG is v-prefixed (e.g. v2.0.9) but the asset name uses the bare
# version (AgentChain-Setup-2.0.9.exe). Strip the leading 'v' so the lookup matches.
$version = $version -replace '^v', ''
Write-Info "Latest release: v$version"

$setupName = "AgentChain-Setup-$version.exe"
$setupUrl  = Get-AssetUrl -Release $release -Name $setupName
if (-not $setupUrl) {
    Die "No installer named '$setupName' in release $version. The Windows build may be missing from this release."
}

$tmp     = Join-Path $env:TEMP ("agentchain-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$setupPath = Join-Path $tmp $setupName

try {
    Get-File -Url $setupUrl -Dest $setupPath

    # Verify against SHA256SUMS when available (best-effort).
    $sumsUrl = Get-AssetUrl -Release $release -Name 'SHA256SUMS-win.txt'
    if ($sumsUrl) {
        $sumsPath = Join-Path $tmp 'SHA256SUMS'
        try {
            Get-File -Url $sumsUrl -Dest $sumsPath
            switch (Test-Checksum -File $setupPath -Name $setupName -SumsFile $sumsPath) {
                'ok'       { Write-Ok   "Checksum verified." }
                'mismatch' { Die "Checksum MISMATCH for $setupName. Aborting for safety." }
                'skip'     { Write-Warn "Could not verify checksum (no matching entry). Continuing." }
            }
        } catch {
            Write-Warn "Could not download/verify SHA256SUMS. Continuing."
        }
    } else {
        Write-Warn "Release has no SHA256SUMS asset. Skipping verification."
    }

    Write-Host ""
    Write-Warn "Note: this build is unsigned. Windows SmartScreen may warn you."
    Write-Warn "If it does: click 'More info' -> 'Run anyway'."
    Write-Host ""

    Write-Info "Launching the AgentChain installer ..."
    # NSIS installer. /S would run silently; we run interactively so the user
    # can choose the install location and dismiss any SmartScreen prompt.
    $proc = Start-Process -FilePath $setupPath -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-Warn "Installer exited with code $($proc.ExitCode)."
    } else {
        Write-Ok "AgentChain $version installed!"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
