@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" -Lan -OpenBrowser
if errorlevel 1 (
  echo.
  echo Failed to start LAN server.
  pause
)
