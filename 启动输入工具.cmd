@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist "%~dp0runtime\AutoHotkey64.exe" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-runtime.ps1"
    if errorlevel 1 (
        echo Runtime preparation failed. See README.md for manual setup.
        pause
        exit /b 1
    )
)
if /i "%~1"=="--test" goto test
start "" "%~dp0runtime\AutoHotkey64.exe" "%~dp0输入工具.ahk"
exit /b 0

:test
start "" /wait "%~dp0runtime\AutoHotkey64.exe" /ErrorStdOut "%~dp0验收.ahk" --test
set "testExit=%ERRORLEVEL%"
if exist "%~dp0验收结果.txt" type "%~dp0验收结果.txt"
exit /b %testExit%
