# lib/report.sh — derivado regenerable. Lee vía db.sh, escribe "$PRODUCTS_HTML".

# @brief Regenera el HTML desde cero (cabecera + una fila por registro).
# @param $1 uid del operador, $2 username del operador (auditoría punto 5).
# @note El HTML es derivado: siempre se puede borrar y regenerar.
generate_report() {
    local uid="$1"
    local user="$2"
    local -A cache
    local id resto nombre precio
    load_table productos cache

    mkdir -p "$(dirname "$PRODUCTS_HTML")"
    {
        printf '<!DOCTYPE html>\n<html lang="es">\n<head><meta charset="utf-8">\n'
        printf '<title>Productos</title>\n</head>\n<body>\n'
        printf '<h1>Productos</h1>\n'
        printf '<table border="1">\n<tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>\n'
    } > "$PRODUCTS_HTML"
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"
        printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$id" "$nombre" "$precio" >> "$PRODUCTS_HTML"
    done
    printf '</table>\n</body>\n</html>\n' >> "$PRODUCTS_HTML"
    printf 'Reporte generado en %s.\n' "$PRODUCTS_HTML"
    log_action "$uid" "$user" "reporte"
}
