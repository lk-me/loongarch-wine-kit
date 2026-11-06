# loongarch-wine-kit

**English** | [简体中文](README.zh-CN.md)

Reproducible toolchain and build workflow for running Wine natively on
**LoongArch64 Linux** — no x86 emulation or binary translation involved.

The kit turns a plain loongarch64 machine into a host that can compile
`loongarch64-windows` PE binaries and run them under a native LoongArch build
of Wine.

| Item | Value |
| --- | --- |
| Target triple | `loongarch64-windows` (`IMAGE_FILE_MACHINE_LOONGARCH64`, `0x6264`) |
| Toolchain | LLVM/Clang + LLD, cross-targeted to LoongArch PE |
| Wine versions | 10.14, 11.16 |
| Verified on | Loongson-3A5000, 4 cores / 16 GB, Debian 10, kernel 4.19 (16 KB pages) |
| Verification | `wineboot`, `wine cmd /c ver`, `winecfg`, `notepad` |

---

## 1. Why a kit is needed

Upstream LLVM cannot emit Windows PE for LoongArch, and upstream Wine has no
LoongArch backend. Three layers had to be added:

| Layer | Content |
| --- | --- |
| LLVM (13 commits) | MC-layer COFF writer, LLD COFF support, import thunks, `.pdata` sorting, PE unwind encoding, Windows target info |
| mingw CRT | Minimal `mainCRTStartup` that preserves `$ra` and carries `.seh_*` unwind metadata |
| Wine (11 / 21 commits) | Build system, signal/context handling, stack unwinding + `__C_specific_handler`, PE loading and runtime fixes |

Details per commit: [MODIFICATIONS.md](MODIFICATIONS.md).

---

## 2. Requirements

| Item | Requirement |
| --- | --- |
| Build host | **loongarch64 Linux** (Wine links native unix-side objects; it cannot be cross-built on x86) |
| Packages | `gcc g++ make ninja-build flex bison pkg-config python3 git`, X11 dev headers (`libx11-dev libxext-dev libxrender-dev`) |
| CMake | ≥ 3.20 (see §2.1 if the distro ships 3.13) |
| Disk | 25–30 GB for LLVM sources + build, ~6 GB for Wine |
| Display | Xorg on `DISPLAY=:0` for the GUI verification step |

### 2.1 Bootstrapping a newer CMake

Debian 10 ships CMake 3.13.4, which is below LLVM's minimum:

```bash
BASE=$HOME/cmake-boot && mkdir -p "$BASE" && cd "$BASE"
curl -sLO https://cmake.org/files/v3.28/cmake-3.28.6.tar.gz
tar xf cmake-3.28.6.tar.gz && cd cmake-3.28.6
./bootstrap --parallel=4 --prefix="$BASE/install" > bootstrap.log 2>&1
make -j4 >> bootstrap.log 2>&1
make install >> bootstrap.log 2>&1
export PATH="$BASE/install/bin:$PATH"
```

15–30 minutes on four cores.

---

## 3. Repository layout

```text
loongarch-wine-kit/
├── env.sh                     # single place for all paths and knobs
├── README.md                  # this file
├── README.zh-CN.md            # Chinese version
├── MODIFICATIONS.md           # per-commit description of every change
├── CREDITS.md                 # effort / resource accounting
├── crt/
│   ├── crt0.S                 # PE entry point: saves $ra, carries .seh_* metadata
│   └── empty.S                # placeholder for crtbegin.o / crtend.o
├── patches/
│   ├── llvm/                  # 13 patches for llvm-project
│   ├── wine/                  # 11 patches for wine-10.14
│   └── wine-11.16/            # 20 patches for wine-11.16
└── scripts/
    ├── 01-build-llvm.sh
    ├── 02-install-crt.sh
    ├── 03-deploy-toolchain.sh
    ├── 04-build-wine.sh
    └── 05-verify.sh
```

Working tree defaults to `$WORK=$HOME/loongarch-wine`:

```text
$WORK/
├── llvm-project/
├── wine-11.16/            # or wine-10.14
├── build-llvm/
├── toolchain/             # clang, lld, sysroot/loongarch64-w64-mingw32
└── build-wine/
```

---

## 4. Quick start (single machine)

```bash
KIT=/path/to/loongarch-wine-kit
export WORK=$HOME/loongarch-wine && mkdir -p "$WORK"

# 1. Sources
git clone --depth 1 https://github.com/llvm/llvm-project.git "$WORK/llvm-project"
git clone https://github.com/wine-mirror/wine.git "$WORK/wine-11.16"
git -C "$WORK/wine-11.16" checkout wine-11.16

# 2. Patches
git -C "$WORK/llvm-project" am "$KIT"/patches/llvm/*.patch
git -C "$WORK/wine-11.16"   am "$KIT"/patches/wine-11.16/*.patch

# 3. Build (step 01 takes hours — run it under nohup/screen)
"$KIT"/scripts/01-build-llvm.sh
"$KIT"/scripts/02-install-crt.sh
"$KIT"/scripts/03-deploy-toolchain.sh    # no-op when TARGET_HOST is empty
"$KIT"/scripts/04-build-wine.sh
DISPLAY=:0 "$KIT"/scripts/05-verify.sh
```

For Wine 10.14 use `patches/wine/` and `WINE_SRC=$WORK/wine-10.14` instead.

### 4.1 What each step does

| Step | Action | Notes |
| --- | --- | --- |
| 01 | Configure and build `clang;lld` with only the LoongArch target | Installs a `loongarch64-w64-mingw32-clang` wrapper that bakes in `--target` and `--sysroot` |
| 02 | Compile `crt0.S` → `crt2.o`, `empty.S` → `crtbegin.o`/`crtend.o`; generate stub import libraries | Stubs are 8-byte archives; real symbols come from the Wine build tree |
| 03 | rsync the toolchain to a remote host | Only needed when the build host differs from the run host |
| 04 | `configure` + `make` | `$TOOLCHAIN/bin` must be on `PATH`; `configure` finds the cross compiler by name |
| 05 | Exit-code and stdio tests, then `winecfg`/`notepad` window checks | Failures correspond to the two historical hangs |

---

## 5. Verification baseline

| Case | Pass criterion |
| --- | --- |
| `t_exit` | exits within 5 s, `rc=0` |
| `t_printf` | prints `A B S C` within 5 s, `rc=0` |
| `wineboot --init` | completes, prefix directory created |
| `wine cmd /c ver` | prints `Microsoft Windows 10.0.x` |
| `winecfg` | X top-level window appears within 8 s |
| `notepad` | same as above |

Measured on Loongson-3A5000 with Wine 11.16: `wineboot` returns 0,
`wine cmd /c ver` prints `Microsoft Windows 10.0.19045`,
`notepad` maps a 721×512 window and `winecfg` maps `Wine 设置` at 477×608.

### 5.1 Symptom → cause

| Symptom | Likely cause |
| --- | --- |
| `t_exit` hangs at 100 % CPU | `mainCRTStartup` did not preserve `$ra` (self-referencing return) |
| `t_printf` hangs | Program built without `-D_UCRT`; `FILE` layout mismatch |
| `wineboot` aborts with `double free or corruption` | `ntdll/unix/loader.c` path buffer sized from `/aarch64-windows` |
| `undefined symbol: __imp_*` when linking | Stub `lib*.a` used instead of `$WINE_BUILD/dlls/*/lib*.a` |
| `unable to find library -lcompiler-rt` | `COMPILER_RT_PE_LIBS` empty; `configure` not the patched one |

---

## 6. Supported versions

| Wine baseline | Patch set | Commits | Status |
| --- | --- | --- | --- |
| `wine-10.14` | `patches/wine/` | 11 | verified: windows, console tests, benchmarks |
| `wine-11.16` | `patches/wine-11.16/` | 21 | verified: build, install, `winecfg`/`notepad` |

Wine 11.16 additionally required: updated LDT prototypes, removal of the
duplicated `NtSetLdtEntries`, a generic SymCrypt path, disabling the C++ ABI
modules (`vcruntime140`, `msvcp140`, `concrt140`), the `__int128` branch in
`sqlite3`, quad-precision compiler-rt builtins, and the `loader.c` buffer fix.
See [MODIFICATIONS.md](MODIFICATIONS.md) §8.

---

## 7. Current limitations

- Background services busy-wait: `services`, `winedevice`, `rpcss`, `plugplay`
  each saturate a core while idle. **Fixed** in commit 21 (`setjmp`/`longjmp`
  around `pthread_exit`); the proper fix is emitting `.eh_frame` for PE modules
  and registering it with libgcc.
- `dlls/rsaenh` fails to link against `libtomcrypt.a` (relocation errors).
- C++ exceptions and the MSVC C++ ABI are unsupported; the related modules are
  disabled on loongarch64.
- 32-bit / WoW64 support has not been started.

---

## 8. References

- Full engineering log (Chinese): `../wine-loongarch编译问题记录.md`
- Per-commit change list: [MODIFICATIONS.md](MODIFICATIONS.md)
- Effort accounting: [CREDITS.md](CREDITS.md)

## 9. License

Scripts and documentation in this repository are provided under the MIT
License. Patches under `patches/` are derivative works of Wine (LGPL-2.1-or-later)
and LLVM (Apache-2.0 WITH LLVM-exception) and remain under their respective
upstream licenses.
