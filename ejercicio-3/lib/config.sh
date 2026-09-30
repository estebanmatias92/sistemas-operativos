# lib/config.sh — única fuente de rutas y spec ejecutable.
# Se importa primero; no tiene lógica, solo declare -gr.
# -g: sourcing dentro de funciones (bats setup, bin/app) crea globals, no locals.
# Rutas MUTABLES a propósito (declare -g sin -r): tests y runtime las
# sobreescriben por env (DB=... source config). Fuente de verdad = "$DB".
# Spec (RE_*, OPT_*) sí inmutable (-gr/-gri).
# Orden de carga: config -> validators -> crypto -> logging -> db -> auth/products/report -> ui.

declare -g APP_ROOT="${APP_ROOT:-.}"
declare -g DB="${DB:-var/db/data.sq3}"
declare -g LOG="${LOG:-var/log/system.log}"
declare -g ERRLOG="${ERRLOG:-var/log/error.log}"
declare -g PRODUCTS_HTML="${PRODUCTS_HTML:-var/report/productos.html}"

declare -gr RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'
declare -gr RE_USER='^[A-Za-z0-9_.-]+$'

declare -gri OPT_ADD=1
declare -gri OPT_REMOVE=2
declare -gri OPT_LIST=3
declare -gri OPT_UPDATE=4
declare -gri OPT_REPORT=5
declare -gri OPT_EXIT=6
