# lib/logging.sh — cross-cutting. Cualquier capa lo llama; nunca importa ui ni db.
# Formato system.log: fecha/hora<TAB>id<TAB>usuario<TAB>acción
# Guarda/pragma + auto-source defensivo de config (modo modular standalone).

[[ -n "${_LOGGING_LOADED:-}" ]] && return 0
declare -g _LOGGING_LOADED=1

if [[ -z "${LOG:-}" || -z "${ERRLOG:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Adjunta una línea de auditoría.
# @param $1 id, $2 usuario, $3 acción.
log_action() {
    local id="$1"
    local user="$2"
    local accion="$3"
    mkdir -p "$(dirname "$LOG")"
    printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$id" "$user" "$accion" >> "$LOG"
}

# @brief Adjunta un error a error.log + stderr (no sale del programa).
# Formato: fecha/hora + mensaje (igual date que system.log; el stderr de
# sqlite3 queda crudo con sus propios prefijos).
# @param $@ mensaje.
log_error() {
    mkdir -p "$(dirname "$ERRLOG")"
    printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$ERRLOG" >&2
}
