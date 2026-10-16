@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0sync.ps1"
pause
