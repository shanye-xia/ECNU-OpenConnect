@echo off
setlocal
title ECNU OpenConnect - Force Stop
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\internal\ECNU-OpenConnect-GUI.ps1" ForceStop
pause
exit /b %ERRORLEVEL%
