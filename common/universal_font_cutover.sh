#!/system/bin/sh
# Phase 9 controlled production cutover controller.
# Official single-font switches try Universal first and fall back to the existing
# production switcher without ever rewriting the current boot's live payload.
set +e

MODDIR="${MODDIR:-${MODULE_DIR:-/data/adb/modules/LuoShu}}"
MODULE_DIR="$MODDIR"
CONFIG_DIR="${CONFIG_DIR:-$MODDIR/config}"
PUBLIC_DIR="${LUOSHU_PUBLIC_DIR:-/sdcard/LuoShu}"
LEGACY_SWITCH="$MODDIR/common/legacy_v14_4/font_switch_safe.sh"
DEPLOYMENT="$MODDIR/common/universal_font_deployment.sh"
PLAN_BRIDGE="$MODDIR/common/universal_font_plan.sh"
ROUTE_BRIDGE="$MODDIR/common/minimal_xml_router.sh"
COMPILER_BRIDGE="$MODDIR/common/universal_font_compiler.sh"
GATE="$MODDIR/common/universal_font_cutover_gate.py"
PYROOT="$MODDIR/common/python"
PYBIN="$PYROOT/bin/luoshu-python"
CUTOVER_STATE="$CONFIG_DIR/universal-font-cutover.conf"
LOG_FILE="$MODDIR/logs/fontswitch.log"
PROGRESS_FILE="${LUOSHU_SWITCH_PROGRESS_FILE:-}"

_uc_log() {
    mkdir -p "$MODDIR/logs" 2>/dev/null || true
    printf '[%s] [CUTOVER] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

_uc_progress() {
    _ucp_percent="$1"; shift
    [ -n "$PROGRESS_FILE" ] || return 0
    {
        printf 'percent=%s\n' "$_ucp_percent"
        printf 'message=%s\n' "$*"
    } > "$PROGRESS_FILE.tmp.$$" 2>/dev/null && mv -f "$PROGRESS_FILE.tmp.$$" "$PROGRESS_FILE" 2>/dev/null || true
}

_uc_python() {
    if [ -n "${LUOSHU_PYTHON:-}" ]; then
        "$LUOSHU_PYTHON" "$@"
        return $?
    fi
    [ -x "$PYBIN" ] || return 127
    PYTHONHOME="$PYROOT" \
    PYTHONPATH="$MODDIR/common:$PYROOT/lib/python3.14:$PYROOT/lib/python3.14/site-packages" \
    LD_LIBRARY_PATH="$PYROOT/lib:$PYROOT/lib/python3.14/lib-dynload${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$PYBIN" "$@"
}

_uc_write_state() {
    _ucs_state="$1"; _ucs_font="$2"; _ucs_decision="$3"; _ucs_reason="$4"
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    {
        printf 'state=%s\n' "$_ucs_state"
        printf 'font=%s\n' "$_ucs_font"
        printf 'decision=%s\n' "$_ucs_decision"
        printf 'reason=%s\n' "$_ucs_reason"
        printf 'time=%s\n' "$(date +%s 2>/dev/null || echo 0)"
    } > "$CUTOVER_STATE.tmp.$$" 2>/dev/null && mv -f "$CUTOVER_STATE.tmp.$$" "$CUTOVER_STATE" 2>/dev/null || true
    chmod 0644 "$CUTOVER_STATE" 2>/dev/null || true
}

_uc_cleanup_universal_next() {
    rm -f "$CONFIG_DIR/universal-font-next.conf" 2>/dev/null || true
    # A switch request supersedes any previously queued next-boot payload.
    rm -rf "$MODDIR/.luoshu-payload-next" "$MODDIR"/.luoshu-payload-next.stage.* 2>/dev/null || true
}

_uc_legacy() {
    _ucl_font="$1"; _ucl_reason="$2"
    _uc_log "legacy fallback font=$_ucl_font reason=$_ucl_reason"
    _uc_write_state fallback "$_ucl_font" legacy "$_ucl_reason"
    _uc_progress 25 "通用引擎未接管，正在使用兼容切换路径"
    _uc_cleanup_universal_next
    [ -f "$LEGACY_SWITCH" ] || {
        printf '{"status":"error","message":"缺少兼容字体切换核心"}\n'
        return 1
    }
    MODDIR="$MODDIR" MODULE_DIR="$MODDIR" LUOSHU_PUBLIC_DIR="$PUBLIC_DIR" \
        sh "$LEGACY_SWITCH" action switch "$_ucl_font"
}

_uc_precondition() {
    [ -s "$CONFIG_DIR/device_font_topology.json" ] || return 1
    [ -s "$CONFIG_DIR/device_font_roles.json" ] || return 1
    [ -f "$DEPLOYMENT" ] || return 1
    [ -f "$GATE" ] || return 1
    [ -f "$PLAN_BRIDGE" ] || return 1
    [ -f "$ROUTE_BRIDGE" ] || return 1
    [ -f "$COMPILER_BRIDGE" ] || return 1
    return 0
}

_uc_paths() {
    _ucx_font="$1"
    UC_PLAN=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$PLAN_BRIDGE" path "$_ucx_font") || return 1
    UC_ROUTE=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$ROUTE_BRIDGE" path "$_ucx_font") || return 1
    UC_ARTIFACTS=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$COMPILER_BRIDGE" manifest "$_ucx_font") || return 1
    UC_DEPLOYMENT=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$DEPLOYMENT" manifest "$_ucx_font") || return 1
    UC_PAYLOAD=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$DEPLOYMENT" payload "$_ucx_font") || return 1
    [ -s "$UC_PLAN" ] && [ -s "$UC_ROUTE" ] && [ -s "$UC_ARTIFACTS" ] && [ -s "$UC_DEPLOYMENT" ] && [ -d "$UC_PAYLOAD" ]
}

_uc_switch() {
    _uc_font="$1"
    [ -n "$_uc_font" ] || { printf '{"status":"error","message":"未指定字体"}\n'; return 1; }

    # System default and composite temporary families stay on the proven legacy
    # production path during controlled rollout.
    if [ "$_uc_font" = default ]; then
        _uc_legacy "$_uc_font" default-font
        return $?
    fi
    if [ -n "${LUOSHU_REAL_MODDIR:-}" ]; then
        _uc_legacy "$_uc_font" composite-runtime
        return $?
    fi
    case "$_uc_font" in
        mix|LuoShuAutoMix|LuoShuMix*) _uc_legacy "$_uc_font" composite-family; return $? ;;
    esac

    if ! _uc_precondition; then
        _uc_legacy "$_uc_font" universal-precondition-missing
        return $?
    fi

    _uc_write_state preparing "$_uc_font" universal preparing
    _uc_progress 8 "通用引擎正在分析设备字体拓扑"
    _uc_log "universal prepare start font=$_uc_font"
    _uc_prepare_output=$(MODDIR="$MODDIR" MODULE_DIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" \
        LUOSHU_PUBLIC_DIR="$PUBLIC_DIR" sh "$DEPLOYMENT" prepare "$_uc_font" 2>&1)
    _uc_prepare_rc=$?
    if [ "$_uc_prepare_rc" -ne 0 ]; then
        _uc_log "universal prepare failed font=$_uc_font rc=$_uc_prepare_rc output=$(printf '%s' "$_uc_prepare_output" | tail -c 600)"
        _uc_legacy "$_uc_font" universal-prepare-failed
        return $?
    fi

    _uc_progress 72 "正在检查正式接管安全条件"
    if ! _uc_paths "$_uc_font"; then
        _uc_legacy "$_uc_font" universal-artifacts-missing
        return $?
    fi

    _uc_gate_output=$(_uc_python "$GATE" \
        --font-plan "$UC_PLAN" \
        --route-plan "$UC_ROUTE" \
        --artifact-manifest "$UC_ARTIFACTS" \
        --deployment "$UC_DEPLOYMENT" \
        --payload-root "$UC_PAYLOAD" 2>&1)
    _uc_gate_rc=$?
    _uc_log "gate font=$_uc_font rc=$_uc_gate_rc result=$_uc_gate_output"
    if [ "$_uc_gate_rc" -ne 0 ] || ! printf '%s' "$_uc_gate_output" | grep -q '"eligible":true'; then
        _uc_legacy "$_uc_font" universal-readiness-gate-rejected
        return $?
    fi

    _uc_progress 88 "通用引擎验证通过，正在准备下一次启动"
    _uc_stage_output=$(MODDIR="$MODDIR" MODULE_DIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" \
        LUOSHU_PUBLIC_DIR="$PUBLIC_DIR" sh "$DEPLOYMENT" stage-prepared "$_uc_font" 2>&1)
    _uc_stage_rc=$?
    if [ "$_uc_stage_rc" -ne 0 ] || ! printf '%s' "$_uc_stage_output" | grep -q '"status":"ok"'; then
        _uc_log "universal stage failed font=$_uc_font rc=$_uc_stage_rc output=$_uc_stage_output"
        _uc_legacy "$_uc_font" universal-stage-failed
        return $?
    fi

    _uc_write_state staged "$_uc_font" universal ready-next-boot
    _uc_progress 96 "通用字体负载已准备，完整重启后自动验收"
    printf '%s\n' "$_uc_stage_output"
    return 0
}

case "${1:-switch}" in
    switch) _uc_switch "${2:-}" ;;
    status)
        if [ -s "$CUTOVER_STATE" ]; then cat "$CUTOVER_STATE"
        else printf 'state=idle\ndecision=none\n'
        fi
        ;;
    *) echo "Usage: $0 {switch|status} <font-family>" >&2; exit 2 ;;
esac
