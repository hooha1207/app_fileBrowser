@echo off
echo =======================================================
echo     Flutter Project Initialization Script
echo =======================================================
echo.
echo This script will generate the platform specific folders
echo (android, ios, web, windows, etc.) and fetch dependencies.
echo.
pause

echo.
echo [1/2] Generating platform folders (flutter create .)...
call flutter create .

echo.
echo [2/2] Fetching dependencies (flutter pub get)...
call flutter pub get

echo.
echo =======================================================
echo     Initialization Complete!
echo =======================================================
echo You can now run the project with 'flutter run'.
echo.
pause
