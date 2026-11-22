@echo off
rem Runs the Node.js that travels with this folder (engine\node\node.exe); never the system one.
rem   engine\node.cmd engine\voice\voice.mjs <lines.json> <out folder>
if not exist "%~dp0node\node.exe" (
  echo engine\node\node.exe is missing: copy node.exe 18 or newer into engine\node\ 1>&2
  exit /b 1
)
"%~dp0node\node.exe" %*
