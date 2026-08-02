@echo off
setlocal EnableExtensions EnableDelayedExpansion
title JENGA Twitch Connector Setup
cd /d "%~dp0"

set "NODE_EXE="

where node >nul 2>nul
if %errorlevel%==0 set "NODE_EXE=node"

if not defined NODE_EXE if exist "%ProgramFiles%\nodejs\node.exe" (
    set "NODE_EXE=%ProgramFiles%\nodejs\node.exe"
)

if not defined NODE_EXE (
    echo Node.js was not found.
    echo.

    where winget >nul 2>nul
    if not %errorlevel%==0 (
        echo Install Node.js LTS from https://nodejs.org/
        pause
        exit /b 1
    )

    choice /M "Install Node.js LTS automatically"
    if errorlevel 2 exit /b 1

    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements

    if exist "%ProgramFiles%\nodejs\node.exe" (
        set "NODE_EXE=%ProgramFiles%\nodejs\node.exe"
    )
)

if not defined NODE_EXE (
    echo Restart this file after Node.js installation.
    pause
    exit /b 1
)

if exist "config.json" (
    echo Existing channel configuration found:
    type config.json
    echo.

    choice /M "Keep this channel"
    if errorlevel 2 del /q "config.json"
)

if not exist "config.json" (
    echo.
    set "CHANNEL="
    set /p "CHANNEL=Enter your Twitch login name, without URL or #: "

    if not defined CHANNEL (
        echo No channel entered.
        pause
        exit /b 1
    )

    set "CHANNEL=!CHANNEL:#=!"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$c='!CHANNEL!'.Trim().ToLower();" ^
      "if ([string]::IsNullOrWhiteSpace($c)) { exit 2 };" ^
      "$json=@{channel=$c} | ConvertTo-Json;" ^
      "$utf8=New-Object System.Text.UTF8Encoding($false);" ^
      "[System.IO.File]::WriteAllText((Join-Path (Get-Location) 'config.json'), $json, $utf8)"

    if errorlevel 1 (
        echo Could not save the channel configuration.
        pause
        exit /b 1
    )

    echo Saved Twitch channel: !CHANNEL!
)

set "NPM_CMD="

if exist "%ProgramFiles%\nodejs\npm.cmd" (
    set "NPM_CMD=%ProgramFiles%\nodejs\npm.cmd"
) else (
    where npm >nul 2>nul
    if %errorlevel%==0 set "NPM_CMD=npm"
)

if not defined NPM_CMD (
    echo npm was not found.
    pause
    exit /b 1
)

if not exist "node_modules\tmi.js" (
    echo Installing connector dependencies...
    call "%NPM_CMD%" install

    if errorlevel 1 (
        echo npm install failed.
        pause
        exit /b 1
    )
)

echo.
echo Starting JENGA Twitch Connector...
"%NODE_EXE%" connector.js
pause
