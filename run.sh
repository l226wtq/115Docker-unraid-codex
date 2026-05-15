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

VNC_PORT=$((5900 + ${DISPLAY#:}))
UI_JS_PATH="${NO_VNC_HOME}/app/ui.js"
COOKIE_FILE="/usr/local/115Cookie/worker.js"
RUN_USER_NAME=${RUN_USER_NAME:-appuser}
RUN_GROUP_NAME=${RUN_GROUP_NAME:-appgroup}

ensure_runtime_dirs() {
    mkdir -p "${HOME}/.vnc" /etc/115 /opt/Downloads
}

cleanup_runtime_locks() {
    rm -rf /tmp/.X11-unix/X${DISPLAY#:} "/tmp/.X${DISPLAY#:}-lock" "${HOME}"/.vnc/*.pid "${HOME}"/.vnc/*.log
    rm -rf /etc/115/SingletonLock /etc/115/SingletonSocket /etc/115/SingletonCookie
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
    chmod ug+rwX "${HOME}" /etc/115 /opt/Downloads 2>/dev/null || true
    chown -R "${PUID}:${PGID}" "${HOME}/.vnc" "${HOME}/Desktop" /etc/115 2>/dev/null || true
    chmod -R ug+rwX "${HOME}/.vnc" "${HOME}/Desktop" /etc/115 2>/dev/null || true
    [ -d /usr/local/115Cookie ] && chmod -R a+rwX /usr/local/115Cookie 2>/dev/null || true

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
configure_cookie
configure_novnc_auth
drop_privileges_if_needed
ensure_runtime_dirs
cleanup_runtime_locks

echo "geometry=${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" > "${HOME}/.vnc/config"

if [ -n "${PASSWORD}" ]; then
    export PASSWD_PATH="${HOME}/.vnc/passwd"
    echo "${PASSWORD}" | vncpasswd -f >"${PASSWD_PATH}"
    chmod 0600 "${PASSWD_PATH}"
    echo "securitytypes=VncAuth" >> "${HOME}/.vnc/config"
else
    echo "securitytypes=None" >> "${HOME}/.vnc/config"
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
