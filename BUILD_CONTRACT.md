# Monolith v1 Runtime Installer Build Contract (Windows)

## 1. Objectives
This contract defines how to produce a commercial-grade Windows installer for **Monolith v1** that:

- Detects CUDA-capable NVIDIA hardware at install time.
- Creates an isolated Python runtime under `%LOCALAPPDATA%\Monolith\runtime`.
- Installs required dependencies into that isolated environment only.
- Creates predictable runtime, data, install-log, and model folders.
- Preserves user data across upgrades.
- Ships as a conventional wizard installer (Next/Next/Finish), without requiring Python on the target machine.

## 2. Directory Contract (Target Machine)
Installer must create and maintain these folders:

- `%LOCALAPPDATA%\Monolith\app\` → application runtime assets and launcher scripts.
- `%LOCALAPPDATA%\Monolith\runtime\` → isolated Python runtime and site-packages.
- `%LOCALAPPDATA%\Monolith\data\` → persistent user data (must survive upgrades/uninstall by default).
- `%LOCALAPPDATA%\Monolith\install\` → install logs and detection traces.
- `%LOCALAPPDATA%\Monolith\models\` → empty model repository for future downloads.

## 3. Packaging Contract

### 3.1 Required payload inside installer build context
Build pipeline must stage these artifacts before compiling `.iss`:

- `payload\python\` → bundled CPython distribution for Windows (no system Python dependency).
  - Must include `python.exe`, standard library, and `Scripts\pip.exe` (or `ensurepip` support).
- `payload\app\` → Monolith launch scripts/binaries/UI assets (no model files).
- `scripts\detect_gpu.bat` and `scripts\install_env.bat`.

### 3.2 Python isolation contract
All package installs must use:

- `%LOCALAPPDATA%\Monolith\runtime\python\python.exe -m pip ...`

Never call plain `pip` or `python` without full runtime path during installation.

### 3.3 Dependency contract
Install always:

- `PySide6`
- `llama-cpp-python`

Install PyTorch stack based on detection:

- GPU path:
  - `torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121`
- CPU path:
  - `torch torchvision torchaudio`

## 4. Hardware Detection Contract

### 4.1 Detection criteria
Installer classifies target as **GPU-capable** only when:

1. NVIDIA adapter is detected (`nvidia-smi` successful OR WMI reports NVIDIA controller), and
2. CUDA capability is inferred from successful `nvidia-smi` execution.

If detection fails or is ambiguous, default to **CPU** build for reliability.

### 4.2 Detection output
`detect_gpu.bat` must write:

- `%LOCALAPPDATA%\Monolith\install\gpu_mode.txt`
  - value: `GPU` or `CPU`

It should also append verbose diagnostics to:

- `%LOCALAPPDATA%\Monolith\install\installer.log`

## 5. Installer Orchestration Contract

Execution order:

1. Create directory tree.
2. Deploy bundled Python to `%LOCALAPPDATA%\Monolith\runtime\python`.
3. Deploy app assets to `%LOCALAPPDATA%\Monolith\app`.
4. Run `detect_gpu.bat`.
5. Run `install_env.bat` (reads `gpu_mode.txt`, installs packages accordingly).
6. Create Start Menu + Desktop shortcuts to launcher.
7. Write final status to install logs.

## 6. Upgrade/Uninstall Contract

- Upgrades must not remove `%LOCALAPPDATA%\Monolith\data`.
- Upgrades should reuse existing `%LOCALAPPDATA%\Monolith\runtime` if compatible; otherwise rebuild runtime in place.
- Uninstall should remove app/runtime artifacts but leave `data` and `models` unless user explicitly chooses full wipe (optional advanced flow).

## 7. Logging Contract

At minimum write to `%LOCALAPPDATA%\Monolith\install\installer.log`:

- installer version/build metadata
- GPU detection result and raw probe results
- pip command invocations + exit codes
- completion/failure marker

## 8. CI/Release Build Contract

`build_release.bat` responsibilities:

1. Validate presence of Inno Setup compiler (`ISCC.exe`).
2. Validate payload folders (`payload\python`, `payload\app`).
3. Generate/clean staging and output directories.
4. Compile `MonolithInstaller.iss`.
5. Publish installer executable under `dist\`.

## 9. Security and Reliability Notes

- Do not execute unsigned remote scripts during install.
- Prefer pinned versions for production reproducibility (variables provided in scripts).
- Keep pip cache inside runtime or disable to reduce residue.
- Never bundle user models in installer payload.

## 10. Acceptance Criteria (v1)
A fresh Windows machine without Python installed can:

1. Run installer wizard to completion.
2. Launch Monolith from Start Menu/Desktop.
3. Open Chat/Terminal UI successfully.
4. Confirm runtime packages installed in isolated runtime path.
5. Upgrade to newer installer without losing `%LOCALAPPDATA%\Monolith\data`.
