@echo off
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Установи Node.js с сайта nodejs.org и запусти этот файл снова.
  pause
  exit /b 1
)
call npm install
if errorlevel 1 ( pause & exit /b 1 )
call npm run dist
echo.
echo Готово. Установщик и папка с программой лежат в папке dist.
pause
