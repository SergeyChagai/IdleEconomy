@echo off
REM Run both test suites the project owns.
REM
REM 1) Console suite (Lune) -- always, CI-ready exit code.
REM 2) Studio suite (TestEZ) -- needs Rojo + Play; this script prints how.
REM
REM ASCII only: cmd.exe reads .bat files in the OEM codepage.

setlocal
set "ROOT=%~dp0"

echo === Console suite (Lune) ===
call "%ROOT%test.bat"
if errorlevel 1 (
  echo Console suite failed -- skipping Studio instructions.
  exit /b 1
)

echo.
echo === Studio suite (TestEZ) ===
echo Stop any running rojo serve, then:
echo   rojo serve test.project.json
echo In Studio: Plugins -^> Rojo -^> Connect -^> Play
echo Watch Output for [StudioTests] server/client suite passed.
echo.
echo Production Play still uses default.project.json (no TestEZ runners).
exit /b 0
