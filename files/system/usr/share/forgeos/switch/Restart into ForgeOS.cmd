@echo off
rem ForgeOS by RL Forge Works - restart this PC into ForgeOS one time (Job 13e).
rem Windows asks for permission (admin) first. The normal start-up order is not changed.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%PUBLIC%\Documents\ForgeOS\restart-into-forgeos.ps1'"
