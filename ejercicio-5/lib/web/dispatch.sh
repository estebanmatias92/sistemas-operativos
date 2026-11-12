# lib/web/dispatch.sh — dispatcher del entrypoint web (bin/server).
# `--handle-request` atiende UNA conexión por stdio (socat hace fork por request).
# Los errores de transporte/estáticos son 4xx; los de aplicación viajan en el
# envelope JSON-RPC con HTTP 200 (ver lib/web/rpc.sh).

[[ -n "${_WEB_DISPATCH_LOADED:-}" ]] && return 0
declare -g _WEB_DISPATCH_LOADED=1

if [[ -z "${HTTP_STATIC_PATH:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# @brief Dependencias del servidor web (se verifican con --check).
server_check_dependencies() {
    local deps=(socat jq realpath stat wc head flock sha256sum sqlite3)
    local cmd missing=0
    printf 'Verificando dependencias del servidor:\n'
    for cmd in "${deps[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  - %-10s (OK)\n' "$cmd"
        else
            printf '  - %-10s (No encontrada)\n' "$cmd"
            missing=1
        fi
    done
    return "$missing"
}

server_show_help() {
    printf 'Uso: %s [OPCIONES]\n' "${0##*/}"
    printf '\nOpciones:\n'
    printf '  --handle-request   Atiende una conexión por stdin/stdout (uso interno de socat).\n'
    printf '  --check            Verifica dependencias del servidor.\n'
    printf '  -h, --help         Muestra esta ayuda.\n'
    printf '  -v, --version      Muestra la versión.\n'
    printf '\nSin opciones levanta el servidor en http://%s:%s\n' "$HTTP_SERVER_HOST" "$HTTP_SERVER_PORT"
    printf '\nVariables de entorno:\n'
    printf '  HTTP_SERVER_HOST   Interfaz de escucha (default 0.0.0.0).\n'
    printf '  HTTP_SERVER_PORT   Puerto (default 8080).\n'
    printf '  DB, LOG, ERRLOG    Rutas de datos y logs (default var/...).\n'
    printf '  SESSION_DIR        Directorio de sesiones (default var/session).\n'
    printf '  SESSION_TTL        TTL en segundos (default 3600).\n'
}

# @brief Atiende un request HTTP completo por stdio y siempre retorna 0.
# @note stdout es SOLO la respuesta HTTP; diagnósticos van a stderr/error.log.
server_handle_request() {
    http_reset_response

    if ! http_load_headers; then
        http_bad_request
        http_send_headers
        http_send_response
        return 0
    fi
    if ! http_load_request; then
        http_send_headers
        http_send_response
        return 0
    fi

    server_dispatch_request
    http_send_headers
    http_send_response
    return 0
}

# @brief Atiende un POST JSON-RPC completo y monta la respuesta en HTTP.
server_handle_rpc() {
    rpc_load_registry
    if ! rpc_load_request; then
        rpc_load_response
        return 0
    fi
    rpc_process_request
    rpc_load_response
}

# @brief Decide el flujo según el método HTTP.
server_dispatch_request() {
    case "$HTTP_REQUEST_METHOD" in
        GET) http_process_static ;;
        POST) server_handle_rpc ;;
        *)
            # Método HTTP no soportado: error de aplicación con HTTP 200.
            rpc_reset_response
            rpc_method_not_allowed
            rpc_load_response
            ;;
    esac
}

# @brief Levanta socat en modo fork (sin estado compartido en memoria).
server_main() {
    require_db || return 1
    printf 'Sistemas Operativos (ISFT Nº 151) %s\n' "$HTTP_SERVER_VERSION"
    printf 'JSON-RPC 2.0 WebAPI escuchando en http://%s:%s ...\n' "$HTTP_SERVER_HOST" "$HTTP_SERVER_PORT"
    printf 'Ctrl+C para detener.\n'
    exec socat TCP-LISTEN:"$HTTP_SERVER_PORT",bind="$HTTP_SERVER_HOST",reuseaddr,fork \
        EXEC:"$APP_DIR/bin/server --handle-request"
}

main() {
    case "${1:-}" in
        "") server_main ;;
        --handle-request) server_handle_request ;;
        --check) server_check_dependencies ;;
        -h | --help) server_show_help ;;
        -v | --version) printf '%s\n' "$HTTP_SERVER_VERSION" ;;
        *)
            printf 'Opción desconocida: %s\n' "$1" >&2
            server_show_help >&2
            return 1
            ;;
    esac
}
