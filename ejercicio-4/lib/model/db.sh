# lib/model/db.sh — base de la capa model: ÚNICO punto con `sqlite3`.
# Guarda/pragma + auto-source defensivo de config (modo modular standalone).
# Dependencias: solo config (y logging como cross-cutting en require_db).

[[ -n "${_MODEL_DB_LOADED:-}" ]] && return 0
declare -g _MODEL_DB_LOADED=1

if [[ -z "${DB:-}" || -z "${RE_PRECIO:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

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

# @brief Fail-fast: exige DB creada por scripts/deploy.sh (nunca la crea).
# @return 0 lista / 1 falta (mensaje amable vía log_error si existe).
# @note La creación vive en scripts/deploy.sh (`make init`); el runtime no escribe schema.
require_db() {
    local tables
    if [[ ! -f "$DB" ]]; then
        if declare -F log_error >/dev/null; then
            log_error "$(printf 'Error: falta %s; corra `make init`.' "$DB")"
        else
            printf 'Error: falta %s; corra `make init`.\n' "$DB" >&2
        fi
        return 1
    fi
    if ! tables="$(sqlite3 "$DB" ".tables" 2>>"$ERRLOG")"; then
        return 1
    fi
    if [[ "$tables" != *"productos"* || "$tables" != *"usuarios"* ]]; then
        if declare -F log_error >/dev/null; then
            log_error "$(printf 'Error: schema incompleto en "%s"; corra `make init`.' "$DB")"
        else
            printf 'Error: schema incompleto en "%s"; corra `make init`.\n' "$DB" >&2
        fi
        return 1
    fi
    return 0
}

# @brief Ejecuta una sentencia contra "$DB" (una por invocación).
# @param $1 SQL con comillas dobles Bash afuera, simples SQL adentro (valores ya escapados).
# @stdout salida de sqlite3. stderr crudo va a "$ERRLOG".
db_exec() {
    local sql="$1"
    sqlite3 "$DB" "$sql" 2>>"$ERRLOG"
}
