# lib/api/products_api.sh — casos de uso de inventario (capa API).
# Validan + llaman a lib/model/*; nunca SQL/sqlite3/grep crudo.
# El id de producto es AUTOINCREMENT: el alta NO lo pide, lo devuelve la DB.
#
# Variantes *_data (para la web) devuelven datos por stdout y usan códigos
# estables: 0 ok / 10 inválido / 11 inexistente / 12 interno. Las funciones
# históricas conservan mensajes y return 0/1 para CLI/TUI.

[[ -n "${_API_PRODUCTS_LOADED:-}" ]] && return 0
declare -g _API_PRODUCTS_LOADED=1

if [[ -z "${RE_PRECIO:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Alta: valida formato e inserta; el id lo genera SQLite.
# @param $1 nombre (admite espacios), $2 precio (ver RE_PRECIO).
# @param $3 uid del operador, $4 username del operador (auditoría).
# @stdout "Producto <id> guardado." (el <id> es el autogenerado).
# @return 0 guardado / 1 inválido o fallo SQL (disco intacto).
add_product() {
    local new_id
    new_id="$(add_product_data "$1" "$2" "$3" "$4")" || return 1
    printf 'Producto %s guardado.\n' "$new_id"
}

# @brief Variante estructurada: valida + inserta + audita.
# @param $1 nombre, $2 precio, $3 uid, $4 username.
# @stdout id autogenerado.
# @return 0 ok / 10 inválido / 12 interno.
add_product_data() {
    local nombre="$1"
    local precio="$2"
    local uid="$3"
    local user="$4"
    local new_id

    if ! product_data_valid "$nombre" "$precio"; then
        log_error "$(printf 'Error: datos de producto inválidos (nombre="%s", precio="%s").' "$nombre" "$precio")"
        return 10
    fi
    if ! new_id="$(model_product_insert "$nombre" "$precio")"; then
        log_error "$(printf 'Error: no se pudo guardar el producto (nombre="%s").' "$nombre")"
        return 12
    fi
    if [[ -z "$new_id" ]]; then
        log_error 'Error: no se pudo guardar el producto (sin id generado).'
        return 12
    fi
    log_action "$uid" "$user" "$(printf 'alta id="%s"' "$new_id")"
    printf '%s\n' "$new_id"
}

# @brief Baja por id (mensaje histórico).
remove_product() {
    local id
    id="$(remove_product_data "$1" "$2" "$3")" || return 1
    printf 'Producto %s eliminado.\n' "$id"
}

# @brief Variante estructurada: valida existencia + elimina + audita.
# @param $1 id, $2 uid, $3 username.
# @stdout id eliminado.
# @return 0 ok / 11 inexistente o inválido / 12 interno.
remove_product_data() {
    local id="$1"
    local uid="$2"
    local user="$3"

    if ! is_valid_ref_id "$id" || ! model_product_exists "$id"; then
        log_error "$(printf 'El producto "%s" no existe.' "$id")"
        return 11
    fi
    model_product_delete "$id" || return 12
    log_action "$uid" "$user" "$(printf 'baja id="%s"' "$id")"
    printf '%s\n' "$id"
}

# @brief Muestra el inventario (lectura sin escritura: disco intacto).
# @param $1 uid del operador, $2 username del operador (auditoría).
list_products() {
    local rows id nombre precio empty=1
    rows="$(list_products_data "$1" "$2")" || return 1

    if [[ -z "$rows" ]]; then
        printf '\nLISTADO: (vacío)\n'
        return 0
    fi
    printf '\nLISTADO:\n'
    while IFS=$'\t' read -r id nombre precio; do
        [[ -z "$id" ]] && continue
        empty=0
        printf 'ID %s : %s - $%s\n' "$id" "$nombre" "$precio"
    done <<<"$rows"
    if ((empty)); then
        printf '(vacío)\n'
    fi
}

# @brief Variante estructurada: filas TSV id<TAB>nombre<TAB>precio + auditoría.
# @param $1 uid, $2 username.
# @return 0 ok (puede no haber filas) / 12 interno.
list_products_data() {
    local uid="$1"
    local user="$2"
    local rows

    rows="$(model_product_list)" || return 12
    log_action "$uid" "$user" "listado"
    if [[ -n "$rows" ]]; then
        printf '%s\n' "$rows"
    fi
}

# @brief Modificación quirúrgica: valida nuevo dato + UPDATE por id.
# @param $1 id autogenerado, $2 nombre nuevo, $3 precio nuevo.
# @param $4 uid del operador, $5 username del operador (auditoría).
# @return 0 actualizado / 1 id inexistente o dato inválido (disco intacto).
update_product() {
    local id
    id="$(update_product_data "$1" "$2" "$3" "$4" "$5")" || return 1
    printf 'Producto %s actualizado.\n' "$id"
}

# @brief Variante estructurada: valida + UPDATE por id + audita.
# @param $1 id, $2 nombre, $3 precio, $4 uid, $5 username.
# @stdout id actualizado.
# @return 0 ok / 10 inválido / 11 inexistente / 12 interno.
update_product_data() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local uid="$4"
    local user="$5"

    if ! product_data_valid "$nombre" "$precio"; then
        log_error "$(printf 'Error: datos de producto inválidos (nombre="%s", precio="%s").' "$nombre" "$precio")"
        return 10
    fi
    if ! is_valid_ref_id "$id" || ! model_product_exists "$id"; then
        log_error "$(printf 'El producto "%s" no existe.' "$id")"
        return 11
    fi
    model_product_update "$id" "$nombre" "$precio" || return 12
    log_action "$uid" "$user" "$(printf 'edición id="%s"' "$id")"
    printf '%s\n' "$id"
}
