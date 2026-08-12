@echo off
setlocal
title Audio AutoSwitch - Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar-PROX2-AutoSwitch.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
if not "%exitCode%"=="0" echo Installation exited with code %exitCode%.
pause
exit /b %exitCode%
