@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "INSTALL_RESULT=%ERRORLEVEL%"
if not "%INSTALL_RESULT%"=="0" echo Installation failed. Please save and quit Photoshop, then try again.
pause
exit /b %INSTALL_RESULT%
