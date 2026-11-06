#!/usr/bin/env bash
# 步骤 5：冒烟验证。覆盖本次踩过的两类卡死 + 图形栈。
#
#   A. 退出码/CRT：程序跑完能退出（历史问题：$ra 自指 → 自旋）
#   B. 格式化输出：printf/fprintf 不挂（历史问题：UCRT/msvcrt FILE 混用）
#   C. 图形栈：winecfg / notepad 能映射出 X 窗口

source "$(dirname "$0")/../env.sh"

BIN="$WINE_BUILD"
[ -x "$BIN/wine" ] || BIN="$WINE_INSTALL/bin"
WS="$BIN/../server/wineserver"
[ -x "$WS" ] || WS="$(command -v wineserver)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export WINEPREFIX WINEDEBUG="${WINEDEBUG:--all}"

if [ ! -d "$WINEPREFIX" ]; then
  "$BIN/wine" wineboot --init >/dev/null 2>&1 || true
fi

build_test() { # $1=name $2=source
  "$CC_PE" -D_UCRT -o "$TMP/$1.exe" "$2" \
    "$BIN/dlls/ucrtbase/libucrtbase.a" \
    "$BIN/dlls/msvcrt/libmsvcrt.a" \
    "$BIN/dlls/kernel32/libkernel32.a"
}

cat > "$TMP/t_exit.c" <<'EOF'
int main(void) { return 0; }
EOF

cat > "$TMP/t_printf.c" <<'EOF'
#include <stdio.h>
int main(void) {
    printf("A\n"); printf("B\n");
    fprintf(stderr, "S\n");
    printf("C\n"); fflush(stdout);
    return 0;
}
EOF

build_test t_exit "$TMP/t_exit.c"
build_test t_printf "$TMP/t_printf.c"

echo "== A/B 用例（5 秒超时，非 0 退出或超时即失败）"
for t in t_exit t_printf; do
  timeout 5 "$BIN/wine" "$TMP/$t.exe" > "$TMP/$t.out" 2>&1
  echo "   $t rc=$? out=$(tr '\n' ' ' < "$TMP/$t.out")"
done

echo "== C 图形栈（需要 DISPLAY）"
if [ -n "${DISPLAY:-}" ]; then
  "$BIN/wine" "$BIN/programs/winecfg/loongarch64-windows/winecfg.exe" >/dev/null 2>&1 &
  sleep 8
  xwininfo -root -tree 2>/dev/null | grep -m2 -i "wine\|设置" || echo "   未找到窗口"
  "$WS" -k 2>/dev/null || true
else
  echo "   跳过：未设置 DISPLAY"
fi

echo "== 验证结束"
