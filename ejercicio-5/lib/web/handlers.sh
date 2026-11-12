# lib/web/handlers.sh — handlers RPC (un handler por método del contrato).
# Leen RPC_REQUEST_PARAMS y RPC_SESSION_UID/USER; llaman a lib/api/ y arman
# JSON con jq. No arman SQL, no repiten la validación de capas, no ven tokens
# completos (el layer RPC ya validó la sesión de los métodos privados).

[[ -n "${_WEB_HANDLERS_LOADED:-}" ]] && return 0
declare -g _WEB_HANDLERS_LOADED=1

if [[ -z "${HTTP_STATIC_PATH:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Método público de humo.
rpc_handle_saludar() {
    rpc_success "$(jq -nc --arg s 'Saludos desde el servidor en bash!' '$s')"
}
