@echo off
setlocal
cd /d "%~dp0"
if exist "config.json" del /q "config.json"
call setup_and_start.bat
