@echo off
cd /d "%~dp0"
if not exist "config.json" (
  call setup_and_start.bat
  exit /b
)
node connector.js
pause
