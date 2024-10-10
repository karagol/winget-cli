Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appx
Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx -OutFile Microsoft.UI.Xaml.2.8.x64.appx
Invoke-WebRequest -Uri https://github.com/microsoft/winget-cli/releases/download/v1.8.1911/76fba573f02545629706ab99170237bc_License1.xml -OutFile 76fba573f02545629706ab99170237bc_License1.xml
Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
Add-AppxPackage Microsoft.UI.Xaml.2.8.x64.appx
Add-AppxProvisionedPackage -Online -PackagePath Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appx -LicensePath 76fba573f02545629706ab99170237bc_License1.xml
