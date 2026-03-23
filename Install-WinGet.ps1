#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs WinGet (App Installer) on Windows Server 2022.
.DESCRIPTION
    Fetches the latest release from GitHub and installs all dependencies.
    Idempotent — skips components that are already installed.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Helper Functions ---

function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [+] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [-] $Message" -ForegroundColor Red
}

function Install-AppxIfMissing {
    param(
        [string]$PackageName,
        [string]$Uri,
        [string]$OutFile
    )

    $existing = Get-AppxPackage -Name "*$PackageName*" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-OK "$PackageName is already installed (v$($existing.Version)), skipping."
        return
    }

    Write-Step "Downloading $PackageName..."
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    Write-Step "Installing $PackageName..."
    Add-AppxPackage -Path $OutFile
    Write-OK "$PackageName installed."
}

#endregion

#region --- Prerequisites ---

Write-Step "Checking prerequisites..."

# OS check
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 1) {
    Write-Host "    [!] Workstation OS detected. This script is designed for Server, continuing anyway..." -ForegroundColor Yellow
}

# Desktop Experience check (required for App-V / Appx)
$desktopExp = Get-WindowsFeature -Name Server-Gui-Shell -ErrorAction SilentlyContinue
if ($desktopExp -and $desktopExp.InstallState -ne 'Installed') {
    throw "Desktop Experience is not installed. WinGet requires this feature."
}

Write-OK "Prerequisites OK."

#endregion

#region --- Check if WinGet is Already Installed ---

Write-Step "Checking for existing WinGet installation..."

$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    $ver = & winget --version 2>&1
    Write-OK "WinGet is already installed: $ver"
    exit 0
}

#endregion

#region --- Fetch Latest Release from GitHub ---

Write-Step "Fetching latest WinGet release from GitHub..."

$releaseApi = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
$headers    = @{ 'User-Agent' = 'WinGet-Installer-Script' }
$release    = Invoke-RestMethod -Uri $releaseApi -Headers $headers

$appxAsset    = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
$licenseAsset = $release.assets | Where-Object { $_.name -like '*License*.xml'  } | Select-Object -First 1

if (-not $appxAsset -or -not $licenseAsset) {
    throw "Release assets not found. Check the GitHub API response."
}

Write-OK "Target version: $($release.tag_name)"

#endregion

#region --- Temporary Directory ---

$tempDir = Join-Path $env:TEMP 'WinGetInstall'
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

#endregion

#region --- Dependencies ---

Install-AppxIfMissing `
    -PackageName 'Microsoft.VCLibs.140.00.UWPDesktop' `
    -Uri         'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' `
    -OutFile     (Join-Path $tempDir 'VCLibs.appx')

# UI.Xaml — dynamically resolve version from release assets
$xamlAsset = $release.assets | Where-Object { $_.name -like 'Microsoft.UI.Xaml*.appx' } | Select-Object -First 1
if ($xamlAsset) {
    Install-AppxIfMissing `
        -PackageName 'Microsoft.UI.Xaml.2' `
        -Uri         $xamlAsset.browser_download_url `
        -OutFile     (Join-Path $tempDir 'UIXaml.appx')
} else {
    # Fallback: known static URL
    Write-Host "    [!] UI.Xaml release asset not found, using fallback URL." -ForegroundColor Yellow
    Install-AppxIfMissing `
        -PackageName 'Microsoft.UI.Xaml.2' `
        -Uri         'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx' `
        -OutFile     (Join-Path $tempDir 'UIXaml.appx')
}

#endregion

#region --- WinGet Installation ---

Write-Step "Downloading WinGet package ($($appxAsset.name))..."
$appxPath    = Join-Path $tempDir $appxAsset.name
$licensePath = Join-Path $tempDir $licenseAsset.name

Invoke-WebRequest -Uri $appxAsset.browser_download_url    -OutFile $appxPath    -UseBasicParsing
Invoke-WebRequest -Uri $licenseAsset.browser_download_url -OutFile $licensePath -UseBasicParsing

Write-Step "Installing WinGet (Add-AppxProvisionedPackage)..."
Add-AppxProvisionedPackage `
    -Online      `
    -PackagePath $appxPath `
    -LicensePath $licensePath | Out-Null

Write-OK "WinGet installed successfully!"

#endregion

#region --- Verification ---

Write-Step "Verifying installation..."

# PATH is updated on new sessions; add manually to use winget in the current session
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$wingetPath   = "$localAppData\Microsoft\WindowsApps"
if ($env:PATH -notlike "*$wingetPath*") {
    $env:PATH += ";$wingetPath"
}

try {
    $verOutput = & winget --version 2>&1
    Write-OK "Verification successful: $verOutput"
} catch {
    Write-Host "`n[!] winget command not found yet." -ForegroundColor Yellow
    Write-Host "    Open a new PowerShell/terminal session and run 'winget --version'." -ForegroundColor Yellow
}

#endregion

#region --- Cleanup ---

Write-Step "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "Cleanup complete."

Write-Host "`nInstallation complete! You can now use the 'winget' command.`n" -ForegroundColor Green
