# lib/web/http.sh — transporte HTTP/1.1 (capa web, solo stdio).
# Lee un request desde stdin y escribe la respuesta por stdout.
# No conoce SQLite ni la API: el dispatch decide qué procesar.
# Socat hace fork por conexión; no hay estado compartido entre requests.

[[ -n "${_WEB_HTTP_LOADED:-}" ]] && return 0
declare -g _WEB_HTTP_LOADED=1

if [[ -z "${HTTP_STATIC_PATH:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# --- Request (entrada) ---
declare -gA HTTP_REQUEST_HEADERS
declare -g HTTP_REQUEST_METHOD=""
declare -g HTTP_REQUEST_PATH=""
declare -g HTTP_REQUEST_PROTOCOL=""
declare -g HTTP_REQUEST_BODY=""
declare -g HTTP_REQUEST_FILEPATH=""

# --- Response (salida) ---
declare -g HTTP_RESPONSE_STATUS=""
declare -gA HTTP_RESPONSE_HEADERS
declare -g HTTP_RESPONSE_BODY=""
declare -g HTTP_RESPONSE_IS_PATH=false

# @brief Limpia el estado de la respuesta (cada request es un proceso nuevo).
http_reset_response() {
    HTTP_RESPONSE_STATUS=""
    HTTP_RESPONSE_HEADERS=()
    HTTP_RESPONSE_BODY=""
    HTTP_RESPONSE_IS_PATH=false
    HTTP_REQUEST_FILEPATH=""
}

# @brief Setea el status line con su razón estándar.
# @param $1 código HTTP (200, 400, 404, 405, 413, 500).
http_set_status() {
    local code="$1"
    local reason
    case "$code" in
        200) reason="OK" ;;
        400) reason="Bad Request" ;;
        404) reason="Not Found" ;;
        405) reason="Method Not Allowed" ;;
        413) reason="Payload Too Large" ;;
        500) reason="Internal Server Error" ;;
        *) reason="Status" ;;
    esac
    HTTP_RESPONSE_STATUS="HTTP/1.1 $code $reason"
}

# @brief Agrega/reemplaza un header de respuesta.
# @param $1 nombre, $2 valor.
http_set_header() {
    local name="$1"
    local value="$2"
    HTTP_RESPONSE_HEADERS["$name"]="$value"
}

# @brief Setea el body de la respuesta (texto o ruta a archivo).
# @param --path $1 ruta (opcional) | $1 texto.
# @param $2 ruta cuando se usa --path.
http_set_body() {
    if [[ "${1:-}" == "--path" ]]; then
        HTTP_RESPONSE_BODY="${2:-$HTTP_REQUEST_FILEPATH}"
        HTTP_RESPONSE_IS_PATH=true
    else
        HTTP_RESPONSE_BODY="${1:-}"
        HTTP_RESPONSE_IS_PATH=false
    fi
}

# @brief Mapa MIME explícito (sin depender de xdg-mime).
# @param $1 ruta del archivo.
# @stdout Content-Type.
file_mimetype() {
    local path="${1,,}"
    case "$path" in
        *.html | *.htm) printf 'text/html; charset=utf-8' ;;
        *.css) printf 'text/css; charset=utf-8' ;;
        *.js | *.mjs) printf 'application/javascript; charset=utf-8' ;;
        *.json) printf 'application/json; charset=utf-8' ;;
        *.svg) printf 'image/svg+xml' ;;
        *.ico) printf 'image/x-icon' ;;
        *.png) printf 'image/png' ;;
        *.jpg | *.jpeg) printf 'image/jpeg' ;;
        *.gif) printf 'image/gif' ;;
        *.webp) printf 'image/webp' ;;
        *.woff) printf 'font/woff' ;;
        *.woff2) printf 'font/woff2' ;;
        *.txt) printf 'text/plain; charset=utf-8' ;;
        *) printf 'application/octet-stream' ;;
    esac
}

# @brief Lee request line + headers desde stdin (CRLF tolerante).
# @return 0 request parseado / 1 sin request line.
http_load_headers() {
    local line key value
    HTTP_REQUEST_METHOD=""
    HTTP_REQUEST_PATH=""
    HTTP_REQUEST_PROTOCOL=""
    HTTP_REQUEST_HEADERS=()

    if ! IFS= read -r line; then
        return 1
    fi
    line="${line%$'\r'}"
    [[ -z "$line" ]] && return 1
    read -r HTTP_REQUEST_METHOD HTTP_REQUEST_PATH HTTP_REQUEST_PROTOCOL <<<"$line"

    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && break
        key="${line%%:*}"
        key="${key^^}"
        value="${line#*:}"
        value="${value# }"
        HTTP_REQUEST_HEADERS["$key"]="$value"
    done
    return 0
}

# @brief Lee el body según Content-Length (bytes, tope 512 KB).
# @return 0 ok / 1 header inválido (400) / 2 body demasiado grande (413).
http_load_request() {
    local length="${HTTP_REQUEST_HEADERS["CONTENT-LENGTH"]:-0}"
    HTTP_REQUEST_BODY=""

    if [[ ! "$length" =~ ^[0-9]+$ ]]; then
        http_set_status 400
        http_set_header "Content-Type" "text/plain; charset=utf-8"
        http_set_body "400 Bad Request: Content-Length inválido."
        return 1
    fi
    if ((length > HTTP_MAX_REQUEST_BODY_SIZE)); then
        http_set_status 413
        http_set_header "Content-Type" "text/plain; charset=utf-8"
        http_set_body "413 Payload Too Large: el body supera 512 KB."
        return 2
    fi
    if ((length > 0)); then
        HTTP_REQUEST_BODY="$(head -c "$length" 2>/dev/null)" || HTTP_REQUEST_BODY=""
    fi
    return 0
}

# @brief Respuesta 404 de transporte/estáticos.
http_not_found() {
    http_set_status 404
    http_set_header "Content-Type" "text/plain; charset=utf-8"
    http_set_body "404 Not Found: el archivo solicitado no existe."
}

# @brief Respuesta 400 de transporte.
http_bad_request() {
    http_set_status 400
    http_set_header "Content-Type" "text/plain; charset=utf-8"
    http_set_body "400 Bad Request: petición HTTP inválida."
}

# @brief Respuesta 405 con Allow (el dispatch RPC la reemplaza por -32005 si aplica).
http_method_not_allowed() {
    http_set_status 405
    http_set_header "Allow" "GET, POST"
    http_set_header "Content-Type" "text/plain; charset=utf-8"
    http_set_body "405 Method Not Allowed: use GET o POST."
}

# @brief Resuelve un GET contra static/ o var/report/ con anti path traversal.
# @note /report/<archivo> mapea a dirname(PRODUCTS_HTML)/<archivo>.
http_process_static() {
    local req_path="${HTTP_REQUEST_PATH%%\?*}"
    local root target canonical_root canonical_file

    [[ "$req_path" == "/" ]] && req_path="/$HTTP_DEFAULT_PATH"

    if [[ "$req_path" == "/$HTTP_REPORT_PREFIX/"* ]]; then
        root="$(dirname "$PRODUCTS_HTML")"
        target="$root/${req_path#/$HTTP_REPORT_PREFIX/}"
    else
        root="$HTTP_STATIC_PATH"
        target="$root${req_path}"
    fi

    canonical_root="$(realpath -m -- "$root" 2>/dev/null || true)"
    canonical_file="$(realpath -m -- "$target" 2>/dev/null || true)"

    # Prefijo con "/" final: evita que /var/report-otro pase como /var/report.
    if [[ -z "$canonical_root" || -z "$canonical_file" ]] \
        || [[ "$canonical_file" != "$canonical_root/"* ]] \
        || [[ ! -f "$canonical_file" ]]; then
        http_not_found
        return 0
    fi

    HTTP_REQUEST_FILEPATH="$canonical_file"
    http_set_status 200
    http_set_header "Content-Type" "$(file_mimetype "$canonical_file")"
    http_set_header "Content-Length" "$(stat -c%s -- "$canonical_file" 2>/dev/null || wc -c <"$canonical_file")"
    http_set_body --path "$canonical_file"
}

# @brief Calcula Content-Length en bytes (UTF-8 correcto).
# @stdout número de bytes del body.
http_response_length() {
    if [[ "$HTTP_RESPONSE_IS_PATH" == true && -f "$HTTP_RESPONSE_BODY" ]]; then
        stat -c%s -- "$HTTP_RESPONSE_BODY" 2>/dev/null || wc -c <"$HTTP_RESPONSE_BODY"
    else
        printf '%s' "$HTTP_RESPONSE_BODY" | wc -c | tr -d '[:space:]'
    fi
}

# @brief Escribe status line + headers + cierre de conexión (socat).
http_send_headers() {
    [[ -n "$HTTP_RESPONSE_STATUS" ]] || http_set_status 500
    http_set_header "Connection" "close"
    http_set_header "X-Content-Type-Options" "nosniff"
    [[ -n "${HTTP_RESPONSE_HEADERS["CONTENT-LENGTH"]:-}" ]] \
        || http_set_header "Content-Length" "$(http_response_length)"

    printf '%s\r\n' "$HTTP_RESPONSE_STATUS"
    local key
    for key in "${!HTTP_RESPONSE_HEADERS[@]}"; do
        printf '%s: %s\r\n' "$key" "${HTTP_RESPONSE_HEADERS[$key]}"
    done
    printf '\r\n'
}

# @brief Escribe el body (texto o archivo).
http_send_response() {
    if [[ "$HTTP_RESPONSE_IS_PATH" == true && -f "$HTTP_RESPONSE_BODY" ]]; then
        cat -- "$HTTP_RESPONSE_BODY"
    else
        printf '%s' "$HTTP_RESPONSE_BODY"
    fi
}
