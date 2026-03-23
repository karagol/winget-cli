# WinGet Installer for Windows Server 2022

A robust, idempotent PowerShell script that automates the installation of **WinGet** (Windows Package Manager / App Installer) on **Windows Server 2022**, including all required dependencies.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Usage](#usage)
- [What the Script Does](#what-the-script-does)
  - [1. Prerequisites Check](#1-prerequisites-check)
  - [2. Existing Installation Detection](#2-existing-installation-detection)
  - [3. Latest Release Resolution](#3-latest-release-resolution)
  - [4. Dependency Installation](#4-dependency-installation)
  - [5. WinGet Installation](#5-winget-installation)
  - [6. Verification](#6-verification)
  - [7. Cleanup](#7-cleanup)
- [Helper Functions](#helper-functions)
- [Error Handling](#error-handling)
- [Idempotency](#idempotency)
- [Notes & Limitations](#notes--limitations)

---

## Overview

WinGet is not included by default on Windows Server 2022. Installing it manually requires downloading multiple interdependent `.appx` / `.msixbundle` packages in the correct order, along with a license file. This script fully automates that process — dynamically resolving the latest available version from GitHub, handling all dependencies, and verifying the result.

---

## Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows Server 2022 (also tolerates Windows 10/11 workstation) |
| **PowerShell** | 5.1 or later |
| **Privileges** | Must be run as **Administrator** (`#Requires -RunAsAdministrator`) |
| **Desktop Experience** | The **Server-Gui-Shell** Windows feature must be installed |
| **Internet Access** | Requires outbound HTTPS to `api.github.com`, `github.com`, and `aka.ms` |

---

## Usage

```powershell
# Run directly in an elevated PowerShell session
.\Install-WinGet.ps1
```

Or allow execution if needed:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Install-WinGet.ps1
```

---

## What the Script Does

### 1. Prerequisites Check

Before attempting any downloads or installations, the script validates the environment:

- **OS Type Detection** — Uses `Get-CimInstance Win32_OperatingSystem` to read the `ProductType` property. A value of `1` indicates a Workstation OS; the script logs a warning but continues. This is informational only, as the script is primarily designed and tested for Server editions.

- **Desktop Experience Feature Check** — Calls `Get-WindowsFeature -Name Server-Gui-Shell` to confirm that the Desktop Experience feature is installed. WinGet relies on UWP/AppX infrastructure that is only available when this feature is present. If it is missing, the script throws a terminating error immediately rather than proceeding to a guaranteed failure later.

---

### 2. Existing Installation Detection

The script checks whether `winget` is already available in the current session's `PATH` using `Get-Command winget`. If found, it prints the installed version and **exits immediately** with code `0`. This makes the script safe to run repeatedly — for example, in a provisioning pipeline or as part of a DSC/baseline enforcement run — without causing unnecessary re-installations or errors.

---

### 3. Latest Release Resolution

Instead of hardcoding a specific WinGet version, the script queries the **GitHub Releases API**:

```
GET https://api.github.com/repos/microsoft/winget-cli/releases/latest
```

A `User-Agent` header is included as required by the GitHub API. The response is parsed with `Invoke-RestMethod`, which deserializes the JSON payload automatically. From the `assets` array, the script extracts:

- **`.msixbundle`** — the main WinGet application package
- **`*License*.xml`** — the license file required for provisioned (system-wide) installation

This approach ensures the script always installs the most recent stable release without requiring manual version updates.

---

### 4. Dependency Installation

WinGet has two mandatory runtime dependencies that must be installed before the main package. Both are handled by the `Install-AppxIfMissing` helper function (see [Helper Functions](#helper-functions)):

#### a) Microsoft Visual C++ Runtime Libraries (VCLibs)

- **Package name:** `Microsoft.VCLibs.140.00.UWPDesktop`
- **Source:** `https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx`
- Required for UWP app execution on Server SKUs where these libraries are not pre-installed.

#### b) Microsoft UI XAML (WinUI)

- **Package name:** `Microsoft.UI.Xaml.2`
- **Primary source:** Dynamically resolved from the WinGet release's own asset list (looks for `Microsoft.UI.Xaml*.appx`), ensuring version compatibility with the WinGet build being installed.
- **Fallback source:** If the asset is not found in the release (e.g., API change), falls back to the known static URL for `v2.8.6`.
- Provides the XAML rendering layer used by the WinGet UI components.

Both dependencies are downloaded to an isolated temporary directory (`$env:TEMP\WinGetInstall`) and installed via `Add-AppxPackage`.

---

### 5. WinGet Installation

With dependencies in place, the script proceeds to install WinGet itself:

1. Downloads the `.msixbundle` and license `.xml` from the URLs resolved in step 3.
2. Calls `Add-AppxProvisionedPackage -Online` instead of `Add-AppxPackage`. This is the critical distinction for Server environments — provisioned packages are registered system-wide and made available to all users, not just the current session. The `-LicensePath` parameter is required when using this method.

---

### 6. Verification

After installation, the script attempts to invoke `winget --version` to confirm the binary is functional. Because Windows only updates `PATH` for new sessions, the script first manually appends the WindowsApps directory to `$env:PATH` for the current session:

```powershell
$localAppData\Microsoft\WindowsApps
```

If `winget --version` succeeds, the version string is printed. If it fails (e.g., due to session state or Store registration delay), a non-fatal warning is shown instructing the user to open a new terminal and verify manually.

---

### 7. Cleanup

The temporary directory (`$env:TEMP\WinGetInstall`) and all downloaded files are removed using `Remove-Item -Recurse -Force`. Errors during cleanup are suppressed (`-ErrorAction SilentlyContinue`) so that a cleanup failure does not obscure a successful installation.

---

## Helper Functions

| Function | Purpose |
|---|---|
| `Write-Step` | Prints a cyan `[*]` prefixed message to indicate a major step in progress |
| `Write-OK` | Prints a green `[+]` prefixed message to indicate success |
| `Write-Fail` | Prints a red `[-]` prefixed message to indicate a failure |
| `Install-AppxIfMissing` | Checks if a package is already installed via `Get-AppxPackage`; skips download and installation if found, otherwise downloads from the given URI and installs with `Add-AppxPackage` |

---

## Error Handling

The script sets `$ErrorActionPreference = 'Stop'` globally, which causes all non-terminating errors to be promoted to terminating errors. This ensures that any unexpected failure — a failed download, a missing asset, a package installation error — immediately halts execution rather than silently continuing to the next step in a broken state.

---

## Idempotency

The script is designed to be safely re-run at any time:

- If `winget` is already in `PATH` → exits immediately.
- If a dependency package is already installed → `Install-AppxIfMissing` skips it.
- Temporary files are cleaned up on every run.

This makes the script suitable for use in automated provisioning pipelines, Group Policy startup scripts, or image build processes where the same script may execute multiple times.

---

## Notes & Limitations

- **Store registration delay:** On some systems, the AppX package registration may complete asynchronously. If `winget` is not immediately available after the script finishes, opening a new PowerShell session resolves this.
- **Air-gapped environments:** The script requires internet access. For offline deployments, pre-download the required assets and adapt the URI parameters accordingly.
- **ARM64:** The script targets `x64` architecture. For ARM64 Server environments, the VCLibs and UI.Xaml URLs would need to be adjusted.
- **GitHub API rate limiting:** Unauthenticated requests to the GitHub API are limited to 60 requests/hour per IP. In environments with many concurrent provisioning jobs, consider caching the release metadata or authenticating with a token.
