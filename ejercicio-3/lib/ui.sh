# lib/ui.sh — ÚNICA capa con I/O interactivo (read/printf de menúes).
# No toca disco directo; delega en casos de uso.

show_welcome() {
    printf "Bienvenido al Sistema de Gestion de Inventario\n\n"
}

product_menu() {
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
                read -rp "Ingrese ID: " id || return 0
                read -rp "Ingrese Nombre: " nombre || return 0
                read -rp "Ingrese Precio: " precio || return 0
                add_product "$id" "$nombre" "$precio" || true
                ;;
            "$OPT_REMOVE")
                read -rp "Ingrese ID a eliminar: " id || return 0
                remove_product "$id" || true
                ;;
            "$OPT_LIST")
                list_products
                ;;
            "$OPT_UPDATE")
                read -rp "Ingrese ID a editar: " id || return 0
                read -rp "Ingrese nuevo Nombre: " nombre || return 0
                read -rp "Ingrese nuevo Precio: " precio || return 0
                update_product "$id" "$nombre" "$precio" || true
                ;;
            "$OPT_REPORT")
                generate_report
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

main() {
    init_db
    show_welcome

    if ! auth_menu; then
        printf '\nSaliendo del programa...\n'
        return 0
    fi
    product_menu
}
