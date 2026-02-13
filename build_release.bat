@echo off
setlocal EnableExtensions

rem Monolith v1 installer build orchestrator.
rem Expected from repo root:
rem   payload\python\...   (bundled CPython runtime)
rem   payload\app\...      (Monolith runtime app assets/launcher)
rem   MonolithInstaller.iss

set "ROOT=%~dp0"
cd /d "%ROOT%"

set "DIST_DIR=%ROOT%dist"
set "BUILD_DIR=%ROOT%build"
set "ISCC_DEFAULT=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
set "ISCC=%ISCC_DEFAULT%"

if not "%~1"=="" set "ISCC=%~1"

echo [BUILD] Root: %ROOT%

if not exist "%ISCC%" (
  echo [BUILD] ERROR: Inno Setup compiler not found: "%ISCC%"
  echo [BUILD] Pass ISCC path as first argument, e.g.:
  echo [BUILD] build_release.bat "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
  exit /b 10
)

if not exist "%ROOT%payload\python\python.exe" (
  echo [BUILD] ERROR: Missing bundled Python runtime at payload\python\python.exe
  exit /b 11
)

if not exist "%ROOT%payload\app" (
  echo [BUILD] ERROR: Missing app payload directory payload\app
  exit /b 12
)

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
mkdir "%BUILD_DIR%"

echo [BUILD] Compiling installer...
"%ISCC%" "%ROOT%MonolithInstaller.iss" /DMonolithVersion=1.0.0 /O"%DIST_DIR%"
if not %errorlevel%==0 (
  echo [BUILD] ERROR: ISCC failed.
  exit /b 13
)

echo [BUILD] SUCCESS: Installer output in %DIST_DIR%
exit /b 0
