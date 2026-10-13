# lib/api/auth_api.sh — casos de uso de usuarios (capa API).
# Nunca texto plano en disco ni SQL directo: delega en lib/model/users_store.sh.
# Tras login/registro exitosos la auditoría usa el id AUTOINCREMENT del model.

[[ -n "${_API_AUTH_LOADED:-}" ]] && return 0
declare -g _API_AUTH_LOADED=1

if [[ -z "${RE_USER:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Alta con hash: valida, chequea duplicado y persiste username+hash.
# @param $1 username (ver RE_USER), $2 contraseña (solo vive en memoria).
# @return 0 registrado / 1 inválido o duplicado.
# @note En éxito audita (el uid se resuelve post-INSERT vía model).
register_user() {
    local user="$1"
    local pass="$2"
    local hash uid

    if ! is_valid_username "$user"; then
        log_error "$(printf 'Error: nombre de usuario inválido: "%s".' "$user")"
        return 1
    fi
    if [[ -z "$pass" ]]; then
        log_error 'Error: contraseña vacía.'
        return 1
    fi
    if model_user_exists "$user"; then
        log_error "$(printf 'Error: el usuario "%s" ya existe.' "$user")"
        return 1
    fi
    hash="$(hash_password "$pass")"
    model_user_insert "$user" "$hash" || return 1
    printf 'Usuario %s registrado.\n' "$user"
    if uid="$(model_user_get_id "$user")" && [[ -n "$uid" ]]; then
        log_action "$uid" "$user" "$(printf 'registro username="%s"' "$user")"
    fi
}

# @brief Reproduce el hash de lo tipeado y lo compara con el guardado.
# @param $1 username, $2 contraseña tipeada.
# @return 0 acceso / 1 denegado.
# @note En éxito audita; en fallo no loguea (solo éxitos).
login_user() {
    local user="$1"
    local pass="$2"
    local want got uid

    if ! model_user_exists "$user"; then
        return 1
    fi
    if ! want="$(model_user_get_hash "$user")"; then
        return 1
    fi
    got="$(hash_password "$pass")"
    if [[ -n "$want" && "$got" == "$want" ]]; then
        if uid="$(model_user_get_id "$user")" && [[ -n "$uid" ]]; then
            log_action "$uid" "$user" "$(printf 'login username="%s"' "$user")"
        fi
        return 0
    fi
    return 1
}

# @brief Id numérico de un username (para que la UI no arme SQL).
# @param $1 username.
# @stdout uid o vacío.
auth_resolve_uid() {
    local user="$1"
    model_user_get_id "$user" || true
}
