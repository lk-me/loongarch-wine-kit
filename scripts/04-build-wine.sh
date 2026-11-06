#!/usr/bin/env bash
# 步骤 4：在 loongarch64 Linux 上构建 Wine（PE 侧用步骤 1 的 clang 工具链）。
#
# 注意：
#   * Wine 含 unix 侧代码，构建机必须是 loongarch64 Linux；
#   * 需要先把 $TOOLCHAIN/bin 放进 PATH，configure 靠名字找 cross CC；
#   * 必须使用 MINGW sysroot 里的 crt2.o（步骤 2）。

source "$(dirname "$0")/../env.sh"

export PATH="$TOOLCHAIN/bin:$PATH"
mkdir -p "$WINE_BUILD"

if [ ! -f "$WINE_BUILD/config.status" ]; then
  ( cd "$WINE_BUILD" && "$WINE_SRC/configure" \
      --prefix="$WINE_INSTALL" \
      --disable-tests \
      --without-alsa --without-pulse --without-oss \
      --without-cups --without-gnutls --without-udev \
      --without-usb --without-vulkan --without-gstreamer \
      --without-pcsclite --without-sane --without-v4l2 )
fi

# 已知坑（源码层已修，见 MODIFICATIONS.md 第 5 节）：COMPILER_RT_PE_LIBS 为空时，
# programs/xcopy 链接会报 "unable to find library -lcompiler-rt"。
# 正常情况下 configure 会给出 "compiler-rt"；只有补丁没打全或 configure 过期才会为空。
if grep -q '^COMPILER_RT_PE_LIBS *= *$' "$WINE_BUILD/Makefile"; then
  CRT_LIB="$WINE_BUILD/libs/compiler-rt/loongarch64-windows/libcompiler-rt.a"
  if [ -f "$CRT_LIB" ]; then
    sed -i "s|^COMPILER_RT_PE_LIBS *= *\$|COMPILER_RT_PE_LIBS = $CRT_LIB|" "$WINE_BUILD/Makefile"
    echo "!! COMPILER_RT_PE_LIBS 为空，已临时修正；请检查 configure 是否为补丁后的版本"
    echo "!! （赋值结尾不能有空格，否则 makedep 名称匹配失败）"
  else
    echo "!! 未找到 $CRT_LIB，跳过；若 xcopy 链接失败请检查该项"
  fi
fi

make -C "$WINE_BUILD" -j "$JOBS"

echo "== 构建完成："
ls -l "$WINE_BUILD/loader/wine" "$WINE_BUILD/dlls/winex11.drv/winex11.so" 2>/dev/null || true
