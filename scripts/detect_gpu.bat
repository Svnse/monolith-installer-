@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Detect NVIDIA CUDA availability for Monolith runtime installer.
rem Output file: %LOCALAPPDATA%\Monolith\install\gpu_mode.txt with value GPU or CPU.

set "BASE=%LOCALAPPDATA%\Monolith"
set "INSTALL_DIR=%BASE%\install"
set "LOG=%INSTALL_DIR%\installer.log"
set "MODE_FILE=%INSTALL_DIR%\gpu_mode.txt"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [GPU-DETECT] ---- %DATE% %TIME% ---->>"%LOG%"
echo [GPU-DETECT] Starting hardware probe>>"%LOG%"

set "GPU_MODE=CPU"

rem Probe 1: nvidia-smi in PATH (strong CUDA signal).
where nvidia-smi >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%A in ('nvidia-smi --query-gpu=name --format=csv,noheader 2^>nul') do (
        set "GPU_NAME=%%A"
        set "GPU_MODE=GPU"
        goto :detected
    )
)

rem Probe 2: fallback via WMI for NVIDIA adapter, still keep CPU default when uncertain.
for /f "delims=" %%A in ('wmic path win32_VideoController get name ^| findstr /I "NVIDIA" 2^>nul') do (
    set "GPU_NAME=%%A"
    rem WMI alone does not guarantee CUDA runtime compatibility; keep conservative CPU default.
    echo [GPU-DETECT] NVIDIA controller found via WMI but CUDA probe unavailable, using CPU mode>>"%LOG%"
    goto :detected
)

:detected
echo %GPU_MODE%>"%MODE_FILE%"
if defined GPU_NAME (
  echo [GPU-DETECT] GPU_NAME=!GPU_NAME!>>"%LOG%"
)
echo [GPU-DETECT] RESULT=%GPU_MODE%>>"%LOG%"
exit /b 0
