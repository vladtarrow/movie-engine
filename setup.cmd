@echo off
rem One-step setup of Movie Engine: Node.js, its packages and portable Kdenlive, all inside this folder.
rem Double-click it, or run "setup.cmd -DryRun" to see what it would download first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0engine\install.ps1" %*
set "CODE=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %CODE%
