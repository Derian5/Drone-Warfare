@echo off
python "%~dp0tools\serve_web.py" --open
if errorlevel 1 pause
