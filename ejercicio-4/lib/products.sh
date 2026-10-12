# lib/products.sh — casos de uso de inventario. Validan + llaman db.sh; nunca SQL/grep crudo.

# @brief Alta: valida formato, rechaza duplicado y hace append.
# @param $1 id, $2 nombre (admite espacios), $3 precio (ver RE_PRECIO).
# @param $4 uid del operador, $5 username del operador (auditoría punto 5).
# @return 0 guardado / 1 inválido o duplicado (disco intacto).
add_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local uid="$4"
    local user="$5"

    if ! product_valid "$id" "$nombre" "$precio"; then
        log_error "$(printf 'Error: datos de producto inválidos (id="%s", nombre="%s", precio="%s").' "$id" "$nombre" "$precio")"
        return 1
    fi
    if record_exists productos "$id"; then
        log_error "$(printf 'Error: el producto "%s" ya existe.' "$id")"
        return 1
    fi
    append_record productos "$(printf '%s\t%s\t%s' "$id" "$nombre" "$precio")"
    printf 'Producto %s guardado.\n' "$id"
    log_action "$uid" "$user" "$(printf 'alta id="%s"' "$id")"
}

remove_product() {
    local id="$1"
    local uid="$2"
    local user="$3"
    if ! record_exists productos "$id"; then
        log_error "$(printf 'El producto "%s" no existe.' "$id")"
        return 1
    fi
    delete_record productos "$id"
    printf 'Producto %s eliminado.\n' "$id"
    log_action "$uid" "$user" "$(printf 'baja id="%s"' "$id")"
}

# @brief Muestra el inventario desde un cache local que se descarta al salir.
# @param $1 uid del operador, $2 username del operador (auditoría punto 5).
# @note Lectura sin escritura: disco queda intacto.
list_products() {
    local uid="$1"
    local user="$2"
    local -A cache
    local id resto nombre precio
    load_table productos cache || return 1
    log_action "$uid" "$user" "listado"

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
# @param $4 uid del operador, $5 username del operador (auditoría punto 5).
# @return 0 actualizado / 1 id inexistente o dato inválido (disco intacto).
update_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local uid="$4"
    local user="$5"
    local -A cache

    if ! product_valid "$id" "$nombre" "$precio"; then
        log_error "$(printf 'Error: datos de producto inválidos (id="%s", nombre="%s", precio="%s").' "$id" "$nombre" "$precio")"
        return 1
    fi
    load_table productos cache
    if [[ -z "${cache[$id]+x}" ]]; then
        log_error "$(printf 'El producto "%s" no existe.' "$id")"
        return 1
    fi
    cache["$id"]="$(printf '%s\t%s' "$nombre" "$precio")"
    save_table productos cache
    printf 'Producto %s actualizado.\n' "$id"
    log_action "$uid" "$user" "$(printf 'edición id="%s"' "$id")"
}
