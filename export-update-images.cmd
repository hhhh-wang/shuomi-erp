@echo off
rem SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
setlocal
title Export Shuomi ERP update images
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\export-images.ps1" -Package update %*
set "TASK_EXIT=%ERRORLEVEL%"
if not "%TASK_EXIT%"=="0" echo Export failed. Read the error above.
if "%~1"=="" pause
exit /b %TASK_EXIT%
