# lib/web/handlers.sh — handlers RPC (un handler por método del contrato).
# Leen RPC_REQUEST_PARAMS y RPC_SESSION_UID/USER; llaman a lib/api/ y arman
# JSON con jq. No arman SQL, no repiten la validación de capas, no ven tokens
# completos (el layer RPC ya validó la sesión de los métodos privados).

[[ -n "${_WEB_HANDLERS_LOADED:-}" ]] && return 0
declare -g _WEB_HANDLERS_LOADED=1

if [[ -z "${HTTP_STATIC_PATH:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Método público de humo.
rpc_handle_saludar() {
    rpc_success "$(jq -nc --arg s 'Saludos desde el servidor en bash!' '$s')"
}

# @brief auth.register (público): alta con hash, sin texto plano.
# @params {username, password}
# @result {uid, username}
rpc_handle_auth_register() {
    local user pass out rc=0 uid

    if ! jq -e '(.username | type == "string") and (.password | type == "string")' \
        >/dev/null 2>&1 <<<"$RPC_REQUEST_PARAMS"; then
        rpc_invalid_params "username y password deben ser strings."
        return 0
    fi
    user="$(jq -r '.username' <<<"$RPC_REQUEST_PARAMS")"
    pass="$(jq -r '.password' <<<"$RPC_REQUEST_PARAMS")"

    out="$(register_user_data "$user" "$pass")" || rc=$?
    case "$rc" in
        0)
            uid="${out%%$'\t'*}"
            rpc_success "$(jq -nc --argjson uid "${uid:-0}" --arg username "$user" '{uid: $uid, username: $username}')"
            ;;
        10) rpc_invalid_params "username o password inválidos." ;;
        11) rpc_conflict "El usuario ya existe." ;;
        *) rpc_internal_error ;;
    esac
}

# @brief auth.login (público): autentica y crea sesión fork-safe.
# @params {username, password}
# @result {token, uid, username, expires_at}
rpc_handle_auth_login() {
    local user pass out session token expires rc=0 uid

    if ! jq -e '(.username | type == "string") and (.password | type == "string")' \
        >/dev/null 2>&1 <<<"$RPC_REQUEST_PARAMS"; then
        rpc_invalid_params "username y password deben ser strings."
        return 0
    fi
    user="$(jq -r '.username' <<<"$RPC_REQUEST_PARAMS")"
    pass="$(jq -r '.password' <<<"$RPC_REQUEST_PARAMS")"

    out="$(login_user_data "$user" "$pass")" || rc=$?
    case "$rc" in
        0)
            IFS=$'\t' read -r uid user <<<"$out"
            session="$(session_create "$uid" "$user")" || {
                rpc_internal_error "No se pudo crear la sesión."
                return 0
            }
            IFS=$'\t' read -r token expires <<<"$session"
            rpc_success "$(jq -nc \
                --arg token "$token" \
                --argjson uid "$uid" \
                --arg username "$user" \
                --argjson expires_at "$expires" \
                '{token: $token, uid: $uid, username: $username, expires_at: $expires_at}')"
            ;;
        11) rpc_invalid_credentials ;;
        *) rpc_internal_error ;;
    esac
}

# @brief auth.logout (privado): revoca el token validado por el layer RPC.
# @params {token}
# @result {ok: true}
rpc_handle_auth_logout() {
    local token

    token="$(jq -r '.token // empty' <<<"$RPC_REQUEST_PARAMS" 2>/dev/null || true)"
    if [[ -z "$token" ]]; then
        rpc_invalid_params "Falta token."
        return 0
    fi
    if ! session_revoke "$token"; then
        rpc_internal_error "No se pudo revocar la sesión."
        return 0
    fi
    rpc_success '{"ok":true}'
}
