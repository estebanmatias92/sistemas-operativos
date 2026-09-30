# lib/db.sh — ÚNICA capa que toca la base (SQLite3 contra "$DB").
# Variabilidad Lab 05: mismas firmas que el adapter TSV del Lab 04, distinta
# implementación. Nadie fuera de aquí invoca `sqlite3` ni arma SQL crudo.
#
# TIPOS:
#   cache   : array asociativo temporal del llamador (se crea, usa y descarta).
#             clave = id/username, valor = resto opaco con su TAB.
#             Ej: cache=([A1]="Yerba Mate\t120.50"). Nunca global persistente.

# @brief Escapa un valor para interpolarlo como literal SQL (' -> '').
# @param $1 valor crudo.
# @stdout valor escapado. Siempre usar antes de interpolar en SQL.
sql_escape() {
    local val="$1"
    printf '%s' "${val//\'/\'\'}"
}

# @brief Lista blanca de tablas: un input nunca se convierte en SQL arbitrario.
# @param $1 nombre de tabla.
# @return 0 conocida / 1 desconocida.
valid_table() {
    case "$1" in
        productos|usuarios) return 0 ;;
        *) return 1 ;;
    esac
}

# @brief Crea el schema si falta (idempotente). Consigna punto 3: si data.sq3
# no existe en el dir de trabajo, construirlo. Espejo de sql/schema.sql.
init_db() {
    mkdir -p "$(dirname "$DB")" "$(dirname "$LOG")" "$(dirname "$ERRLOG")" "$(dirname "$PRODUCTS_HTML")"
    if ! sqlite3 "$DB" <<'SQL' 2>>"$ERRLOG"; then
CREATE TABLE IF NOT EXISTS usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS productos(id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio TEXT NOT NULL);
SQL
        return 1
    fi
    [[ -f "$LOG" ]] || : > "$LOG"
    [[ -f "$ERRLOG" ]] || : > "$ERRLOG"
}

# @brief ¿Existe esta clave? SELECT amable (salida vacía = no existe).
# @param $1 tabla, $2 clave (id o username).
# @return 0 existe / 1 no existe o tabla inválida.
# @note sqlite3 retorna 0 aun sin filas: chequear salida vacía, no $?.
record_exists() {
    local tbl="$1"
    local key="$2"
    local esc out
    valid_table "$tbl" || return 1
    esc="$(sql_escape "$key")"
    if [[ "$tbl" == "productos" ]]; then
        if ! out="$(sqlite3 "$DB" "SELECT 1 FROM productos WHERE id='$esc';" 2>>"$ERRLOG")"; then
            return 1
        fi
    else
        if ! out="$(sqlite3 "$DB" "SELECT 1 FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG")"; then
            return 1
        fi
    fi
    [[ -n "$out" ]]
}

# @brief Alta cruda (sin validar): el llamador valida formato + duplicado antes.
# @param $1 tabla, $2 línea "col1\tcol2[\tcol3]" (mismo formato que el TSV del Lab 04).
# @return 0 insertado / 1 tabla inválida o fallo constraint (disco intacto).
append_record() {
    local tbl="$1"
    local line="$2"
    local c1 c2 c3 e1 e2 e3
    valid_table "$tbl" || return 1
    IFS=$'\t' read -r c1 c2 c3 <<< "$line"
    e1="$(sql_escape "$c1")"
    e2="$(sql_escape "$c2")"
    e3="$(sql_escape "$c3")"
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "INSERT INTO productos(id,nombre,precio) VALUES('$e1','$e2','$e3');" 2>>"$ERRLOG" || return 1
    else
        sqlite3 "$DB" "INSERT INTO usuarios(username,hash) VALUES('$e1','$e2');" 2>>"$ERRLOG" || return 1
    fi
}

# @brief Baja por clave.
# @param $1 tabla, $2 clave.
delete_record() {
    local tbl="$1"
    local key="$2"
    local esc
    valid_table "$tbl" || return 1
    esc="$(sql_escape "$key")"
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "DELETE FROM productos WHERE id='$esc';" 2>>"$ERRLOG" || return 1
    else
        sqlite3 "$DB" "DELETE FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG" || return 1
    fi
}

# @brief Foto de la tabla en el cache del llamador (ver TIPOS).
# @param $1 tabla.
# @param $2 cache por nombre (se vacía y se llena).
# @return 0 ok / 1 tabla inválida o fallo SQL.
load_table() {
    local tbl="$1"
    local -n ref="$2"
    local k resto
    local sep rows

    valid_table "$tbl" || return 1
    ref=()
    sep="$(printf '\t')"

    if [[ "$tbl" == "productos" ]]; then
        if ! rows="$(sqlite3 "$DB" -separator "$sep" "SELECT id,nombre,precio FROM productos;" 2>>"$ERRLOG")"; then
            return 1
        fi
    else
        if ! rows="$(sqlite3 "$DB" -separator "$sep" "SELECT username,hash FROM usuarios;" 2>>"$ERRLOG")"; then
            return 1
        fi
    fi
    [[ -z "$rows" ]] && return 0
    while IFS=$'\t' read -r k resto; do
        [[ -z "$k" ]] && continue
        ref["$k"]="$resto"
    done <<< "$rows"
}

# @brief Vuelca un cache modificado (compat Lab 04): DELETE + re-INSERT.
# Mantiene el flujo `load -> mutar -> save` de update_product sin cambios.
# @param $1 tabla.
# @param $2 cache por nombre.
save_table() {
    local tbl="$1"
    local -n ref="$2"
    local k resto nombre precio e1 e2 e3

    valid_table "$tbl" || return 1
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "DELETE FROM productos;" 2>>"$ERRLOG" || return 1
        for k in "${!ref[@]}"; do
            resto="${ref[$k]}"
            IFS=$'\t' read -r nombre precio <<< "$resto"
            e1="$(sql_escape "$k")"
            e2="$(sql_escape "$nombre")"
            e3="$(sql_escape "$precio")"
            sqlite3 "$DB" "INSERT INTO productos(id,nombre,precio) VALUES('$e1','$e2','$e3');" 2>>"$ERRLOG" || return 1
        done
    else
        sqlite3 "$DB" "DELETE FROM usuarios;" 2>>"$ERRLOG" || return 1
        for k in "${!ref[@]}"; do
            e1="$(sql_escape "$k")"
            e2="$(sql_escape "${ref[$k]}")"
            sqlite3 "$DB" "INSERT INTO usuarios(username,hash) VALUES('$e1','$e2');" 2>>"$ERRLOG" || return 1
        done
    fi
}
