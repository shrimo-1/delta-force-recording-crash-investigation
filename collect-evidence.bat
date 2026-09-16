@echo off
setlocal
set "SCRIPT=%~dp0tools\Collect-Evidence.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Collection returned exit code %RC%.
pause
exit /b %RC%
