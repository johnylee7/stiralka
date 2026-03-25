@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" -OpenBrowser
if errorlevel 1 (
  echo.
  echo Failed to start local server.
  pause
)
