# lib/model/products_store.sh — persistencia de productos (id AUTOINCREMENT).
# Solo este archivo + users_store.sh + db.sh invocan `sqlite3`. La API nunca arma SQL.
# El id lo genera SQLite; el llamador lo recibe por stdout (last_insert_rowid).

[[ -n "${_MODEL_PRODUCTS_STORE_LOADED:-}" ]] && return 0
declare -g _MODEL_PRODUCTS_STORE_LOADED=1

if [[ -z "${DB:-}" || -z "${RE_PRECIO:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Alta cruda (sin validar): la API valida formato antes.
# @param $1 nombre, $2 precio.
# @stdout nuevo id autogenerado.
# @return 0 insertado / 1 fallo SQL (disco intacto).
# @note INSERT + SELECT last_insert_rowid en UNA invocación (misma conexión).
model_product_insert() {
    local nombre="$1"
    local precio="$2"
    local enombre eprecio
    enombre="$(sql_escape "$nombre")"
    eprecio="$(sql_escape "$precio")"
    db_exec "INSERT INTO productos(nombre,precio) VALUES('$enombre','$eprecio'); SELECT last_insert_rowid();"
}

# @brief ¿Existe este id? (SELECT amable: salida vacía = no existe).
# @param $1 id numérico.
# @return 0 existe / 1 no existe o formato inválido.
model_product_exists() {
    local id="$1"
    local esc out
    [[ "$id" =~ $RE_REF_ID ]] || return 1
    esc="$(sql_escape "$id")"
    if ! out="$(db_exec "SELECT 1 FROM productos WHERE id='$esc';")"; then
        return 1
    fi
    [[ -n "$out" ]]
}

# @brief Actualización quirúrgica (un UPDATE, preserva AUTOINCREMENT).
# @param $1 id, $2 nombre nuevo, $3 precio nuevo.
model_product_update() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local eid enombre eprecio
    eid="$(sql_escape "$id")"
    enombre="$(sql_escape "$nombre")"
    eprecio="$(sql_escape "$precio")"
    db_exec "UPDATE productos SET nombre='$enombre',precio='$eprecio' WHERE id='$eid';"
}

# @brief Baja por id.
# @param $1 id.
model_product_delete() {
    local id="$1"
    local esc
    esc="$(sql_escape "$id")"
    db_exec "DELETE FROM productos WHERE id='$esc';"
}

# @brief Listado tabular TSV (id<TAB>nombre<TAB>precio) por stdout.
model_product_list() {
    local sep
    sep="$(printf '\t')"
    sqlite3 "$DB" -separator "$sep" "SELECT id,nombre,precio FROM productos;" 2>>"$ERRLOG"
}
