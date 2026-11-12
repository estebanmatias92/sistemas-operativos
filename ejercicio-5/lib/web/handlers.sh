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

# @brief products.list (privado): inventario como array JSON.
# @params {token}
# @result {products: [{id, nombre, precio}]}
rpc_handle_products_list() {
    local rows json

    rows="$(list_products_data "$RPC_SESSION_UID" "$RPC_SESSION_USER")" || {
        rpc_internal_error
        return 0
    }
    if [[ -z "$rows" ]]; then
        json='[]'
    else
        json="$(printf '%s\n' "$rows" | jq -Rsc '
            split("\n")
            | map(select(length > 0) | split("\t") | {id: (.[0] | tonumber), nombre: .[1], precio: .[2]})')"
    fi
    rpc_success "$(jq -nc --argjson products "$json" '{products: $products}')"
}

# @brief products.add (privado): alta con id autogenerado.
# @params {token, nombre, precio}
# @result {id, nombre, precio}
rpc_handle_products_add() {
    local nombre precio out rc=0 id

    if ! jq -e '(.nombre | type == "string") and (.precio | type == "string")' \
        >/dev/null 2>&1 <<<"$RPC_REQUEST_PARAMS"; then
        rpc_invalid_params "nombre y precio deben ser strings."
        return 0
    fi
    nombre="$(jq -r '.nombre' <<<"$RPC_REQUEST_PARAMS")"
    precio="$(jq -r '.precio' <<<"$RPC_REQUEST_PARAMS")"

    out="$(add_product_data "$nombre" "$precio" "$RPC_SESSION_UID" "$RPC_SESSION_USER")" || rc=$?
    case "$rc" in
        0)
            id="$out"
            rpc_success "$(jq -nc \
                --argjson id "$id" \
                --arg nombre "$nombre" \
                --arg precio "$precio" \
                '{id: $id, nombre: $nombre, precio: $precio}')"
            ;;
        10) rpc_invalid_params "nombre o precio inválidos." ;;
        *) rpc_internal_error ;;
    esac
}

# @brief products.update (privado): edición quirúrgica por id.
# @params {token, id, nombre, precio}
# @result {id, nombre, precio}
rpc_handle_products_update() {
    local id nombre precio out rc=0

    if ! jq -e '(.id | type == "number" or type == "string")
        and (.nombre | type == "string")
        and (.precio | type == "string")' >/dev/null 2>&1 <<<"$RPC_REQUEST_PARAMS"; then
        rpc_invalid_params "id, nombre y precio requeridos."
        return 0
    fi
    id="$(jq -r '.id' <<<"$RPC_REQUEST_PARAMS")"
    nombre="$(jq -r '.nombre' <<<"$RPC_REQUEST_PARAMS")"
    precio="$(jq -r '.precio' <<<"$RPC_REQUEST_PARAMS")"

    if ! is_valid_ref_id "$id"; then
        rpc_invalid_params "id debe ser un entero positivo."
        return 0
    fi

    out="$(update_product_data "$id" "$nombre" "$precio" "$RPC_SESSION_UID" "$RPC_SESSION_USER")" || rc=$?
    case "$rc" in
        0)
            rpc_success "$(jq -nc \
                --argjson id "$id" \
                --arg nombre "$nombre" \
                --arg precio "$precio" \
                '{id: $id, nombre: $nombre, precio: $precio}')"
            ;;
        10) rpc_invalid_params "nombre o precio inválidos." ;;
        11) rpc_not_found "El producto no existe." ;;
        *) rpc_internal_error ;;
    esac
}

# @brief products.remove (privado): baja por id.
# @params {token, id}
# @result {id}
rpc_handle_products_remove() {
    local id out rc=0

    if ! jq -e '(.id | type == "number" or type == "string")' \
        >/dev/null 2>&1 <<<"$RPC_REQUEST_PARAMS"; then
        rpc_invalid_params "id requerido."
        return 0
    fi
    id="$(jq -r '.id' <<<"$RPC_REQUEST_PARAMS")"
    if ! is_valid_ref_id "$id"; then
        rpc_invalid_params "id debe ser un entero positivo."
        return 0
    fi

    out="$(remove_product_data "$id" "$RPC_SESSION_UID" "$RPC_SESSION_USER")" || rc=$?
    case "$rc" in
        0) rpc_success "$(jq -nc --argjson id "$out" '{id: $id}')" ;;
        11) rpc_not_found "El producto no existe." ;;
        *) rpc_internal_error ;;
    esac
}

# @brief report.generate (privado): regenera var/report/productos.html.
# @params {token}
# @result {path, url}
rpc_handle_report_generate() {
    local path url rc=0

    path="$(generate_report_data "$RPC_SESSION_UID" "$RPC_SESSION_USER")" || rc=$?
    if ((rc != 0)); then
        rpc_internal_error
        return 0
    fi
    url="/$HTTP_REPORT_PREFIX/${path##*/}"
    rpc_success "$(jq -nc --arg path "$path" --arg url "$url" '{path: $path, url: $url}')"
}
