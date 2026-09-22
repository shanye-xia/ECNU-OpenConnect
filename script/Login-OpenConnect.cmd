@echo off
setlocal
title ECNU OpenConnect - Login
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\internal\ECNU-OpenConnect-GUI.ps1" CliLogin
pause
exit /b %ERRORLEVEL%
