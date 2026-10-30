@echo off
cd /d "%~dp0"
if not exist node_modules (
  echo Installing dependencies...
  call npm install
)
if not exist public\models\rvm_mobilenetv3_fp32.onnx (
  echo Downloading mask models (~170 MB, first run only)...
  call npm run fetch-models
)
rem optional render server (Phase 5): only if its Python venv exists (server\start.bat creates it)
if exist server\.venv (
  start "Sizzle FX render server" cmd /c server\start.bat
)
start "" http://localhost:5180
call npm run dev
