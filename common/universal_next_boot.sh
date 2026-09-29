#!/system/bin/sh
# Phase 7 universal deployment next-boot activation.
# Swaps only a previously validated private payload. It does not compile fonts.
set +e

_ufnb_module() {
    printf '%s\n' "${MODULE_DIR:-${MODDIR:-/data/adb/modules/LuoShu}}"
}

_ufnb_value() {
    sed -n "s/^${2}=//p" "$1" 2>/dev/null | head -n1 | tr -d '\r\n'
}

_ufnb_log() {
    _ufnb_mod=$(_ufnb_module)
    mkdir -p "$_ufnb_mod/logs" 2>/dev/null || true
    printf '[%s] [UNIVERSAL-NEXT] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" "$*" >> "$_ufnb_mod/logs/fontswitch.log" 2>/dev/null || true
}

_ufnb_python() {
    if [ -n "${LUOSHU_PYTHON:-}" ]; then
        "$LUOSHU_PYTHON" "$@"
        return $?
    fi
    _ufnb_mod=$(_ufnb_module)
    _ufnb_root="$_ufnb_mod/common/python"
    _ufnb_bin="$_ufnb_root/bin/luoshu-python"
    [ -x "$_ufnb_bin" ] || return 127
    PYTHONHOME="$_ufnb_root" \
    PYTHONPATH="$_ufnb_mod/common:$_ufnb_root/lib/python3.14:$_ufnb_root/lib/python3.14/site-packages" \
    LD_LIBRARY_PATH="$_ufnb_root/lib:$_ufnb_root/lib/python3.14/lib-dynload${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$_ufnb_bin" "$@"
}

_ufnb_manifest_value() {
    _ufnb_manifest="$1"
    _ufnb_key="$2"
    _ufnb_python - "$_ufnb_manifest" "$_ufnb_key" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding="utf-8"))
v=p.get(sys.argv[2],"")
print(v if isinstance(v,(str,int,float)) else "")
PY
}

_ufnb_restore_file() {
    _ufnb_backup="$1"; _ufnb_target="$2"
    rm -f "$_ufnb_target" 2>/dev/null || true
    [ -f "$_ufnb_backup" ] && cp -fp "$_ufnb_backup" "$_ufnb_target" 2>/dev/null || true
}

universal_font_next_boot_activate() {
    _ufnb_mod=$(_ufnb_module)
    _ufnb_cfg="$_ufnb_mod/config"
    _ufnb_state="$_ufnb_cfg/universal-font-next.conf"
    _ufnb_next="$_ufnb_mod/.luoshu-payload-next"
    _ufnb_live="$_ufnb_mod/.luoshu-payload"
    [ -s "$_ufnb_state" ] && [ -d "$_ufnb_next" ] || return 2

    _ufnb_font=$(_ufnb_value "$_ufnb_state" font)
    _ufnb_id=$(_ufnb_value "$_ufnb_state" deploymentId)
    _ufnb_digest=$(_ufnb_value "$_ufnb_state" payloadDigest)
    _ufnb_manifest="$_ufnb_next/.luoshu-runtime/deployment/deployment.json"
    [ -n "$_ufnb_font" ] && [ -n "$_ufnb_id" ] && [ -n "$_ufnb_digest" ] && [ -s "$_ufnb_manifest" ] || return 1

    _ufnb_deployer="$_ufnb_mod/common/universal_font_deployment.py"
    [ -f "$_ufnb_deployer" ] || return 1
    _ufnb_python "$_ufnb_deployer" --payload-root "$_ufnb_next" --validate-payload-only "$_ufnb_manifest" >/dev/null 2>&1 || {
        _ufnb_log "staged payload validation failed"
        return 1
    }
    [ "$(_ufnb_manifest_value "$_ufnb_manifest" deploymentId)" = "$_ufnb_id" ] || return 1
    [ "$(_ufnb_manifest_value "$_ufnb_manifest" payloadDigest)" = "$_ufnb_digest" ] || return 1

    _ufnb_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r\n')
    [ -n "$_ufnb_boot" ] || _ufnb_boot="$(date +%s 2>/dev/null || echo 0)-$$"
    _ufnb_retired_root="$_ufnb_mod/.luoshu-retired"
    _ufnb_retired="$_ufnb_retired_root/universal-${_ufnb_boot}"
    _ufnb_backup="$_ufnb_cfg/.universal-next-backup.$$"
    mkdir -p "$_ufnb_retired_root" "$_ufnb_backup" 2>/dev/null || return 1
    [ ! -f "$_ufnb_cfg/universal-font-runtime.conf" ] || cp -fp "$_ufnb_cfg/universal-font-runtime.conf" "$_ufnb_backup/runtime.conf" 2>/dev/null || true
    [ ! -f "$_ufnb_cfg/font_runtime_legacy_v14_4.conf" ] || cp -fp "$_ufnb_cfg/font_runtime_legacy_v14_4.conf" "$_ufnb_backup/legacy.conf" 2>/dev/null || true
    [ ! -f "$_ufnb_cfg/active_font.conf" ] || cp -fp "$_ufnb_cfg/active_font.conf" "$_ufnb_backup/active.conf" 2>/dev/null || true
    rm -rf "$_ufnb_retired" 2>/dev/null || true

    if [ -d "$_ufnb_live" ]; then
        mv "$_ufnb_live" "$_ufnb_retired" 2>/dev/null || { rm -rf "$_ufnb_backup"; return 1; }
    fi
    if ! mv "$_ufnb_next" "$_ufnb_live" 2>/dev/null; then
        [ ! -d "$_ufnb_retired" ] || mv "$_ufnb_retired" "$_ufnb_live" 2>/dev/null || true
        rm -rf "$_ufnb_backup" 2>/dev/null || true
        return 1
    fi

    _ufnb_runtime="$_ufnb_cfg/universal-font-runtime.conf"
    {
        printf 'state=active\n'
        printf 'pipeline=universal-font-deployment-v1\n'
        printf 'font=%s\n' "$_ufnb_font"
        printf 'deploymentId=%s\n' "$_ufnb_id"
        printf 'payloadDigest=%s\n' "$_ufnb_digest"
        printf 'bootId=%s\n' "$_ufnb_boot"
        printf 'time=%s\n' "$(date +%s 2>/dev/null || echo 0)"
    } > "$_ufnb_runtime.tmp.$$" 2>/dev/null && mv -f "$_ufnb_runtime.tmp.$$" "$_ufnb_runtime" 2>/dev/null || {
        rm -rf "$_ufnb_live" 2>/dev/null || true
        [ ! -d "$_ufnb_retired" ] || mv "$_ufnb_retired" "$_ufnb_live" 2>/dev/null || true
        _ufnb_restore_file "$_ufnb_backup/runtime.conf" "$_ufnb_cfg/universal-font-runtime.conf"
        _ufnb_restore_file "$_ufnb_backup/legacy.conf" "$_ufnb_cfg/font_runtime_legacy_v14_4.conf"
        _ufnb_restore_file "$_ufnb_backup/active.conf" "$_ufnb_cfg/active_font.conf"
        rm -rf "$_ufnb_backup" 2>/dev/null || true
        return 1
    }
    chmod 0600 "$_ufnb_runtime" 2>/dev/null || true
    rm -f "$_ufnb_cfg/font_runtime_legacy_v14_4.conf" 2>/dev/null || true
    printf '%s\n' "$_ufnb_font" > "$_ufnb_cfg/active_font.conf" 2>/dev/null || true
    chmod 0644 "$_ufnb_cfg/active_font.conf" 2>/dev/null || true
    {
        printf 'font=%s\n' "$_ufnb_font"
        printf 'deploymentId=%s\n' "$_ufnb_id"
        printf 'payloadDigest=%s\n' "$_ufnb_digest"
        printf 'retired=%s\n' "$_ufnb_retired"
        printf 'bootId=%s\n' "$_ufnb_boot"
    } > "$_ufnb_cfg/universal-font-activated.conf.tmp.$$" 2>/dev/null && \
        mv -f "$_ufnb_cfg/universal-font-activated.conf.tmp.$$" "$_ufnb_cfg/universal-font-activated.conf" 2>/dev/null || true
    rm -f "$_ufnb_state" 2>/dev/null || true
    rm -rf "$_ufnb_backup" 2>/dev/null || true
    _ufnb_log "activated deployment=$_ufnb_id font=$_ufnb_font retired=$_ufnb_retired"
    return 0
}
