@echo off
setlocal
title ECNU OpenConnect - Stop
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\internal\ECNU-OpenConnect-GUI.ps1" Disconnect
pause
exit /b %ERRORLEVEL%
