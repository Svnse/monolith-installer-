@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Monolith isolated runtime setup.
rem Must only use bundled runtime Python, never system Python.

set "BASE=%LOCALAPPDATA%\Monolith"
set "RUNTIME_DIR=%BASE%\runtime"
set "PYTHON_HOME=%RUNTIME_DIR%\python"
set "PYTHON_EXE=%PYTHON_HOME%\python.exe"
set "INSTALL_DIR=%BASE%\install"
set "LOG=%INSTALL_DIR%\installer.log"
set "MODE_FILE=%INSTALL_DIR%\gpu_mode.txt"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"

echo [ENV-INSTALL] ---- %DATE% %TIME% ---->>"%LOG%"

if not exist "%PYTHON_EXE%" (
  echo [ENV-INSTALL] ERROR: Missing bundled python at "%PYTHON_EXE%">>"%LOG%"
  exit /b 2
)

set "GPU_MODE=CPU"
if exist "%MODE_FILE%" (
    set /p GPU_MODE=<"%MODE_FILE%"
)

echo [ENV-INSTALL] GPU_MODE=%GPU_MODE%>>"%LOG%"

rem Bootstrap pip if missing.
"%PYTHON_EXE%" -m pip --version >nul 2>&1
if not %errorlevel%==0 (
    echo [ENV-INSTALL] pip missing, running ensurepip>>"%LOG%"
    "%PYTHON_EXE%" -m ensurepip --upgrade >>"%LOG%" 2>&1
)

rem Upgrade packaging toolchain.
"%PYTHON_EXE%" -m pip install --upgrade pip setuptools wheel >>"%LOG%" 2>&1
if not %errorlevel%==0 (
  echo [ENV-INSTALL] ERROR: Failed to bootstrap pip tooling>>"%LOG%"
  exit /b 3
)

rem Core packages always installed.
"%PYTHON_EXE%" -m pip install PySide6 llama-cpp-python >>"%LOG%" 2>&1
if not %errorlevel%==0 (
  echo [ENV-INSTALL] ERROR: Failed to install required core packages>>"%LOG%"
  exit /b 4
)

if /I "%GPU_MODE%"=="GPU" (
  echo [ENV-INSTALL] Installing CUDA 12.1 PyTorch wheels>>"%LOG%"
  "%PYTHON_EXE%" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 >>"%LOG%" 2>&1
) else (
  echo [ENV-INSTALL] Installing CPU PyTorch wheels>>"%LOG%"
  "%PYTHON_EXE%" -m pip install torch torchvision torchaudio >>"%LOG%" 2>&1
)

if not %errorlevel%==0 (
  echo [ENV-INSTALL] ERROR: Failed to install torch stack>>"%LOG%"
  exit /b 5
)

echo [ENV-INSTALL] SUCCESS>>"%LOG%"
exit /b 0
