#!/system/bin/sh
# LuoShu Phase 7 backend-neutral deployment bridge.
# Prepares private payloads. The normal font-switch path does not call stage-next yet.
set +e

MODDIR="${MODDIR:-${MODULE_DIR:-/data/adb/modules/LuoShu}}"
MODULE_DIR="$MODDIR"
CONFIG_DIR="${CONFIG_DIR:-$MODDIR/config}"
DEPLOYER="$MODDIR/common/universal_font_deployment.py"
COMPILER_BRIDGE="$MODDIR/common/universal_font_compiler.sh"
PLAN_BRIDGE="$MODDIR/common/universal_font_plan.sh"
ROUTE_BRIDGE="$MODDIR/common/minimal_xml_router.sh"
DEPLOY_ROOT="$CONFIG_DIR/universal-font-deployments"
PYROOT="$MODDIR/common/python"
PYBIN="$PYROOT/bin/luoshu-python"

_ud_exec() {
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

_ud_family_key() {
    _udk_family="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$_udk_family" | sha256sum | awk '{print substr($1,1,24)}'
    elif command -v busybox >/dev/null 2>&1; then
        printf '%s' "$_udk_family" | busybox sha256sum | awk '{print substr($1,1,24)}'
    else
        printf '%s' "$_udk_family" | cksum | awk '{print $1 "-" $2}'
    fi
}

_ud_dir() {
    _udd_key=$(_ud_family_key "$1") || return 1
    printf '%s/%s\n' "$DEPLOY_ROOT" "$_udd_key"
}

_ud_manifest() {
    _udm_dir=$(_ud_dir "$1") || return 1
    printf '%s/deployment.json\n' "$_udm_dir"
}

_ud_payload() {
    _udp_dir=$(_ud_dir "$1") || return 1
    printf '%s/payload\n' "$_udp_dir"
}

_ud_upstream_paths() {
    _udu_family="$1"
    UD_FONT_PLAN=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$PLAN_BRIDGE" path "$_udu_family") || return 1
    UD_ROUTE_PLAN=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$ROUTE_BRIDGE" path "$_udu_family") || return 1
    UD_ARTIFACT_MANIFEST=$(MODDIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" sh "$COMPILER_BRIDGE" manifest "$_udu_family") || return 1
    [ -s "$UD_FONT_PLAN" ] && [ -s "$UD_ROUTE_PLAN" ] && [ -s "$UD_ARTIFACT_MANIFEST" ]
}

_ud_prepare() {
    _udp_family="$1"
    [ -n "$_udp_family" ] || { printf '{"status":"error","message":"未指定字体家族"}\n'; return 1; }
    [ -f "$DEPLOYER" ] || { printf '{"status":"error","message":"Universal Deployment 组件不可用"}\n'; return 1; }

    _udp_compile=$(MODDIR="$MODDIR" MODULE_DIR="$MODDIR" CONFIG_DIR="$CONFIG_DIR" \
        sh "$COMPILER_BRIDGE" compile "$_udp_family" 2>&1)
    _udp_rc=$?
    [ "$_udp_rc" -eq 0 ] || { printf '%s\n' "$_udp_compile"; return "$_udp_rc"; }

    _ud_upstream_paths "$_udp_family" || {
        printf '{"status":"error","message":"Phase 4/5/6 产物不完整"}\n'
        return 1
    }
    _udp_dir=$(_ud_dir "$_udp_family") || return 1
    _udp_manifest=$(_ud_manifest "$_udp_family") || return 1
    _udp_payload=$(_ud_payload "$_udp_family") || return 1
    rm -rf "$_udp_dir" 2>/dev/null || true
    mkdir -p "$_udp_dir" 2>/dev/null || return 1

    _ud_exec "$DEPLOYER" \
        --font-plan "$UD_FONT_PLAN" \
        --route-plan "$UD_ROUTE_PLAN" \
        --artifact-manifest "$UD_ARTIFACT_MANIFEST" \
        --payload-root "$_udp_payload" \
        --manifest "$_udp_manifest"
}

_ud_validate() {
    _udv_family="$1"
    _ud_upstream_paths "$_udv_family" || return 1
    _udv_manifest=$(_ud_manifest "$_udv_family") || return 1
    _udv_payload=$(_ud_payload "$_udv_family") || return 1
    [ -s "$_udv_manifest" ] && [ -d "$_udv_payload" ] || return 1
    _ud_exec "$DEPLOYER" \
        --font-plan "$UD_FONT_PLAN" \
        --route-plan "$UD_ROUTE_PLAN" \
        --artifact-manifest "$UD_ARTIFACT_MANIFEST" \
        --payload-root "$_udv_payload" \
        --validate "$_udv_manifest"
}

_ud_stage_next() {
    _uds_family="$1"
    _ud_prepare "$_uds_family" >/dev/null || return $?
    _uds_manifest=$(_ud_manifest "$_uds_family") || return 1
    _uds_payload=$(_ud_payload "$_uds_family") || return 1
    _ud_validate "$_uds_family" >/dev/null || return 1

    _uds_id=$(sed -n 's/.*"deploymentId":[[:space:]]*"\([^"]*\)".*/\1/p' "$_uds_manifest" 2>/dev/null | head -n1)
    _uds_digest=$(sed -n 's/.*"payloadDigest":[[:space:]]*"\([^"]*\)".*/\1/p' "$_uds_manifest" 2>/dev/null | head -n1)
    [ -n "$_uds_id" ] && [ -n "$_uds_digest" ] || {
        # Pretty JSON normally places values on dedicated lines; Python is the
        # authoritative parser when sed cannot read them.
        _uds_values=$(_ud_exec - "$_uds_manifest" <<'PY'
import json, sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
print(p.get('deploymentId',''))
print(p.get('payloadDigest',''))
PY
)
        _uds_id=$(printf '%s\n' "$_uds_values" | sed -n '1p')
        _uds_digest=$(printf '%s\n' "$_uds_values" | sed -n '2p')
    }
    [ -n "$_uds_id" ] && [ -n "$_uds_digest" ] || return 1

    _uds_next="$MODDIR/.luoshu-payload-next"
    _uds_stage="$MODDIR/.luoshu-payload-next.stage.$$"
    rm -rf "$_uds_stage" 2>/dev/null || true
    mkdir -p "$_uds_stage" "$CONFIG_DIR" 2>/dev/null || return 1
    cp -af "$_uds_payload/." "$_uds_stage/" 2>/dev/null || {
        rm -rf "$_uds_stage" 2>/dev/null || true
        return 1
    }
    rm -rf "$_uds_next" 2>/dev/null || true
    mv "$_uds_stage" "$_uds_next" 2>/dev/null || {
        rm -rf "$_uds_stage" 2>/dev/null || true
        return 1
    }
    _uds_state="$CONFIG_DIR/universal-font-next.conf"
    {
        printf 'font=%s\n' "$_uds_family"
        printf 'deploymentId=%s\n' "$_uds_id"
        printf 'payloadDigest=%s\n' "$_uds_digest"
        printf 'time=%s\n' "$(date +%s 2>/dev/null || echo 0)"
    } > "$_uds_state.tmp.$$" 2>/dev/null && mv -f "$_uds_state.tmp.$$" "$_uds_state" 2>/dev/null || return 1
    chmod 0600 "$_uds_state" 2>/dev/null || true
    printf '{"status":"ok","state":"staged-next-boot","deploymentId":"%s"}\n' "$_uds_id"
}

case "${1:-prepare}" in
    prepare|build|refresh) _ud_prepare "${2:-}" ;;
    validate) _ud_validate "${2:-}" ;;
    manifest|path) _ud_manifest "${2:-}" ;;
    payload) _ud_payload "${2:-}" ;;
    stage-next) _ud_stage_next "${2:-}" ;;
    *)
        echo "Usage: $0 {prepare|validate|manifest|payload|stage-next} <font-family>" >&2
        exit 2
        ;;
esac
