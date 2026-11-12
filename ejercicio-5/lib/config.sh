# lib/config.sh — única fuente de rutas y spec ejecutable.
# Se importa primero; no tiene lógica, solo declare.
# -g: sourcing dentro de funciones (bats setup, bin/app) crea globals, no locals.
# Rutas MUTABLES a propósito (declare -g sin -r): tests y runtime las
# sobreescriben por env (DB=... source config). Fuente de verdad = "$DB".
# Spec (RE_*, OPT_*) sí inmutable (-gr/-gri).
# Orden de carga: config -> validators -> crypto -> logging -> model -> api -> ui.
# Guarda/pragma: re-sourcear es no-op (idempotente, apto para bundle concatenado).

[[ -n "${_APP_CONFIG_LOADED:-}" ]] && return 0
declare -g _APP_CONFIG_LOADED=1

# --- Rutas runtime (relativas a APP_ROOT = dir de trabajo) ---
declare -g APP_ROOT="${APP_ROOT:-.}"
declare -g DB="${DB:-var/db/data.sq3}"
declare -g LOG="${LOG:-var/log/system.log}"
declare -g ERRLOG="${ERRLOG:-var/log/error.log}"
declare -g PRODUCTS_HTML="${PRODUCTS_HTML:-var/report/productos.html}"

# --- Servidor web (host/puerto configurables por env; spec inmutable) ---
declare -g HTTP_SERVER_HOST="${HTTP_SERVER_HOST:-0.0.0.0}"
declare -g HTTP_SERVER_PORT="${HTTP_SERVER_PORT:-8080}"
declare -g HTTP_STATIC_PATH="${HTTP_STATIC_PATH:-static}"
declare -gr HTTP_DEFAULT_PATH="index.html"
declare -gr HTTP_REPORT_PREFIX="report"
declare -gri HTTP_MAX_REQUEST_BODY_SIZE=524288 # 512 KB
declare -gr HTTP_SERVER_VERSION="v1.0.0"

# --- Sesión web (fork-safe: archivo, no memoria compartida) ---
declare -g SESSION_DIR="${SESSION_DIR:-var/session}"
declare -g SESSIONS_FILE="${SESSIONS_FILE:-$SESSION_DIR/sessions.tsv}"
declare -g SESSION_TTL="${SESSION_TTL:-3600}"
declare -gr SESSION_LOCK="${SESSIONS_FILE}.lock"

# --- Rutas de deploy (fuente canónica SQL + script dueño de la DB) ---
declare -gr SCHEMA_SQL="sql/schema.sql"
declare -gr SEED_SQL="sql/seed.sql"
declare -gr DEPLOY_SH="scripts/deploy.sh"

# --- Spec ejecutable (contratos de validación y menú) ---
declare -gr RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'
declare -gr RE_USER='^[A-Za-z0-9_.-]+$'
declare -gr RE_REF_ID='^[0-9]+$'

declare -gri OPT_ADD=1
declare -gri OPT_REMOVE=2
declare -gri OPT_LIST=3
declare -gri OPT_UPDATE=4
declare -gri OPT_REPORT=5
declare -gri OPT_EXIT=6
