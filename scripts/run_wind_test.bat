@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Validate exactly one argument
if "%~1"=="" goto :usage
if not "%~2"=="" goto :usage

REM Validate file exists
if not exist "%~1" (
  echo Error: File not found: %~1
  exit /b 66
)

set "XCNAV_LOG=%~1"
echo Using XCNAV_LOG="%XCNAV_LOG%"

REM Run the wind unit test
flutter test test\wind_from_json_test.dart
set EXITCODE=%ERRORLEVEL%
exit /b %EXITCODE%

:usage
echo Usage: %~n0 path\to\flight_log.json
echo Example: %~n0 C:\logs\my_flight.json
exit /b 64

