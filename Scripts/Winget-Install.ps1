<#
.SYNOPSIS
Installs or updates winget with complete checks and interactive interface

.DESCRIPTION
Included features:
- Existing installation verification at 3 levels
- Version comparison
- Secure download with hash verification
- Colored and interactive interface
- Reinstall/update options
- Automatic cleanup of temporary files

.EXAMPLE
PS> .\Install-Winget.ps1
PS> .\Install-Winget.ps1 -EnableDebug -Force
#>

# Configurações do módulo
[CmdletBinding()]
param(
    [switch]$EnableDebug,
    [switch]$Force
)

# Configurações globais
$script:Config = @{
    Package = @{
        Version = "1.10.40"
        Hash    = "686842FDFD1E28A239C7242815374D8B52BA1EBCB5D85EB38603C524F70D8F95"
        Url     = "https://github.com/microsoft/winget-cli/releases/download/v1.10.40-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    }
    Paths = @{
        Temp   = Join-Path $env:TEMP "WingetInstall"
        Bundle = Join-Path (Join-Path $env:TEMP "WingetInstall") "Microsoft.DesktopAppInstaller.msixbundle"
    }
    UI = @{
        Colors = @{
            Success = "Green"
            Error   = "Red"
            Warning = "Yellow"
            Info    = "Cyan"
            Debug   = "Gray"
            Banner  = "Magenta"
            Progress = "Blue"
        }
        Symbols = @{
            Success = "✓"
            Error   = "✗"
            Warning = "⚠"
            Info    = "ℹ"
            Arrow   = "→"
            Star    = "★"
        }
    }
    Requirements = @(
        @{
            Test = { [System.Environment]::OSVersion.Version.Major -ge 10 }
            Message = "Windows 10 or higher"
        },
        @{
            Test = { [Environment]::Is64BitOperatingSystem }
            Message = "64-bit System"
        },
        @{
            Test = { $PSVersionTable.PSVersion.Major -ge 5 }
            Message = "PowerShell 5+"
        },
        @{
            Test = {
                try {
                    $appxProvider = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
                    return $null -ne $appxProvider
                } catch {
                    return $false
                }
            }
            Message = "MSIX/AppX Package Support"
        },
        @{
            Test = {
                try {
                    $response = Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 10
                    return $response.StatusCode -eq 200
                } catch {
                    return $false
                }
            }
            Message = "Internet Connection"
        },
        @{
            Test = { 
                $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = New-Object Security.Principal.WindowsPrincipal($identity)
                if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    try {
                        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
                        exit
                    } catch {
                        return $false
                    }
                }
                return $true
            }
            Message = "Administrator Privileges"
        }
    )
}

# Inicialização
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
if ($EnableDebug) { 
    $DebugPreference = "Continue"
    $VerbosePreference = "Continue"
}

# Funções de UI
function Write-LogMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("Success", "Error", "Warning", "Info", "Debug")]
        [string]$Type = "Info",
        [switch]$NoNewline
    )
    
    $symbol = $script:Config.UI.Symbols[$Type]
    $color = $script:Config.UI.Colors[$Type]
    
    if ($NoNewline) {
        Write-Host "$symbol $Message" -ForegroundColor $color -NoNewline
    } else {
        Write-Host "`n$symbol $Message" -ForegroundColor $color
    }
}

function Show-InstallBanner {
    Clear-Host
    $bannerColor = $script:Config.UI.Colors.Banner
    Write-Host @"
    
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║  ██╗    ██╗██╗███╗   ██╗ ██████╗ ███████╗████████╗       ║
    ║  ██║    ██║██║████╗  ██║██╔════╝ ██╔════╝╚══██╔══╝       ║
    ║  ██║ █╗ ██║██║██╔██╗ ██║██║  ███╗█████╗     ██║          ║
    ║  ██║███╗██║██║██║╚██╗██║██║   ██║██╔══╝     ██║          ║
    ║  ╚███╔███╔╝██║██║ ╚████║╚██████╔╝███████╗   ██║          ║
    ║   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝   ╚═╝          ║
    ║                                                          ║
    ║          🚀 Winget Automated Installer 🚀                ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor $bannerColor

    Start-Sleep -Milliseconds 500
}


# Funções de Validação
function Test-SystemRequirements {
    Write-LogMessage "Starting checks..." -Type Info
    
    foreach ($req in $script:Config.Requirements) {
        Write-Host "$($script:Config.UI.Symbols.Arrow) Checking $($req.Message)... " -NoNewline
        if (& $req.Test) {
            Write-Host $script:Config.UI.Symbols.Success -ForegroundColor $script:Config.UI.Colors.Success
        } else {
            Write-Host $script:Config.UI.Symbols.Error -ForegroundColor $script:Config.UI.Colors.Error
            throw "Requirement not met: $($req.Message)"
        }
        Start-Sleep -Milliseconds 300
    }

    Write-LogMessage "All requirements met!" -Type Success
}

function Test-WingetInstallation {
    try {
        $isInstalled = $false
        $version = $null

        # Verificação via comando
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $isInstalled = $true
            $versionOutput = winget --version 2>&1
            if ($versionOutput -match '(\d+\.\d+\.\d+)') {
                $version = [version]$Matches[1]
            }
        }

        # Verificação via AppxPackage
        if (-not $isInstalled) {
            $appx = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
            if ($appx) {
                $isInstalled = $true
                $version = [version]$appx.Version
            }
        }

        # Verificação via Registro
        if (-not $isInstalled) {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft.DesktopAppInstaller"
            if (Test-Path $regPath) {
                $isInstalled = $true
            }
        }

        return @{
            IsInstalled = $isInstalled
            Version = $version
        }
    }
    catch {
        Write-LogMessage "Erro ao verificar instalação: $_" -Type Debug
        return @{
            IsInstalled = $false
            Version = $null
        }
    }
}

# Funções de Instalação
function Get-WingetPackage {
    param (
        [string]$Url = $script:Config.Package.Url,
        [string]$Destination = $script:Config.Paths.Bundle
    )

    try {
        Write-LogMessage "Starting package download..." -Type Info
        
        if (-not (Test-Path $script:Config.Paths.Temp)) {
            New-Item -Path $script:Config.Paths.Temp -ItemType Directory -Force | Out-Null
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        
        Write-LogMessage "Download completed in $($stopwatch.Elapsed.ToString())" -Type Success
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Download error: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Test-PackageHash {
    param (
        [string]$FilePath = $script:Config.Paths.Bundle,
        [string]$ExpectedHash = $script:Config.Package.Hash
    )

    Write-LogMessage "Checking package integrity..." -Type Info
    
    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedHash) {
            throw "Invalid hash! Expected: $ExpectedHash`nGot: $actualHash"
        }
        Write-LogMessage "Package integrity verified" -Type Success
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Integrity check failed!" -Type Error
        throw
    }
}

function Install-WingetPackage {
    param (
        [string]$BundlePath = $script:Config.Paths.Bundle
    )

    try {
        Write-LogMessage "Starting installation process..." -Type Info
        
        $steps = @("Preparing", "Extracting", "Configuring", "Finishing")
        $totalSteps = $steps.Count
        
        foreach ($i in 0..($totalSteps-1)) {
            $step = $steps[$i]
            $percent = [math]::Round(($i + 1) / $totalSteps * 100)
            Write-Progress -Activity "Installing Winget" -Status "$step..." -PercentComplete $percent
            Start-Sleep -Milliseconds 800
        }

        Add-AppxPackage -Path $BundlePath -ErrorAction Stop
        Write-Progress -Activity "Installing Winget" -Completed
        
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Installation error: $($_.Exception.Message)" -Type Error
        throw
    }
}

# Função Principal
function Start-WingetInstallation {
    try {
        Show-InstallBanner
        
        # Verificação inicial
        $currentInstall = Test-WingetInstallation
        $separator = "─" * 70
        
        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Info
        Write-LogMessage "Winget Status" -Type Info
        
        if ($currentInstall.IsInstalled) {
            Write-Host "  $($script:Config.UI.Symbols.Info) Installed Version: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "v$($currentInstall.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "  $($script:Config.UI.Symbols.Info) Script Version: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "v$($script:Config.Package.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Info

            if (-not $Force) {
                Write-Host "`n  Choose an option:" -ForegroundColor $script:Config.UI.Colors.Info
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (R) Reinstall" -ForegroundColor $script:Config.UI.Colors.Warning
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (U) Update" -ForegroundColor $script:Config.UI.Colors.Success
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (Q) Quit" -ForegroundColor $script:Config.UI.Colors.Error
                $choice = Read-Host "`n  Enter your choice"
                
                switch ($choice.ToUpper()) {
                    'R' { 
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Warning
                        Write-LogMessage "Starting reinstallation..." -Type Warning 
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Warning
                    }
                    'U' { 
                        if ($currentInstall.Version -ge [version]$script:Config.Package.Version) {
                            Write-LogMessage "Installed version is already up to date!" -Type Success
                            return
                        }
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Success
                        Write-LogMessage "Starting update..." -Type Info
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Warning
                    }
                    default { 
                        Write-LogMessage "Operation cancelled by user." -Type Info
                        return
                    }
                }
            }
        } else {
            Write-Host "  $($script:Config.UI.Symbols.Info) Installed Version: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "Not installed" -ForegroundColor $script:Config.UI.Colors.Error
            Write-Host "  $($script:Config.UI.Symbols.Info) Script Version: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "v$($script:Config.Package.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Info

            if (-not $Force) {
                Write-Host "`n  Choose an option:" -ForegroundColor $script:Config.UI.Colors.Info
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (I) Install" -ForegroundColor $script:Config.UI.Colors.Success
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (Q) Quit" -ForegroundColor $script:Config.UI.Colors.Error
                $choice = Read-Host "`n  Enter your choice"
                
                switch ($choice.ToUpper()) {
                    'I' { 
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Success
                        Write-LogMessage "Starting installation..." -Type Info
                        Write-Host "$separator`n" -ForegroundColor $script:Config.UI.Colors.Success
                    }
                    default { 
                        Write-LogMessage "Operation cancelled by user." -Type Info
                        return
                    }
                }
            }
        }

        Test-SystemRequirements
        Get-WingetPackage
        Test-PackageHash
        Install-WingetPackage

        # Verificação final
        $finalInstall = Test-WingetInstallation
        if ($finalInstall.IsInstalled) {
            Write-LogMessage "Installation completed successfully! ($($finalInstall.Version))" -Type Success
        }
        else {
            throw "Installation apparently successful, but winget not found!"
        }
    }
    catch {
        Write-LogMessage "Critical error: $($_.Exception.Message)" -Type Error
        throw
    }
    finally {
        if (Test-Path $script:Config.Paths.Temp) {
            Remove-Item $script:Config.Paths.Temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Execução
Start-WingetInstallation

# Pausa final de 10 segundos
Write-LogMessage "Waiting 10 seconds before closing..." -Type Info
Start-Sleep -Seconds 10