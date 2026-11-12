# lib/api/report_api.sh — derivado regenerable (capa API).
# Lee vía lib/model (nunca SQL directo), escribe "$PRODUCTS_HTML".

[[ -n "${_API_REPORT_LOADED:-}" ]] && return 0
declare -g _API_REPORT_LOADED=1

if [[ -z "${DB:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Regenera el HTML desde cero (cabecera + una fila por registro).
# @param $1 uid del operador, $2 username del operador (auditoría).
# @note El HTML es derivado: siempre se puede borrar y regenerar.
generate_report() {
    local uid="$1"
    local user="$2"
    local rows id nombre precio
    if ! rows="$(model_product_list)"; then
        return 1
    fi

    mkdir -p "$(dirname "$PRODUCTS_HTML")"
    {
        printf '<!DOCTYPE html>\n<html lang="es">\n<head><meta charset="utf-8">\n'
        printf '<title>Productos</title>\n</head>\n<body>\n'
        printf '<h1>Productos</h1>\n'
        printf '<table border="1">\n<tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>\n'
    } > "$PRODUCTS_HTML"
    if [[ -n "$rows" ]]; then
        while IFS=$'\t' read -r id nombre precio; do
            [[ -z "$id" ]] && continue
            printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
                "$id" "$nombre" "$precio" >> "$PRODUCTS_HTML"
        done <<< "$rows"
    fi
    printf '</table>\n</body>\n</html>\n' >> "$PRODUCTS_HTML"
    printf 'Reporte generado en %s.\n' "$PRODUCTS_HTML"
    log_action "$uid" "$user" "reporte"
}
