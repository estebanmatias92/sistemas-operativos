# lib/web/rpc.sh — envelope JSON-RPC 2.0 sobre HTTP (capa web).
# Valida el request, resuelve el handler en el registry y arma result/error.
# Los errores de aplicación viajan con HTTP 200; el transporte (4xx) es http.sh.
# Nunca loguea bodies (pueden traer contraseñas).

[[ -n "${_WEB_RPC_LOADED:-}" ]] && return 0
declare -g _WEB_RPC_LOADED=1

if [[ -z "${HTTP_STATIC_PATH:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# --- Request desglosado ---
declare -g RPC_REQUEST_OBJECT=""
declare -g RPC_REQUEST_VALID=false
declare -g RPC_JSONRPC=""
declare -g RPC_REQUEST_METHOD=""
declare -g RPC_REQUEST_ID="null"
declare -g RPC_REQUEST_PARAMS="null"

# --- Response desglosada ---
declare -g RPC_RESPONSE_OBJECT=""
declare -g RPC_RESPONSE_READY=false
declare -g RPC_RESPONSE_JSONRPC="2.0"
declare -g RPC_RESPONSE_ID="null"
declare -g RPC_RESPONSE_RESULT=""
declare -g RPC_RESPONSE_ERROR=""

# --- Sesión resuelta por el layer RPC (fork-safe, desde archivo) ---
declare -g RPC_SESSION_UID=""
declare -g RPC_SESSION_USER=""

# --- Registry de métodos ---
declare -gA RPC_PUBLIC_HANDLER
declare -gA RPC_PRIVATE_HANDLER

# @brief Reset del estado de respuesta (cada request es un proceso nuevo).
rpc_reset_response() {
    RPC_RESPONSE_OBJECT=""
    RPC_RESPONSE_READY=false
    RPC_RESPONSE_JSONRPC="2.0"
    RPC_RESPONSE_ID="null"
    RPC_RESPONSE_RESULT=""
    RPC_RESPONSE_ERROR=""
}

# @brief Arma un result exitoso (JSON válido o string seguro).
# @param $1 result JSON, $2 id opcional (default RPC_REQUEST_ID).
rpc_success() {
    local data="${1:-null}"
    local req_id="${2:-$RPC_REQUEST_ID}"
    [[ -z "$req_id" ]] && req_id="null"

    if ! jq -e . >/dev/null 2>&1 <<<"$data"; then
        data="$(jq -nc --arg s "$data" '$s')"
    fi
    RPC_RESPONSE_ID="$req_id"
    RPC_RESPONSE_RESULT="$data"
    RPC_RESPONSE_ERROR=""
    RPC_RESPONSE_READY=true
}

# @brief Arma un error JSON-RPC con data opcional (JSON o string).
# @param $1 código, $2 mensaje, $3 data, $4 id opcional.
rpc_error() {
    local code="$1"
    local message="$2"
    local details="${3:-null}"
    local req_id="${4:-$RPC_REQUEST_ID}"
    [[ -z "$req_id" ]] && req_id="null"

    if [[ "$details" != "null" ]] && ! jq -e . >/dev/null 2>&1 <<<"$details"; then
        details="$(jq -nc --arg s "$details" '$s')"
    fi
    RPC_RESPONSE_ID="$req_id"
    RPC_RESPONSE_RESULT=""
    RPC_RESPONSE_ERROR="$(jq -nc \
        --argjson code "$code" \
        --arg msg "$message" \
        --argjson data "$details" \
        '{code: $code, message: $msg, data: $data}')"
    RPC_RESPONSE_READY=true
}

# --- Errores estándar (códigos del lab) ---
rpc_parse_error() { rpc_error -32700 "Parse error" "${1:-null}"; }
rpc_invalid_request() { rpc_error -32600 "Invalid Request" "${1:-null}"; }
rpc_method_not_found() { rpc_error -32601 "Method not found" "${1:-null}"; }
rpc_invalid_params() { rpc_error -32602 "Invalid params" "${1:-null}"; }
rpc_internal_error() { rpc_error -32603 "Internal error" "${1:-null}"; }
rpc_unauthorized() { rpc_error -32001 "Unauthorized" "${1:-null}"; }
rpc_invalid_credentials() { rpc_error -32002 "Invalid credentials" "${1:-null}"; }
rpc_not_found() { rpc_error -32003 "Not found" "${1:-null}"; }
rpc_conflict() { rpc_error -32004 "Conflict" "${1:-null}"; }
rpc_method_not_allowed() { rpc_error -32005 "Method Not Allowed" "${1:-null}"; }

# @brief Valida JSON y extrae jsonrpc/method/id/params.
# @return 0 request válido / 1 error de parseo o envelope inválido (respuesta seteada).
rpc_load_request() {
    local body="$HTTP_REQUEST_BODY"

    RPC_REQUEST_OBJECT=""
    RPC_REQUEST_VALID=false
    RPC_JSONRPC=""
    RPC_REQUEST_METHOD=""
    RPC_REQUEST_ID="null"
    RPC_REQUEST_PARAMS="null"
    RPC_SESSION_UID=""
    RPC_SESSION_USER=""
    rpc_reset_response

    if [[ -z "$body" ]] || ! jq -e . >/dev/null 2>&1 <<<"$body"; then
        rpc_parse_error
        return 1
    fi
    RPC_REQUEST_OBJECT="$body"

    if [[ "$(jq -r 'type' <<<"$RPC_REQUEST_OBJECT" 2>/dev/null || true)" != "object" ]]; then
        rpc_invalid_request "Se esperaba un objeto JSON-RPC (batch fuera de alcance)."
        return 1
    fi

    RPC_JSONRPC="$(jq -r '.jsonrpc // ""' <<<"$RPC_REQUEST_OBJECT" 2>/dev/null || true)"
    RPC_REQUEST_METHOD="$(jq -r '.method // ""' <<<"$RPC_REQUEST_OBJECT" 2>/dev/null || true)"
    RPC_REQUEST_ID="$(jq -c '.id // null' <<<"$RPC_REQUEST_OBJECT" 2>/dev/null || echo "null")"
    RPC_REQUEST_PARAMS="$(jq -c '.params // null' <<<"$RPC_REQUEST_OBJECT" 2>/dev/null || echo "null")"

    if [[ "$RPC_JSONRPC" != "2.0" ]]; then
        rpc_invalid_request "jsonrpc debe ser \"2.0\"."
        return 1
    fi
    if ! jq -e '.method | type == "string" and length > 0' >/dev/null 2>&1 <<<"$RPC_REQUEST_OBJECT"; then
        rpc_invalid_request "Falta method (string no vacío)."
        return 1
    fi
    if ! jq -e '.id == null or (.id | type == "string") or (.id | type == "number")' >/dev/null 2>&1 <<<"$RPC_REQUEST_OBJECT"; then
        rpc_invalid_request "id debe ser string, number o null."
        return 1
    fi
    if ! jq -e '.params == null or (.params | type == "object")' >/dev/null 2>&1 <<<"$RPC_REQUEST_OBJECT"; then
        rpc_invalid_params "params debe ser objeto."
        return 1
    fi

    RPC_REQUEST_VALID=true
    return 0
}

# @brief Carga el registry de handlers públicos y privados.
# @note Se ejecuta por request porque socat fork no comparte memoria.
rpc_load_registry() {
    RPC_PUBLIC_HANDLER=()
    RPC_PRIVATE_HANDLER=()
    RPC_PUBLIC_HANDLER['saludar']='rpc_handle_saludar'
    RPC_PUBLIC_HANDLER['auth.register']='rpc_handle_auth_register'
    RPC_PUBLIC_HANDLER['auth.login']='rpc_handle_auth_login'
    RPC_PRIVATE_HANDLER['auth.logout']='rpc_handle_auth_logout'
    RPC_PRIVATE_HANDLER['products.list']='rpc_handle_products_list'
    RPC_PRIVATE_HANDLER['products.add']='rpc_handle_products_add'
    RPC_PRIVATE_HANDLER['products.update']='rpc_handle_products_update'
    RPC_PRIVATE_HANDLER['products.remove']='rpc_handle_products_remove'
    RPC_PRIVATE_HANDLER['report.generate']='rpc_handle_report_generate'
}

# @brief Resuelve el método y ejecuta el handler (público o privado).
rpc_process_request() {
    [[ "$RPC_REQUEST_VALID" == true ]] || return 0

    local method="$RPC_REQUEST_METHOD"
    local handler="${RPC_PUBLIC_HANDLER[$method]:-}"
    if [[ -n "$handler" ]]; then
        "$handler"
        return 0
    fi

    handler="${RPC_PRIVATE_HANDLER[$method]:-}"
    if [[ -n "$handler" ]]; then
        local token
        token="$(jq -r '.token // empty' <<<"$RPC_REQUEST_PARAMS" 2>/dev/null || true)"
        if [[ -z "$token" ]] || ! session_validate "$token"; then
            rpc_unauthorized
            return 0
        fi
        RPC_SESSION_UID="$SESSION_VALID_UID"
        RPC_SESSION_USER="$SESSION_VALID_USER"
        "$handler"
        return 0
    fi

    rpc_method_not_found
}

# @brief Serializa la respuesta y la monta en el layer HTTP.
rpc_load_response() {
    [[ "$RPC_RESPONSE_READY" == true ]] || rpc_internal_error

    if [[ -n "$RPC_RESPONSE_ERROR" ]]; then
        RPC_RESPONSE_OBJECT="$(jq -nc \
            --arg jsonrpc "$RPC_RESPONSE_JSONRPC" \
            --argjson error "$RPC_RESPONSE_ERROR" \
            --argjson id "$RPC_RESPONSE_ID" \
            '{jsonrpc: $jsonrpc, error: $error, id: $id}')"
    else
        RPC_RESPONSE_OBJECT="$(jq -nc \
            --arg jsonrpc "$RPC_RESPONSE_JSONRPC" \
            --argjson result "$RPC_RESPONSE_RESULT" \
            --argjson id "$RPC_RESPONSE_ID" \
            '{jsonrpc: $jsonrpc, result: $result, id: $id}')"
    fi

    http_set_status 200
    http_set_header "Content-Type" "application/json; charset=utf-8"
    http_set_header "Cache-Control" "no-store"
    http_set_body "$RPC_RESPONSE_OBJECT"
}
