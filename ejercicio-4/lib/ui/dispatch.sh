# lib/ui/dispatch.sh — dispatcher dual client + entrypoints por client.
# Sin args = --tui. La DB la crea scripts/deploy.sh (`make init`); aquí solo
# se exige con require_db (fail-fast amable, nunca auto-crea).

[[ -n "${_UI_DISPATCH_LOADED:-}" ]] && return 0
declare -g _UI_DISPATCH_LOADED=1

if [[ -z "${OPT_ADD:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

print_usage() {
    printf 'Uso: %s [--tui|--cli|--help]\n' "${0##*/}"
    printf '  --tui    Interfaz whiptail (default; requiere TTY).\n'
    printf '  --cli    Interfaz CLI heredada del Lab 05.\n'
    printf '  --help   Muestra esta ayuda.\n'
}

cli_main() {
    require_db || return 1
    show_welcome

    local uid="" user=""
    if ! auth_menu uid user; then
        printf '\nSaliendo del programa...\n'
        return 0
    fi
    product_menu "$uid" "$user"
}

# @brief Entrada TUI: exige whiptail+TTY y DB desplegada, luego mismo flujo que cli_main.
tui_main() {
    tui_require || return 1
    require_db || return 1
    tui_msg "Bienvenida" "Bienvenido al Sistema de Gestion de Inventario"

    local uid="" user=""
    if ! tui_auth_menu uid user; then
        tui_msg "Salida" "Saliendo del programa..."
        return 0
    fi
    tui_product_menu "$uid" "$user"
}

# @brief Dispatcher dual client. Sin args = --tui.
main() {
    local mode="--tui"
    if (( $# > 0 )); then
        case "${1:-}" in
            --tui|--cli) mode="$1" ;;
            --help|-h) print_usage; return 0 ;;
            *) printf 'Opción desconocida: %s\n' "$1" >&2; print_usage; return 1 ;;
        esac
    fi
    if [[ "$mode" == "--cli" ]]; then
        cli_main
    else
        tui_main
    fi
}
