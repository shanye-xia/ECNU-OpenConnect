@echo off
setlocal
title ECNU OpenConnect
start "" powershell.exe -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\ECNU-OpenConnect-GUI.ps1" Gui
exit /b 0
