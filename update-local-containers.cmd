@echo off
rem SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
setlocal
title Update local Shuomi ERP containers
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-local-containers.ps1" %*
set "TASK_EXIT=%ERRORLEVEL%"
if not "%TASK_EXIT%"=="0" echo Local update failed. Read the error above or check Docker Desktop logs.
if "%~1"=="" pause
exit /b %TASK_EXIT%
