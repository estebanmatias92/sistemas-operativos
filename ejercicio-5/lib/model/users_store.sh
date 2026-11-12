# lib/model/users_store.sh — persistencia de usuarios (id AUTOINCREMENT, hash hex).
# Solo model invoca `sqlite3`. La API nunca arma SQL ni ve texto plano.

[[ -n "${_MODEL_USERS_STORE_LOADED:-}" ]] && return 0
declare -g _MODEL_USERS_STORE_LOADED=1

if [[ -z "${DB:-}" || -z "${RE_USER:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief ¿Existe este username? (salida vacía = no existe).
# @param $1 username.
# @return 0 existe / 1 no existe.
model_user_exists() {
    local user="$1"
    local esc out
    esc="$(sql_escape "$user")"
    if ! out="$(db_exec "SELECT 1 FROM usuarios WHERE username='$esc';")"; then
        return 1
    fi
    [[ -n "$out" ]]
}

# @brief Alta cruda username+hash (la API valida + hashea antes).
# @param $1 username, $2 hash hex.
model_user_insert() {
    local user="$1"
    local hash="$2"
    local euser ehash
    euser="$(sql_escape "$user")"
    ehash="$(sql_escape "$hash")"
    db_exec "INSERT INTO usuarios(username,hash) VALUES('$euser','$ehash');"
}

# @brief Hash guardado por stdout (vacío = no existe).
# @param $1 username.
model_user_get_hash() {
    local user="$1"
    local esc
    esc="$(sql_escape "$user")"
    db_exec "SELECT hash FROM usuarios WHERE username='$esc';"
}

# @brief Id numérico del username por stdout (vacío = no existe).
# @param $1 username.
model_user_get_id() {
    local user="$1"
    local esc
    esc="$(sql_escape "$user")"
    db_exec "SELECT id FROM usuarios WHERE username='$esc';"
}
