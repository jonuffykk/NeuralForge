@echo off
title NeuralForge
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0installer\NeuralForge.ps1" %*
if errorlevel 1 pause
