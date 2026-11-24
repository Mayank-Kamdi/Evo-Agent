@echo off
title Push to GitHub - Evo-Agent
echo ========================================================
echo Pushing Evo-Agent to https://github.com/Mayank-Kamdi/Evo-Agent.git
echo ========================================================
echo.
cd /d "%~dp0"
git push -u origin main
echo.
if %ERRORLEVEL% equ 0 (
    echo ========================================================
    echo SUCCESS! Repository pushed to GitHub successfully.
    echo ========================================================
) else (
    echo ========================================================
    echo PUSH FAILED or needs authentication.
    echo If browser sign-in opened, please complete the sign-in.
    echo ========================================================
)
echo.
pause

