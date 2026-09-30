# lib/auth.sh — casos de uso de usuarios. Nunca texto plano en disco.

# @brief Alta con hash: valida, chequea duplicado y persiste username+hash.
# @param $1 username (ver RE_USER), $2 contraseña (solo vive en memoria).
# @return 0 registrado / 1 inválido o duplicado.
register_user() {
    local user="$1"
    local pass="$2"
    local hash

    if ! is_valid_username "$user"; then
        printf 'Error: nombre de usuario inválido.\n' >&2
        return 1
    fi
    if [[ -z "$pass" ]]; then
        printf 'Error: contraseña vacía.\n' >&2
        return 1
    fi
    if record_exists usuarios "$user"; then
        printf 'Error: el usuario "%s" ya existe.\n' "$user" >&2
        return 1
    fi
    hash="$(hash_password "$pass")"
    append_record usuarios "$(printf '%s\t%s' "$user" "$hash")"
    printf 'Usuario %s registrado.\n' "$user"
}

# @brief Reproduce el hash de lo tipeado y lo compara con el guardado.
# @param $1 username, $2 contraseña tipeada.
# @return 0 acceso / 1 denegado.
login_user() {
    local user="$1"
    local pass="$2"
    local want got esc

    if ! record_exists usuarios "$user"; then
        return 1
    fi
    esc="$(sql_escape "$user")"
    if ! want="$(sqlite3 "$DB" "SELECT hash FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG")"; then
        return 1
    fi
    got="$(hash_password "$pass")"
    [[ -n "$want" && "$got" == "$want" ]]
}

register_interactive() {
    local user pass
    read -rp "Nuevo usuario: " user || return 2
    read -rsp "Contraseña: " pass || return 2; echo
    register_user "$user" "$pass"
}

# @brief Login con 3 intentos (heredado de ejercicio-1).
# @return 0 acceso / 1 denegado / 2 EOF.
auth_interactive() {
    local -i intentos=0
    local user pass

    while (( intentos < 3 )); do
        read -rp "Usuario: " user || return 2
        read -rsp "Contraseña: " pass || return 2; echo
        if login_user "$user" "$pass"; then
            printf 'Acceso concedido.\n'
            return 0
        fi
        intentos=$((intentos + 1))
        printf 'Credenciales incorrectas (%d/3 intentos).\n' "$intentos"
    done
    return 1
}

# @brief Menú de acceso: sin login o registro no se llega al inventario.
# @return 0 login OK (entrar) / 1 salir o EOF.
# @note El 1 de un fallo de validación NO sale del menú.
auth_menu() {
    local opt="" s=0
    while true; do
        printf '\nACCESO:\n'
        printf '1. Iniciar sesión\n'
        printf '2. Registrar usuario\n'
        printf '3. Salir\n'
        read -rp "Opción: " opt || return 1
        case "$opt" in
            1)
                auth_interactive; s=$?
                if (( s == 0 )); then return 0; fi
                if (( s == 2 )); then return 1; fi
                ;;
            2)
                register_interactive; s=$?
                if (( s == 2 )); then return 1; fi
                ;;
            3) return 1 ;;
            *) printf '\nOpción inválida.\n' ;;
        esac
    done
}
