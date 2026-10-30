@echo off
rem Sizzle FX render server (Phase 5). First run creates server\.venv and installs deps.
cd /d "%~dp0"
if not exist .venv (
  echo Creating Python venv...
  py -3.11 -m venv .venv || python -m venv .venv
  .venv\Scripts\python -m pip install --use-feature=truststore -r requirements.txt
)
rem regenerate the shared shader contract from src/render/glslLoader.js
node ..\scripts\export-contract.mjs
.venv\Scripts\python -m uvicorn app:app --host 127.0.0.1 --port 8790
