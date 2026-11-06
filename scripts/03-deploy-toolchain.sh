#!/usr/bin/env bash
# 步骤 3：把工具链与 sysroot 部署到目标机（TARGET_HOST 为空则跳过）。
#
# 目标机需具备：gcc/make/flex/bison/pkg-config、python3、Xorg 或 xorg 开发库。
# 部署后目标机应能看到 $TARGET_DIR/toolchain/bin/loongarch64-w64-mingw32-clang。

source "$(dirname "$0")/../env.sh"

if [ -z "$TARGET_HOST" ]; then
  echo "TARGET_HOST 为空，按本机为目标机处理，跳过 rsync。"
  exit 0
fi

ssh "$TARGET_HOST" "mkdir -p '$TARGET_DIR'"
rsync -a --delete "$TOOLCHAIN/" "$TARGET_HOST:$TARGET_DIR/toolchain/"
rsync -a "$WORK/mingw64-loongarch64/" "$TARGET_HOST:$TARGET_DIR/mingw64-loongarch64/"

ssh "$TARGET_HOST" "'$TARGET_DIR/toolchain/bin/$TARGET-clang' --version | head -1"
echo "== 部署完成"
