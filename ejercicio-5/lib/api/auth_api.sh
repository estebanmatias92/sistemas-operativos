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
    register_user_data "$1" "$2" >/dev/null || return 1
    printf 'Usuario %s registrado.\n' "$1"
}

# @brief Variante estructurada para la web: valida + persiste + audita.
# @param $1 username, $2 contraseña.
# @stdout "uid<TAB>username".
# @return 0 ok / 10 inválido / 11 duplicado / 12 error interno.
register_user_data() {
    local user="$1"
    local pass="$2"
    local hash uid

    if ! is_valid_username "$user"; then
        log_error "$(printf 'Error: nombre de usuario inválido: "%s".' "$user")"
        return 10
    fi
    if [[ -z "$pass" ]]; then
        log_error 'Error: contraseña vacía.'
        return 10
    fi
    if model_user_exists "$user"; then
        log_error "$(printf 'Error: el usuario "%s" ya existe.' "$user")"
        return 11
    fi
    hash="$(hash_password "$pass")"
    model_user_insert "$user" "$hash" || return 12
    if ! uid="$(model_user_get_id "$user")" || [[ -z "$uid" ]]; then
        log_error "$(printf 'Error: no se pudo resolver el uid de "%s".' "$user")"
        return 12
    fi
    log_action "$uid" "$user" "$(printf 'registro username="%s"' "$user")"
    printf '%s\t%s\n' "$uid" "$user"
}

# @brief Reproduce el hash de lo tipeado y lo compara con el guardado.
# @param $1 username, $2 contraseña tipeada.
# @return 0 acceso / 1 denegado.
# @note En éxito audita; en fallo no loguea (solo éxitos).
login_user() {
    login_user_data "$1" "$2" >/dev/null
}

# @brief Variante estructurada para la web: autentica + audita.
# @param $1 username, $2 contraseña.
# @stdout "uid<TAB>username".
# @return 0 ok / 11 credenciales inválidas / 12 error interno.
# @note Fallo de credenciales es silencioso (sin log), igual que CLI/TUI.
login_user_data() {
    local user="$1"
    local pass="$2"
    local want got uid

    model_user_exists "$user" || return 11
    if ! want="$(model_user_get_hash "$user")"; then
        return 12
    fi
    got="$(hash_password "$pass")"
    [[ -n "$want" && "$got" == "$want" ]] || return 11
    if ! uid="$(model_user_get_id "$user")" || [[ -z "$uid" ]]; then
        return 12
    fi
    log_action "$uid" "$user" "$(printf 'login username="%s"' "$user")"
    printf '%s\t%s\n' "$uid" "$user"
}

# @brief Id numérico de un username (para que la UI no arme SQL).
# @param $1 username.
# @stdout uid o vacío.
auth_resolve_uid() {
    local user="$1"
    model_user_get_id "$user" || true
}
