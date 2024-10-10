@echo off
chcp 65001 >nul
title Script feito por Claudinei Junior

:main
mkdir "%APPDATA%\Claudinei" >nul 2>&1
curl -L "https://raw.githubusercontent.com/needkg/uninga-lab-script/refs/heads/main/ScriptSource.cmd?token=%RANDOM%" -o "%APPDATA%\Claudinei\Script.cmd"
start "" "%APPDATA%\Claudinei\Script.cmd" >nul 2>&1
exit
