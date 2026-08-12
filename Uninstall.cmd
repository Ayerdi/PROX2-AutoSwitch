@echo off
setlocal
title Audio AutoSwitch - Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Desinstalar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
pause
exit /b %exitCode%
