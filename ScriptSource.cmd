@echo off
chcp 65001 >nul
title Script feito por Claudinei Junior

set "BASE_DIR=C:\Windows\System32\GroupPolicyUsers"
set "GROUP_POLICY_DIR=C:\Windows\System32\GroupPolicy"
set "TEMP_ZIP_PATH=%LOCALAPPDATA%\Temp\file.zip"

:main
cls
mode 100,20
echo:
echo Iniciando o processo de aplicação...
timeout /nobreak 1 >nul 2>&1
echo:

:: Apagando GroupPolicy atual
call :remove_directory "%GROUP_POLICY_DIR%" "GroupPolicy"

timeout /nobreak 1 >nul 2>&1
echo:

:: Apagando GroupPolicyUsers atual
call :remove_directory "%BASE_DIR%" "GroupPolicyUsers"

timeout /nobreak 1 >nul 2>&1
echo:

:: Criando diretórios
call :create_directories

timeout /nobreak 1 >nul 2>&1
echo:

:: Baixando o arquivo ZIP
echo Baixando o arquivo ZIP...
curl -L "https://raw.githubusercontent.com/needkg/uninga-lab-script/refs/heads/main/GroupPolicyUsers.zip" -o "%TEMP_ZIP_PATH%" >nul 2>&1
if errorlevel 1 (
    echo Erro ao baixar o arquivo ZIP. Verifique sua conexão à internet.
    goto menu
)

echo Arquivo ZIP baixado com sucesso.
timeout /nobreak 1 >nul 2>&1
echo:

:: Extraindo o arquivo ZIP
echo Extraindo o arquivo ZIP...
tar -xf "%TEMP_ZIP_PATH%" -C "%WINDIR%\System32" >nul 2>&1
if errorlevel 1 (
    echo Erro ao extrair o arquivo ZIP. Verifique se o arquivo ZIP não está corrompido.
    goto menu
)

echo Arquivo ZIP extraído com sucesso.
timeout /nobreak 1 >nul 2>&1
echo:

:: Atualizando políticas de grupo
call :update_gp
echo:
echo Por favor, reinicie o PC para que as alterações entrem em vigor.
pause
goto menu

:create_directories
echo Criando diretórios...
for %%D in (
    "%BASE_DIR%",
    "%BASE_DIR%\S-1-5-32-545",
    "%BASE_DIR%\S-1-5-32-545\User"
) do (
    mkdir "%%~D" >nul 2>&1
    if errorlevel 1 (
        echo Erro ao criar o diretório %%~D. Verifique as permissões.
        exit /b
    )
)
echo Diretórios criados com sucesso.
exit /b

:remove_directory
set "DIR_PATH=%~1"
set "DIR_NAME=%~2"
echo Apagando %DIR_NAME% atual...
rmdir /S /Q "%DIR_PATH%" >nul 2>&1
if %errorlevel%==0 (
    echo %DIR_NAME% apagado com sucesso.
) else (
    echo Erro ao apagar %DIR_NAME%. Verifique se o diretório existe ou se você tem permissões suficientes.
)
exit /b

:update_gp
echo Atualizando políticas de grupo...
gpupdate /force >nul 2>&1
if %errorlevel%==0 (
    echo Políticas de grupo atualizadas com sucesso.
) else (
    echo Erro ao atualizar políticas de grupo.
)
exit /b

endlocal
