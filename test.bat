@echo off
REM Run the economy unit test suite.
REM Exit codes: 0 = all passed, 1 = failures, 127 = runtime not found.
REM
REM ASCII only on purpose: cmd.exe reads .bat files in the OEM codepage,
REM so non-ASCII comments and messages get mangled and can break parsing.

setlocal

REM Lookup order: explicit LUNE_PATH -> lune on PATH.
REM No hardcoded path here: it would not exist on another machine or in CI.

if defined LUNE_PATH (
  if exist "%LUNE_PATH%" (
    set "LUNE=%LUNE_PATH%"
    goto :run
  )
  echo ERROR: LUNE_PATH points to a missing file:
  echo   %LUNE_PATH%
  exit /b 127
)

where lune >nul 2>&1
if %ERRORLEVEL%==0 (
  set "LUNE=lune"
  goto :run
)

echo ERROR: Lune not found. It is the Luau runtime the tests run in.
echo.
echo Either:
echo   1. add lune to PATH, or
echo   2. set LUNE_PATH=C:\path\to\lune.exe
echo.
echo Download: https://github.com/lune-org/lune/releases
exit /b 127

:run
"%LUNE%" run "%~dp0tests\run"
exit /b %ERRORLEVEL%
