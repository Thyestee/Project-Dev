@echo off
rem Updates Hollow Vein Mine from GitHub, then starts it.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher\launcher.ps1"
