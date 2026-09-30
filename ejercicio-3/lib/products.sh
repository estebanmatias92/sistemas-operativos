# lib/products.sh — casos de uso de inventario. Validan + llaman db.sh; nunca SQL/grep crudo.

# @brief Alta: valida formato, rechaza duplicado y hace append.
# @param $1 id, $2 nombre (admite espacios), $3 precio (ver RE_PRECIO).
# @return 0 guardado / 1 inválido o duplicado (disco intacto).
add_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"

    if ! product_valid "$id" "$nombre" "$precio"; then
        printf 'Error: datos de producto inválidos.\n' >&2
        return 1
    fi
    if record_exists productos "$id"; then
        printf 'Error: el producto "%s" ya existe.\n' "$id" >&2
        return 1
    fi
    append_record productos "$(printf '%s\t%s\t%s' "$id" "$nombre" "$precio")"
    printf 'Producto %s guardado.\n' "$id"
}

remove_product() {
    local id="$1"
    if ! record_exists productos "$id"; then
        printf 'El producto no existe.\n'
        return 1
    fi
    delete_record productos "$id"
    printf 'Producto %s eliminado.\n' "$id"
}

# @brief Muestra el inventario desde un cache local que se descarta al salir.
# @note Lectura sin escritura: disco queda intacto.
list_products() {
    local -A cache
    local id resto nombre precio
    load_table productos cache

    if (( ${#cache[@]} == 0 )); then
        printf '\nLISTADO: (vacío)\n'
        return 0
    fi
    printf '\nLISTADO:\n'
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"
        printf 'ID %s : %s - $%s\n' "$id" "$nombre" "$precio"
    done
}

# @brief Modificación en memoria: load -> validar nuevo -> mutar -> save.
# @param $1 id, $2 nombre nuevo, $3 precio nuevo.
# @return 0 actualizado / 1 id inexistente o dato inválido (disco intacto).
update_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local -A cache

    if ! product_valid "$id" "$nombre" "$precio"; then
        printf 'Error: datos de producto inválidos.\n' >&2
        return 1
    fi
    load_table productos cache
    if [[ -z "${cache[$id]+x}" ]]; then
        printf 'El producto no existe.\n'
        return 1
    fi
    cache["$id"]="$(printf '%s\t%s' "$nombre" "$precio")"
    save_table productos cache
    printf 'Producto %s actualizado.\n' "$id"
}
