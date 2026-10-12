# lib/logging.sh — cross-cutting. Cualquier capa lo llama; nunca importa ui ni db.
# Formato system.log: fecha/hora<TAB>id<TAB>usuario<TAB>acción

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
