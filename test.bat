@echo off
REM Прогон юнит-тестов экономики.
REM Код возврата: 0 - зелено, 1 - есть падения (для CI).
"F:\Programs\Lune\lune.exe" run "%~dp0tests\run"
exit /b %ERRORLEVEL%
