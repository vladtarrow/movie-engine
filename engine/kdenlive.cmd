@echo off
rem Starts Kdenlive with its settings, caches and temp files kept inside engine\profile-kdenlive,
rem so the whole project can be copied to another computer.
setlocal
set "ENGINE_DIR=%~dp0"
set "PROFILE_DIR=%ENGINE_DIR%profile-kdenlive"
if not exist "%PROFILE_DIR%\AppData\Roaming" mkdir "%PROFILE_DIR%\AppData\Roaming"
if not exist "%PROFILE_DIR%\AppData\Local\Temp" mkdir "%PROFILE_DIR%\AppData\Local\Temp"
set "USERPROFILE=%PROFILE_DIR%"
set "APPDATA=%PROFILE_DIR%\AppData\Roaming"
set "LOCALAPPDATA=%PROFILE_DIR%\AppData\Local"
set "XDG_CONFIG_HOME=%PROFILE_DIR%\AppData\Local"
set "XDG_DATA_HOME=%PROFILE_DIR%\AppData\Local"
set "XDG_CACHE_HOME=%PROFILE_DIR%\AppData\Local\cache"
rem Interface language: English unless MOVIE_ENGINE_UI_LANG names another (see tools\kd-state.ps1)
if defined MOVIE_ENGINE_UI_LANG (set "LANGUAGE=%MOVIE_ENGINE_UI_LANG%") else (set "LANGUAGE=en_US")
set "LANG=%LANGUAGE%"
set "TEMP=%PROFILE_DIR%\AppData\Local\Temp"
set "TMP=%PROFILE_DIR%\AppData\Local\Temp"
if not "%~1"=="" powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE_DIR%tools\kd-rebase.ps1" -Project "%~f1"
rem A project is opened by kd-open.ps1 (empty editor first): the direct start took about 10 minutes longer on big projects.
if /i "%~x1"==".kdenlive" if "%~2"=="" if exist "%~f1" goto fastopen
start "" "%ENGINE_DIR%Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe" %*
endlocal
exit /b 0
:fastopen
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ENGINE_DIR%tools\kd-open.ps1" -Project "%~f1" -Normal
endlocal
