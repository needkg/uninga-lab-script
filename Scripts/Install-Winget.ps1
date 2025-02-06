<#
.SYNOPSIS
Instala ou atualiza o winget com verificações completas e interface interativa

.DESCRIPTION
Funcionalidades incluídas:
- Verificação de instalação existente em 3 níveis
- Comparação de versões
- Download seguro com verificação de hash
- Interface colorida e interativa
- Opções de reinstalação/atualização
- Limpeza automática de arquivos temporários

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
        Version = "1.9.25200"
        Hash    = "46D46BB5DEACEF0FD8AC30A223072B45AC2D5D5262D1591F2C08FB6EE15E4B22"
        Url     = "https://github.com/microsoft/winget-cli/releases/download/v1.9.25200/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
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
            Message = "Windows 10 ou superior"
        }
        @{
            Test = { [Environment]::Is64BitOperatingSystem }
            Message = "Sistema 64 bits"
        }
        @{
            Test = { $PSVersionTable.PSVersion.Major -ge 5 }
            Message = "PowerShell 5+"
        }
        @{
            Test = {
                try {
                    $response = Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 10
                    return $response.StatusCode -eq 200
                } catch {
                    return $false
                }
            }
            Message = "Conexão com a Internet"
        }
        @{
            Test = {
                try {
                    $appxProvider = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue
                    return $null -ne $appxProvider
                } catch {
                    return $false
                }
            }
            Message = "Suporte a pacotes MSIX/AppX"
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
    ║          🚀 Instalador Automatizado Winget 🚀            ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor $bannerColor

    Start-Sleep -Milliseconds 500
}


# Funções de Validação
function Test-SystemRequirements {
    Write-LogMessage "Iniciando verificações..." -Type Info
    
    foreach ($req in $script:Config.Requirements) {
        Write-Host "$($script:Config.UI.Symbols.Arrow) Verificando $($req.Message)... " -NoNewline
        if (& $req.Test) {
            Write-Host $script:Config.UI.Symbols.Success -ForegroundColor $script:Config.UI.Colors.Success
        } else {
            Write-Host $script:Config.UI.Symbols.Error -ForegroundColor $script:Config.UI.Colors.Error
            throw "Requisito não atendido: $($req.Message)"
        }
        Start-Sleep -Milliseconds 300
    }

    Write-LogMessage "Todos os requisitos atendidos!" -Type Success
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
        Write-LogMessage "Iniciando download do pacote Winget..." -Type Info
        
        if (-not (Test-Path $script:Config.Paths.Temp)) {
            New-Item -Path $script:Config.Paths.Temp -ItemType Directory -Force | Out-Null
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        
        Write-LogMessage "Download concluído em $($stopwatch.Elapsed.ToString())" -Type Success
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Erro no download: $($_.Exception.Message)" -Type Error
        throw
    }
}

function Test-PackageHash {
    param (
        [string]$FilePath = $script:Config.Paths.Bundle,
        [string]$ExpectedHash = $script:Config.Package.Hash
    )

    Write-LogMessage "Verificando integridade do pacote..." -Type Info
    
    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedHash) {
            throw "Hash inválido! Esperado: $ExpectedHash`nObtido: $actualHash"
        }
        Write-LogMessage "Integridade do pacote verificada" -Type Success
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Falha na verificação de integridade!" -Type Error
        throw
    }
}

function Install-WingetPackage {
    param (
        [string]$BundlePath = $script:Config.Paths.Bundle
    )

    try {
        Write-LogMessage "Iniciando processo de instalação..." -Type Info
        
        $steps = @("Preparando", "Extraindo", "Configurando", "Finalizando")
        $totalSteps = $steps.Count
        
        foreach ($i in 0..($totalSteps-1)) {
            $step = $steps[$i]
            $percent = [math]::Round(($i + 1) / $totalSteps * 100)
            Write-Progress -Activity "Instalando Winget" -Status "$step..." -PercentComplete $percent
            Start-Sleep -Milliseconds 800
        }

        Add-AppxPackage -Path $BundlePath -ErrorAction Stop
        Write-Progress -Activity "Instalando Winget" -Completed
        
        return $true | Out-Null
    }
    catch {
        Write-LogMessage "Erro na instalação: $($_.Exception.Message)" -Type Error
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
        Write-LogMessage "Status do Winget" -Type Info
        
        if ($currentInstall.IsInstalled) {
            Write-Host "  $($script:Config.UI.Symbols.Info) Versão Instalada: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "$($currentInstall.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "  $($script:Config.UI.Symbols.Info) Versão do Script: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "v$($script:Config.Package.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Info

            if (-not $Force) {
                Write-Host "`n  Escolha uma opção:" -ForegroundColor $script:Config.UI.Colors.Info
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (R) Reinstalar" -ForegroundColor $script:Config.UI.Colors.Warning
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (A) Atualizar" -ForegroundColor $script:Config.UI.Colors.Success
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (S) Sair" -ForegroundColor $script:Config.UI.Colors.Error
                $choice = Read-Host "`n  Digite sua escolha"
                
                switch ($choice.ToUpper()) {
                    'R' { 
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Warning
                        Write-LogMessage "Iniciando reinstalação..." -Type Warning 
                        Write-Host "$separator`n" -ForegroundColor $script:Config.UI.Colors.Warning
                    }
                    'A' { 
                        if ($currentInstall.Version -ge [version]$script:Config.Package.Version) {
                            Write-LogMessage "Versão instalada já é a mais recente!" -Type Success
                            return
                        }
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Success
                        Write-LogMessage "Iniciando atualização..." -Type Info
                        Write-Host "$separator`n" -ForegroundColor $script:Config.UI.Colors.Success
                    }
                    default { 
                        Write-LogMessage "Operação cancelada pelo usuário." -Type Info
                        return
                    }
                }
            }
        } else {
            Write-Host "  $($script:Config.UI.Symbols.Info) Versão Instalada: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "Não instalado" -ForegroundColor $script:Config.UI.Colors.Error
            Write-Host "  $($script:Config.UI.Symbols.Info) Versão do Script: " -NoNewline -ForegroundColor $script:Config.UI.Colors.Info
            Write-Host "v$($script:Config.Package.Version)" -ForegroundColor $script:Config.UI.Colors.Success
            Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Info

            if (-not $Force) {
                Write-Host "`n  Escolha uma opção:" -ForegroundColor $script:Config.UI.Colors.Info
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (I) Instalar" -ForegroundColor $script:Config.UI.Colors.Success
                Write-Host "  $($script:Config.UI.Symbols.Arrow) (S) Sair" -ForegroundColor $script:Config.UI.Colors.Error
                $choice = Read-Host "`n  Digite sua escolha"
                
                switch ($choice.ToUpper()) {
                    'I' { 
                        Write-Host "`n$separator" -ForegroundColor $script:Config.UI.Colors.Success
                        Write-LogMessage "Iniciando instalação..." -Type Info
                        Write-Host "$separator`n" -ForegroundColor $script:Config.UI.Colors.Success
                    }
                    default { 
                        Write-LogMessage "Operação cancelada pelo usuário." -Type Info
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
            Write-LogMessage "Instalação concluída com sucesso! ($($finalInstall.Version))" -Type Success
        }
        else {
            throw "Instalação aparentemente bem-sucedida, mas winget não encontrado!"
        }
    }
    catch {
        Write-LogMessage "Erro crítico: $($_.Exception.Message)" -Type Error
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