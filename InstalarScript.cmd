@echo off
chcp 65001 >nul
title Script feito por Claudinei Junior

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissões de administrador...
    powershell -Command "Start-Process '%~0' -Verb RunAs" >nul 2>&1
    exit /b
)

:menu
cls
color 0A

echo:
echo       ___________________________________________      
echo:                                                    	
echo:                        Opções:                         
echo:                              
echo:                    [1] Instalar               
echo:                    [2] Desinstalar                                              
echo:       ___________________________________________
choice /C 12 /N
set _erl=%errorlevel%

if %_erl%==1 goto instalar
if %_erl%==2 goto desinstalar

goto menu

:instalar
cls
mkdir "%APPDATA%\Claudinei" >nul 2>&1
curl -L "https://raw.githubusercontent.com/needkg/uninga-lab-script/refs/heads/main/ScriptLauncher.zip?token=%RANDOM%" -o "%APPDATA%\Claudinei\ScriptLauncher.zip"
tar -xf "%APPDATA%\Claudinei\ScriptLauncher.zip" -C "%APPDATA%\Claudinei"
schtasks /create /tn "ScriptClaudinei" /tr "%APPDATA%\Claudinei\ScriptLauncher.cmd" /sc onlogon /rl highest /f
schtasks /run /tn "ScriptClaudinei"
pause
goto menu



:desinstalar
schtasks /delete /tn "ScriptClaudinei" /f

goto menu