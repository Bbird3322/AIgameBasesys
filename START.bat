@echo off
if exist "%~dp0START.exe" (
	start "" "%~dp0START.exe"
	exit /b 0
)

powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\launch-llama-server.ps1"
exit /b %errorlevel%
