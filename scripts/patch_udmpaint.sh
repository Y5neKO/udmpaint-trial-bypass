#!/bin/bash
# =============================================================================
# UDMPAINT (CLIP STUDIO PAINT + Unicorn) 试用绕过 Patch 脚本
#
# 用法:
#   ./patch_udmpaint.sh apply     # 备份 + patch + 重签（默认）
#   ./patch_udmpaint.sh verify    # 校验所有 patch 点是否已应用
#   ./patch_udmpaint.sh restore   # 从备份恢复原版
#
# 环境变量:
#   APP     应用路径（默认 /Applications/Unicorn/PAINT/UDMPAINT.app）
#   BK_DIR  备份目录（默认 /tmp/udmpaint_backup）
#
# Patch 内容:
#   PaintActivation.app (arm64)  8 处: 30天判定x3 NOP + 次数判定x1 NOP + 回拨检测x5 NOP
#   CLIP STUDIO PAINT   (arm64)  2 处: 跳过激活器检查 tbnz->b
# =============================================================================
set -euo pipefail

APP="${APP:-/Applications/Unicorn/PAINT/UDMPAINT.app}"
BK_DIR="${BK_DIR:-/tmp/udmpaint_backup}"
MODE="${1:-apply}"

PA_BIN="${APP}/Contents/MacOS/PaintActivation.app/Contents/MacOS/PaintActivation"
MAIN_BIN="${APP}/Contents/MacOS/CLIP STUDIO PAINT"
PA_THIN="/tmp/udmpaint_pa_arm64"
MAIN_THIN="/tmp/udmpaint_main_arm64"

# ---- 备份 ----
do_backup() {
    if [ -f "${BK_DIR}/PaintActivation.orig" ] && [ -f "${BK_DIR}/CLIPSTUDIOPAINT.orig" ]; then
        echo "[备份] 已存在: ${BK_DIR}（跳过）"
    else
        mkdir -p "${BK_DIR}"
        cp "${PA_BIN}" "${BK_DIR}/PaintActivation.orig"
        cp "${MAIN_BIN}" "${BK_DIR}/CLIPSTUDIOPAINT.orig"
        echo "[备份] 原版已备份到 ${BK_DIR}"
    fi
}

# ---- 恢复 ----
do_restore() {
    if [ -f "${BK_DIR}/PaintActivation.orig" ]; then
        cp "${BK_DIR}/PaintActivation.orig" "${PA_BIN}" && echo "[恢复] PaintActivation <- 原版"
    else
        echo "[恢复] 跳过 PaintActivation（无备份）"
    fi
    if [ -f "${BK_DIR}/CLIPSTUDIOPAINT.orig" ]; then
        cp "${BK_DIR}/CLIPSTUDIOPAINT.orig" "${MAIN_BIN}" && echo "[恢复] 主程序 <- 原版"
    else
        echo "[恢复] 跳过主程序（无备份）"
    fi
    codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 && echo "[重签] adhoc 完成"
    echo "[恢复] 完成"
}

# ---- patch / verify 核心（python）----
patch_core() {
    local bin="$1" thin="$2" target="$3" mode="$4"
    python3 - "${bin}" "${thin}" "${target}" "${mode}" <<'PY'
import sys, subprocess, os, shutil

BIN, THIN, TARGET, MODE = sys.argv[1:5]

# target: "PA" 或 "MAIN"
PATCHES = {
  "PA": [
    (0x1554c, "cc020054", "1f2003d5", "30天 calculateTrialIs30Valid b.gt"),
    (0x18e84, "88020054", "1f2003d5", "次数 checkTrialIsValid b.hi"),
    (0x1a45c, "cc020054", "1f2003d5", "30天 calculateTrialIsValid b.gt"),
    (0x1a0dc, "84020054", "1f2003d5", "回拨 timerFireMethod local<BEGTM4"),
    (0x1a0e4, "44020054", "1f2003d5", "回拨 timerFireMethod local<RUNTM"),
    (0x1a0ec, "04020054", "1f2003d5", "回拨 timerFireMethod local<network"),
    (0x152b4, "44020054", "1f2003d5", "回拨 30Valid 路径 A"),
    (0x152bc, "04020054", "1f2003d5", "回拨 30Valid 路径 B"),
  ],
  "MAIN": [
    (0x15cf990, "a8060037", "35000014", "跳过激活器检查 tbnz->b"),
    (0x15cfa70, "68030037", "1b000014", "跳过二次检查 tbnz->b"),
  ],
}

name = "PaintActivation" if TARGET == "PA" else "CLIP STUDIO PAINT"
patches = PATCHES[TARGET]

# 取 arm64 slice
if os.path.exists(THIN):
    os.remove(THIN)
subprocess.run(["lipo", "-thin", "arm64", BIN, "-output", THIN], check=True)

data = bytearray(open(THIN, "rb").read())
all_applied = True
changed = 0

for off, orig, new, desc in patches:
    cur = bytes(data[off:off+4]).hex()
    if cur == new:
        print(f"  [=] 0x{off:x} 已patch: {desc}")
    elif cur == orig:
        if MODE == "apply":
            data[off:off+4] = bytes.fromhex(new)
            print(f"  [+] 0x{off:x} {orig}->{new}: {desc}")
            changed += 1
        else:
            all_applied = False
            print(f"  [-] 0x{off:x} 未patch: {desc}")
    else:
        print(f"  [!] 0x{off:x} 字节异常 {cur} (期望 {orig} 或 {new}): {desc}")
        sys.exit(1)

if MODE == "apply":
    if changed == 0:
        print(f"  [*] {name}: 全部已 patch，无需改动")
    else:
        open(THIN, "wb").write(bytes(data))
        # 合成回 fat 并替换
        x86 = THIN + ".x86_64"
        if os.path.exists(x86):
            os.remove(x86)
        subprocess.run(["lipo", "-thin", "x86_64", BIN, "-output", x86], check=True)
        newfat = THIN + ".newfat"
        subprocess.run(["lipo", "-create", THIN, x86, "-output", newfat], check=True)
        shutil.copy2(newfat, BIN)
        os.remove(x86); os.remove(newfat)
        print(f"  [*] {name}: patch 完成并已替换")
elif MODE == "verify":
    if all_applied:
        print(f"  [OK] {name}: 全部 patch 点已生效")
    else:
        print(f"  [FAIL] {name}: 存在未 patch 点")
        sys.exit(2)
PY
}

# ---- 主流程 ----
echo "=== UDMPAINT 试用绕过 Patch (${MODE}) ==="
echo "App: ${APP}"

case "${MODE}" in
    apply)
        do_backup
        echo "--- PaintActivation ---"
        patch_core "${PA_BIN}" "${PA_THIN}" "PA" "apply"
        echo "--- CLIP STUDIO PAINT ---"
        patch_core "${MAIN_BIN}" "${MAIN_THIN}" "MAIN" "apply"
        echo "--- 重签 ---"
        codesign --force --deep --sign - "${APP}" 2>&1 | tail -1 || true
        echo "[完成] patch 已应用 + adhoc 重签"
        ;;
    verify)
        echo "--- PaintActivation ---"
        patch_core "${PA_BIN}" "${PA_THIN}" "PA" "verify" || echo "[校验] PaintActivation 未全部 patch"
        echo "--- CLIP STUDIO PAINT ---"
        patch_core "${MAIN_BIN}" "${MAIN_THIN}" "MAIN" "verify" || echo "[校验] 主程序未全部 patch"
        echo "[校验] 完成"
        ;;
    restore)
        do_restore
        ;;
    *)
        echo "用法: $0 {apply|verify|restore}" >&2
        exit 1
        ;;
esac
