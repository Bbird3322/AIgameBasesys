@echo off
setlocal
set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%ROOT_DIR%scripts\hf-gguf-downloader.ps1"
