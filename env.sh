#!/usr/bin/env bash
# 统一路径与参数：所有脚本都应 source 本文件。
# 换机器时只需改 WORK（或事先 export 下列变量），脚本本身不用动。

set -euo pipefail

export WORK="${WORK:-$HOME/loongarch-wine}"

# 目标三元组
export TARGET="loongarch64-w64-mingw32"
export TARGET_TRIPLE="loongarch64-windows"

# 构建工具（系统 CMake 太老时指向源码引导出来的那份）
export CMAKE="${CMAKE:-cmake}"

# 源码与构建目录
export LLVM_SRC="${LLVM_SRC:-$WORK/llvm-project}"
export LLVM_BUILD="${LLVM_BUILD:-$WORK/build-llvm}"
export TOOLCHAIN="${TOOLCHAIN:-$WORK/toolchain}"
export SYSROOT="${SYSROOT:-$TOOLCHAIN/sysroot/$TARGET}"
export WINE_SRC="${WINE_SRC:-$WORK/wine-11.16}"
export WINE_BUILD="${WINE_BUILD:-$WORK/build-wine}"

# CRT 源码目录（工程自带 crt/，也可放到 $WORK/mingw64-loongarch64/crt）
export CRT_SRC="${CRT_SRC:-}"

# Wine 安装前缀与运行前缀
export WINE_INSTALL="${WINE_INSTALL:-/opt/winebuild/install}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-loongarch}"

# 联调目标机（03/05 脚本使用；留空表示本机即目标机）
export TARGET_HOST="${TARGET_HOST:-}"
export TARGET_DIR="${TARGET_DIR:-/data/opt/winebuild}"

export JOBS="${JOBS:-$(nproc)}"
export CC_PE="$TOOLCHAIN/bin/$TARGET-clang"
