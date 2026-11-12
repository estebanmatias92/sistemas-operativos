# lib/ui/cli.sh — client CLI (capa UI, heredado Lab 05).
# Nunca toca disco/SQL directo; delega en la API (add/remove/update/list,
# register/login, generate_report). Sin `sqlite3`, sin `whiptail`.

[[ -n "${_UI_CLI_LOADED:-}" ]] && return 0
declare -g _UI_CLI_LOADED=1

if [[ -z "${OPT_ADD:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

show_welcome() {
    printf "Bienvenido al Sistema de Gestion de Inventario\n\n"
}

register_interactive() {
    local user pass
    read -rp "Nuevo usuario: " user || return 2
    read -rsp "Contraseña: " pass || return 2; echo
    register_user "$user" "$pass"
}

# @brief Login con 3 intentos (heredado de ejercicio-1).
# @param $1 nombre de var donde dejar el uid, $2 nombre de var para el username.
# @return 0 acceso / 1 denegado / 2 EOF.
auth_interactive() {
    local -n _uid_out="$1"
    local -n _user_out="$2"
    local -i intentos=0
    local user pass uid

    while (( intentos < 3 )); do
        read -rp "Usuario: " user || return 2
        read -rsp "Contraseña: " pass || return 2; echo
        if login_user "$user" "$pass"; then
            if uid="$(auth_resolve_uid "$user")" && [[ -n "$uid" ]]; then
                _uid_out="$uid"
                _user_out="$user"
            fi
            printf 'Acceso concedido.\n'
            return 0
        fi
        intentos=$((intentos + 1))
        printf 'Credenciales incorrectas (%d/3 intentos).\n' "$intentos"
    done
    return 1
}

# @brief Menú de acceso: sin login o registro no se llega al inventario.
# @param $1 nombre de var donde dejar el uid, $2 nombre de var para el username.
# @return 0 login OK (entrar) / 1 salir o EOF.
# @note El 1 de un fallo de validación NO sale del menú.
auth_menu() {
    local -n _menu_uid="$1"
    local -n _menu_user="$2"
    local opt="" s=0 uid_tmp="" user_tmp=""
    while true; do
        printf '\nACCESO:\n'
        printf '1. Iniciar sesión\n'
        printf '2. Registrar usuario\n'
        printf '3. Salir\n'
        read -rp "Opción: " opt || return 1
        case "$opt" in
            1)
                auth_interactive uid_tmp user_tmp; s=$?
                if (( s == 0 )); then
                    _menu_uid="$uid_tmp"
                    _menu_user="$user_tmp"
                    return 0
                fi
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

product_menu() {
    local uid="$1"
    local user="$2"
    local opt=""
    local id nombre precio

    while [[ "$opt" != "$OPT_EXIT" ]]; do
        printf '\nACCIONES:\n'
        printf '1. Alta producto\n'
        printf '2. Baja producto\n'
        printf '3. Mostrar inventario\n'
        printf '4. Editar producto\n'
        printf '5. Generar reporte HTML\n'
        printf '6. Salir\n'
        read -rp "Opción: " opt || return 0

        case "$opt" in
            "$OPT_ADD")
                read -rp "Ingrese Nombre: " nombre || return 0
                read -rp "Ingrese Precio: " precio || return 0
                add_product "$nombre" "$precio" "$uid" "$user" || true
                ;;
            "$OPT_REMOVE")
                read -rp "Ingrese ID a eliminar: " id || return 0
                remove_product "$id" "$uid" "$user" || true
                ;;
            "$OPT_LIST")
                list_products "$uid" "$user"
                ;;
            "$OPT_UPDATE")
                read -rp "Ingrese ID a editar: " id || return 0
                read -rp "Ingrese nuevo Nombre: " nombre || return 0
                read -rp "Ingrese nuevo Precio: " precio || return 0
                update_product "$id" "$nombre" "$precio" "$uid" "$user" || true
                ;;
            "$OPT_REPORT")
                generate_report "$uid" "$user"
                ;;
            "$OPT_EXIT")
                printf '\nSaliendo del programa...\n'
                ;;
            *)
                printf '\nOpción inválida.\n'
                ;;
        esac
    done
}
