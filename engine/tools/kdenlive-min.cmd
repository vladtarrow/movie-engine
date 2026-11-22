@echo off
rem Starts Kdenlive minimized with the in-project profile. Used by kd-check.ps1 / kdenlive-bg.ps1
rem through WMI so that the new window has no right to take the keyboard focus.
setlocal
set "ENGINE_DIR=%~dp0.."
set "PROFILE_DIR=%ENGINE_DIR%\profile-kdenlive"
set "USERPROFILE=%PROFILE_DIR%"
set "APPDATA=%PROFILE_DIR%\AppData\Roaming"
set "LOCALAPPDATA=%PROFILE_DIR%\AppData\Local"
set "XDG_CONFIG_HOME=%PROFILE_DIR%\AppData\Local"
set "XDG_DATA_HOME=%PROFILE_DIR%\AppData\Local"
set "XDG_CACHE_HOME=%PROFILE_DIR%\AppData\Local\cache"
rem Interface language: English unless MOVIE_ENGINE_UI_LANG names another (see tools\kd-state.ps1)
if defined MOVIE_ENGINE_UI_LANG (set "LANGUAGE=%MOVIE_ENGINE_UI_LANG%") else (set "LANGUAGE=en_US")
set "LANG=%LANGUAGE%"
start "" /min "%ENGINE_DIR%\Kdenlive\kdenlive-26.08.3_standalone\bin\kdenlive.exe" %*
endlocal
