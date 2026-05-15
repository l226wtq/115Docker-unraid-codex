#!/bin/bash
set +e

SKIP_PRIV_DROP=0
if [ "${1:-}" = "--skip-priv-drop" ]; then
    SKIP_PRIV_DROP=1
    shift
fi

SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")
export DISPLAY_WIDTH=${DISPLAY_WIDTH:-1366}
export DISPLAY_HEIGHT=${DISPLAY_HEIGHT:-768}
export PUID=${PUID:-99}
export PGID=${PGID:-100}
export UMASK=${UMASK:-000}
export DOWNLOAD_PERMISSION_FIX=${DOWNLOAD_PERMISSION_FIX:-1}
export DOWNLOAD_PERMISSION_FIX_INTERVAL=${DOWNLOAD_PERMISSION_FIX_INTERVAL:-30}
export DOWNLOAD_FILE_MODE=${DOWNLOAD_FILE_MODE:-666}
export DOWNLOAD_DIR_MODE=${DOWNLOAD_DIR_MODE:-777}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}

if ! umask "${UMASK}" 2>/dev/null; then
    echo "Warning: invalid UMASK '${UMASK}', falling back to 000."
    umask 000
fi

VNC_CONFIG_DIR="${XDG_CONFIG_HOME}/tigervnc"
LEGACY_VNC_DIR="${HOME}/.vnc"
VNC_PORT=$((5900 + ${DISPLAY#:}))
UI_JS_PATH="${NO_VNC_HOME}/app/ui.js"
COOKIE_FILE="/usr/local/115Cookie/worker.js"
RUN_USER_NAME=${RUN_USER_NAME:-appuser}
RUN_GROUP_NAME=${RUN_GROUP_NAME:-appgroup}

ensure_runtime_dirs() {
    mkdir -p "${VNC_CONFIG_DIR}" /etc/115 /opt/Downloads /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
}

cleanup_runtime_locks() {
    rm -rf /tmp/.X11-unix/X${DISPLAY#:} "/tmp/.X${DISPLAY#:}-lock" "${VNC_CONFIG_DIR}"/*.pid "${VNC_CONFIG_DIR}"/*.log
    rm -rf /etc/115/SingletonLock /etc/115/SingletonSocket /etc/115/SingletonCookie
}

cleanup_legacy_vnc_dir() {
    [ -d "${LEGACY_VNC_DIR}" ] || return

    rm -f "${LEGACY_VNC_DIR}/config" "${LEGACY_VNC_DIR}/passwd" "${LEGACY_VNC_DIR}"/*.pid "${LEGACY_VNC_DIR}"/*.log 2>/dev/null || true
    rmdir "${LEGACY_VNC_DIR}" 2>/dev/null || true
}

fix_download_permissions() {
    [ -d /opt/Downloads ] || return

    find /opt/Downloads -type d ! -perm -"${DOWNLOAD_DIR_MODE}" -exec chmod "${DOWNLOAD_DIR_MODE}" {} + 2>/dev/null || true
    find /opt/Downloads -type f ! -perm -"${DOWNLOAD_FILE_MODE}" -exec chmod "${DOWNLOAD_FILE_MODE}" {} + 2>/dev/null || true
}

start_download_permission_fix() {
    [ "${DOWNLOAD_PERMISSION_FIX}" = "1" ] || return

    fix_download_permissions
    (
        while true; do
            sleep "${DOWNLOAD_PERMISSION_FIX_INTERVAL}"
            fix_download_permissions
        done
    ) &
}

configure_cookie() {
    if [ ! -f "$COOKIE_FILE" ]; then
        return
    fi

    if [ ! -w "$COOKIE_FILE" ]; then
        echo "Warning: ${COOKIE_FILE} is not writable; cookie auto-login values were not updated."
        return
    fi

    EXPIRATION=$(date -d "+1 year" +%s)
    sed -i \
        -e "s|\(CID:\s*'\)[^']*'|\1$COOKIE_CID'|" \
        -e "s|\(SEID:\s*'\)[^']*'|\1$COOKIE_SEID'|" \
        -e "s|\(UID:\s*'\)[^']*'|\1$COOKIE_UID'|" \
        -e "s|\(KID:\s*'\)[^']*'|\1$COOKIE_KID'|" \
        -e "s|\(EXPIRATION_DATE:\s*\)[0-9]*|\1$EXPIRATION|" \
        "$COOKIE_FILE"
}

configure_novnc_auth() {
    if [ ! -f "${UI_JS_PATH}" ] || [ ! -w "${UI_JS_PATH}" ]; then
        return
    fi

    if [ -n "${PASSWORD}" ]; then
        sed -i "s/UI.initSetting('autoconnect', true);/UI.initSetting('autoconnect', false);/g" "${UI_JS_PATH}"
    else
        sed -i "s/UI.initSetting('autoconnect', false);/UI.initSetting('autoconnect', true);/g" "${UI_JS_PATH}"
        sed -i "s/getConfigVar('autoconnect', false)/getConfigVar('autoconnect', true)/g" "${UI_JS_PATH}"
    fi
}

prepare_root_permissions() {
    local group_name user_name

    if ! getent group "${PGID}" >/dev/null 2>&1; then
        groupadd -g "${PGID}" "${RUN_GROUP_NAME}" >/dev/null 2>&1 || true
    fi
    group_name=$(getent group "${PGID}" | cut -d: -f1)

    if ! getent passwd "${PUID}" >/dev/null 2>&1; then
        useradd -u "${PUID}" -g "${PGID}" -d "${HOME}" -s /bin/bash "${RUN_USER_NAME}" >/dev/null 2>&1 || true
    fi
    user_name=$(getent passwd "${PUID}" | cut -d: -f1)

    if [ -z "${user_name}" ]; then
        echo "Warning: unable to resolve uid ${PUID}; continuing as root."
        return 1
    fi

    chown "${PUID}:${PGID}" "${HOME}" /etc/115 /opt/Downloads 2>/dev/null || true
    chmod ug+rwX "${HOME}" /etc/115 /opt/Downloads "${XDG_CONFIG_HOME}" "${VNC_CONFIG_DIR}" 2>/dev/null || true
    chown -R "${PUID}:${PGID}" "${VNC_CONFIG_DIR}" "${HOME}/Desktop" /etc/115 2>/dev/null || true
    chmod -R ug+rwX "${VNC_CONFIG_DIR}" "${HOME}/Desktop" /etc/115 2>/dev/null || true
    [ -d /usr/local/115Cookie ] && chmod -R a+rwX /usr/local/115Cookie 2>/dev/null || true
    [ "${DOWNLOAD_PERMISSION_FIX}" = "1" ] && fix_download_permissions

    export RUN_AS_USER="${user_name}"
    export RUN_AS_GROUP="${group_name}"
}

drop_privileges_if_needed() {
    if [ "${SKIP_PRIV_DROP}" -eq 1 ] || [ "$(id -u)" -ne 0 ]; then
        return
    fi

    if [ "${PUID}" = "0" ] && [ "${PGID}" = "0" ]; then
        return
    fi

    prepare_root_permissions || return

    if command -v runuser >/dev/null 2>&1; then
        exec runuser -u "${RUN_AS_USER}" --preserve-environment -- "${SCRIPT_PATH}" --skip-priv-drop
    fi

    if command -v su >/dev/null 2>&1; then
        exec su -s /bin/bash -c "exec \"${SCRIPT_PATH}\" --skip-priv-drop" "${RUN_AS_USER}"
    fi

    if command -v setpriv >/dev/null 2>&1; then
        exec setpriv --reuid "${PUID}" --regid "${PGID}" --clear-groups "${SCRIPT_PATH}" --skip-priv-drop
    fi

    echo "Warning: no privilege-drop helper found; continuing as root."
}

ensure_runtime_dirs
cleanup_runtime_locks
cleanup_legacy_vnc_dir
configure_cookie
configure_novnc_auth
drop_privileges_if_needed
ensure_runtime_dirs
cleanup_runtime_locks
cleanup_legacy_vnc_dir
start_download_permission_fix

echo "geometry=${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" > "${VNC_CONFIG_DIR}/config"

if [ -n "${PASSWORD}" ]; then
    export PASSWD_PATH="${VNC_CONFIG_DIR}/passwd"
    echo "${PASSWORD}" | vncpasswd -f >"${PASSWD_PATH}"
    chmod 0600 "${PASSWD_PATH}"
    echo "securitytypes=VncAuth" >> "${VNC_CONFIG_DIR}/config"
    echo "PasswordFile=${PASSWD_PATH}" >> "${VNC_CONFIG_DIR}/config"
else
    echo "securitytypes=None" >> "${VNC_CONFIG_DIR}/config"
fi

echo "Starting noVNC on port ${WEB_PORT}..."
"${NO_VNC_HOME}"/utils/novnc_proxy --vnc localhost:${VNC_PORT} --listen ${WEB_PORT} &

echo "Starting VNC Server on ${DISPLAY}..."
/usr/libexec/vncserver ${DISPLAY} &

echo "Waiting for X Server..."
for i in {1..20}; do
    if [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
        echo "X Server is ready."
        break
    fi
    sleep 0.2
done

pcmanfm --desktop --profile default &

echo "Starting tint2..."
G_SLICE=always-malloc tint2 -c "$TINT2_CONF" &

echo "Starting 115 Browser..."
/usr/local/115Browser/115.sh
wait
