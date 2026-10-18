@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
set "INSTALL_RESULT=%ERRORLEVEL%"
if not "%INSTALL_RESULT%"=="0" echo Uninstall failed. Please save and quit Photoshop, then try again.
pause
exit /b %INSTALL_RESULT%
