@echo off
if exist "%~dp0logs\startup-popup.signal" del /q "%~dp0logs\startup-popup.signal"
if exist "%~dp0START.ps1" (
	powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0START.ps1"
	exit /b %errorlevel%
)

if exist "%~dp0START.exe" (
	"%~dp0START.exe"
	exit /b %errorlevel%
)

echo Launcher entrypoint not found: START.ps1 / START.exe
exit /b 1
