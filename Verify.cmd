@echo off
setlocal
title Audio AutoSwitch - Verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verificar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
pause
exit /b %exitCode%
