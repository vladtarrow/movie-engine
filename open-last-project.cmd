@echo off
rem Opens Kdenlive with the project that was open last (the newest entry of its Recent files).
rem Settings stay inside engine\profile-kdenlive. Loading a big project takes a few minutes; the window appears first.
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0engine\tools\kd-open-last.ps1"
