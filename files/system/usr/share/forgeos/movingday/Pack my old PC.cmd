@echo off
rem ForgeOS Moving Day - packs your files onto this USB stick for your new ForgeOS PC.
rem It only reads this PC and changes nothing on it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ForgeOS Moving Day\pack.ps1"
pause
