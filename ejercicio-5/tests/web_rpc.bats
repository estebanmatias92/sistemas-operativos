# tests/web_rpc.bats — ejecuta: make test
# Cubre la capa web end-to-end por stdio (sin socat): HTTP estático + JSON-RPC,
# sesión fork-safe, CRUD, reporte y path traversal. Aísla DB/logs/sesión.

setup() {
    TMPDIR_TEST="$(mktemp -d)"
    export DB="$TMPDIR_TEST/test.sq3"
    export LOG="$TMPDIR_TEST/system.log"
    export ERRLOG="$TMPDIR_TEST/error.log"
    export PRODUCTS_HTML="$TMPDIR_TEST/report/productos.html"
    export SESSION_DIR="$TMPDIR_TEST/session"
    unset SESSIONS_FILE SESSION_TTL HTTP_SERVER_HOST HTTP_SERVER_PORT
    APP="$BATS_TEST_DIRNAME/.."
    "$APP/scripts/deploy.sh" --no-seed >/dev/null
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

# @brief Envía un request HTTP crudo y devuelve la respuesta completa.
http_raw() {
    printf '%s' "$1" | "$APP/bin/server" --handle-request
}

# @brief POST JSON-RPC con Content-Length en bytes.
rpc_call() {
    local body="$1"
    local length
    length="$(printf '%s' "$body" | wc -c)"
    http_raw "$(printf 'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: %s\r\n\r\n%s' "$length" "$body")"
}

# @brief Extrae el body JSON de una respuesta HTTP.
rpc_json() {
    local response
    response="$(rpc_call "$1")"
    printf '%s' "${response#*$'\r\n\r\n'}"
}

# @brief GET de un path y respuesta completa.
http_get() {
    http_raw "$(printf 'GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n' "$1")"
}

# @brief Registra y loguea un usuario; imprime el token.
login_token() {
    local user="$1"
    local pass="$2"
    rpc_json "$(printf '{"jsonrpc":"2.0","id":1,"method":"auth.register","params":{"username":"%s","password":"%s"}}' "$user" "$pass")" >/dev/null
    rpc_json "$(printf '{"jsonrpc":"2.0","id":2,"method":"auth.login","params":{"username":"%s","password":"%s"}}' "$user" "$pass")" | jq -r '.result.token'
}

@test "GET / sirve static/index.html con MIME correcto" {
    run http_get "/"
    [ "$status" -eq 0 ]
    [[ "$output" == "HTTP/1.1 200 OK"* ]]
    [[ "$output" == *"Content-Type: text/html; charset=utf-8"* ]]
    [[ "$output" == *"<!DOCTYPE html>"* ]]
}

@test "GET assets: js, css y favicon con su MIME" {
    run bash -c "printf 'GET /app.js HTTP/1.1\r\nHost: x\r\n\r\n' | '$APP/bin/server' --handle-request"
    [[ "$output" == *"Content-Type: application/javascript; charset=utf-8"* ]]
    run bash -c "printf 'GET /styles.css HTTP/1.1\r\nHost: x\r\n\r\n' | '$APP/bin/server' --handle-request"
    [[ "$output" == *"Content-Type: text/css; charset=utf-8"* ]]
    run bash -c "printf 'GET /favicon.ico HTTP/1.1\r\nHost: x\r\n\r\n' | '$APP/bin/server' --handle-request"
    [[ "$output" == *"Content-Type: image/x-icon"* ]]
}

@test "GET inexistente y path traversal devuelven 404" {
    run http_get "/no-existe"
    [[ "$output" == "HTTP/1.1 404 Not Found"* ]]
    run http_get "/../etc/passwd"
    [[ "$output" == "HTTP/1.1 404 Not Found"* ]]
    run http_get "/report/../etc/passwd"
    [[ "$output" == "HTTP/1.1 404 Not Found"* ]]
}

@test "saludar: envelope 2.0 con result e id preservado" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":7,"method":"saludar"}')"
    [ "$(jq -r '.jsonrpc' <<<"$result")" = "2.0" ]
    [ "$(jq -r '.id' <<<"$result")" = "7" ]
    [ "$(jq -r '.result' <<<"$result")" = "Saludos desde el servidor en bash!" ]
    [ "$(jq -r 'has("error")' <<<"$result")" = "false" ]
}

@test "id string se preserva en la respuesta" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":"abc","method":"no_existe"}')"
    [ "$(jq -r '.id' <<<"$result")" = "abc" ]
    [ "$(jq -r '.error.code' <<<"$result")" = "-32601" ]
}

@test "JSON inválido responde -32700" {
    result="$(rpc_json '{')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32700" ]
    [ "$(jq -r '.id' <<<"$result")" = "null" ]
}

@test "request sin method responde -32600" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":2}')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32600" ]
}

@test "jsonrpc distinto de 2.0 responde -32600" {
    result="$(rpc_json '{"jsonrpc":"1.0","id":2,"method":"saludar"}')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32600" ]
}

@test "batch array fuera de alcance responde -32600" {
    result="$(rpc_json '[{"jsonrpc":"2.0","id":1,"method":"saludar"}]')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32600" ]
}

@test "method inexistente responde -32601" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":3,"method":"no_existe"}')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32601" ]
}

@test "params array responde -32602" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":4,"method":"saludar","params":[1]}')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32602" ]
}

@test "método privado sin token responde -32001" {
    result="$(rpc_json '{"jsonrpc":"2.0","id":5,"method":"products.list","params":{}}')"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32001" ]
}

@test "register/login/logout completo y token revocado" {
    reg="$(rpc_json '{"jsonrpc":"2.0","id":1,"method":"auth.register","params":{"username":"ana","password":"pw1"}}')"
    [ "$(jq -r '.result.username' <<<"$reg")" = "ana" ]
    [ "$(jq -r '.result.uid' <<<"$reg")" -gt 0 ]

    dup="$(rpc_json '{"jsonrpc":"2.0","id":2,"method":"auth.register","params":{"username":"ana","password":"pw1"}}')"
    [ "$(jq -r '.error.code' <<<"$dup")" = "-32004" ]

    bad="$(rpc_json '{"jsonrpc":"2.0","id":3,"method":"auth.login","params":{"username":"ana","password":"mal"}}')"
    [ "$(jq -r '.error.code' <<<"$bad")" = "-32002" ]

    login="$(rpc_json '{"jsonrpc":"2.0","id":4,"method":"auth.login","params":{"username":"ana","password":"pw1"}}')"
    token="$(jq -r '.result.token' <<<"$login")"
    [[ "$token" =~ ^[0-9a-f]{64}$ ]]
    [ "$(jq -r '.result.username' <<<"$login")" = "ana" ]
    [ "$(jq -r '.result.expires_at' <<<"$login")" -gt "$(date +%s)" ]

    [ "$(stat -c%a "$SESSION_DIR")" = "700" ]
    [ "$(stat -c%a "$SESSION_DIR/sessions.tsv")" = "600" ]
    [ "$(awk -F'\t' 'NF == 4 { n++ } END { print n+0 }' "$SESSION_DIR/sessions.tsv")" -eq 1 ]

    out="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"auth.logout\",\"params\":{\"token\":\"$token\"}}")"
    [ "$(jq -r '.result.ok' <<<"$out")" = "true" ]

    replay="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"auth.logout\",\"params\":{\"token\":\"$token\"}}")"
    [ "$(jq -r '.error.code' <<<"$replay")" = "-32001" ]
}

@test "token vencido responde -32001" {
    export SESSION_TTL=-1
    token="$(login_token "vencido" "pw")"
    [[ -n "$token" && "$token" != "null" ]]
    result="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"products.list\",\"params\":{\"token\":\"$token\"}}")"
    [ "$(jq -r '.error.code' <<<"$result")" = "-32001" ]
}

@test "CRUD de productos completo por RPC" {
    token="$(login_token "carla" "pw")"

    add1="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"products.add\",\"params\":{\"token\":\"$token\",\"nombre\":\"escoba\",\"precio\":\"3000\"}}")"
    id1="$(jq -r '.result.id' <<<"$add1")"
    [ "$(jq -r '.result.nombre' <<<"$add1")" = "escoba" ]

    add2="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"products.add\",\"params\":{\"token\":\"$token\",\"nombre\":\"balde\",\"precio\":\"2000.50\"}}")"
    [ "$(jq -r '.result.id' <<<"$add2")" -gt "$id1" ]

    list="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"products.list\",\"params\":{\"token\":\"$token\"}}")"
    [ "$(jq -r '.result.products | length' <<<"$list")" -eq 2 ]
    [ "$(jq -r '.result.products[0].nombre' <<<"$list")" = "escoba" ]

    upd="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"products.update\",\"params\":{\"token\":\"$token\",\"id\":$id1,\"nombre\":\"escoba nueva\",\"precio\":\"3500\"}}")"
    [ "$(jq -r '.result.nombre' <<<"$upd")" = "escoba nueva" ]

    del="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"products.remove\",\"params\":{\"token\":\"$token\",\"id\":$id1}}")"
    [ "$(jq -r '.result.id' <<<"$del")" = "$id1" ]

    again="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"products.remove\",\"params\":{\"token\":\"$token\",\"id\":$id1}}")"
    [ "$(jq -r '.error.code' <<<"$again")" = "-32003" ]
}

@test "productos: precio inválido -32602 y update inexistente -32003" {
    token="$(login_token "dani" "pw")"

    invalid="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"products.add\",\"params\":{\"token\":\"$token\",\"nombre\":\"x\",\"precio\":\"abc\"}}")"
    [ "$(jq -r '.error.code' <<<"$invalid")" = "-32602" ]

    missing="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"products.update\",\"params\":{\"token\":\"$token\",\"id\":999,\"nombre\":\"x\",\"precio\":\"1\"}}")"
    [ "$(jq -r '.error.code' <<<"$missing")" = "-32003" ]

    bad_id="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"products.remove\",\"params\":{\"token\":\"$token\",\"id\":\"1 OR 1=1\"}}")"
    [ "$(jq -r '.error.code' <<<"$bad_id")" = "-32602" ]
}

@test "report.generate devuelve path/url y sirve el HTML con tabla" {
    token="$(login_token "elena" "pw")"
    rpc_json "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"products.add\",\"params\":{\"token\":\"$token\",\"nombre\":\"escoba\",\"precio\":\"3000\"}}" >/dev/null
    report="$(rpc_json "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"report.generate\",\"params\":{\"token\":\"$token\"}}")"
    [ "$(jq -r '.result.url' <<<"$report")" = "/report/productos.html" ]
    path="$(jq -r '.result.path' <<<"$report")"
    [ -f "$path" ]
    grep -q "<th>ID</th><th>Nombre</th><th>Precio</th>" "$path"

    run http_get "/report/productos.html"
    [[ "$output" == "HTTP/1.1 200 OK"* ]]
    [[ "$output" == *"<td>1</td><td>escoba</td><td>3000</td>"* ]]
}

@test "método HTTP no soportado responde -32005 con HTTP 200" {
    response="$(http_raw $'PUT / HTTP/1.1\r\nHost: localhost\r\n\r\n')"
    [[ "$response" == "HTTP/1.1 200 OK"* ]]
    body="${response#*$'\r\n\r\n'}"
    [ "$(jq -r '.error.code' <<<"$body")" = "-32005" ]
}

@test "body mayor a 512 KB responde 413" {
    response="$(http_raw $'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 524289\r\n\r\n')"
    [[ "$response" == "HTTP/1.1 413 Payload Too Large"* ]]
}

@test "Content-Length inválido responde 400" {
    response="$(http_raw $'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: abc\r\n\r\n')"
    [[ "$response" == "HTTP/1.1 400 Bad Request"* ]]
}

@test "logs no contienen contraseñas ni tokens" {
    token="$(login_token "secreta" "pw-super-secreta")"
    rpc_json "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"auth.logout\",\"params\":{\"token\":\"$token\"}}" >/dev/null

    run grep -F "pw-super-secreta" "$LOG" "$ERRLOG"
    [ "$status" -ne 0 ]
    run grep -F "$token" "$LOG" "$ERRLOG"
    [ "$status" -ne 0 ]
    run grep -F "secreta" "$LOG"
    [ "$status" -eq 0 ]
}

@test "auditoría web conserva el formato TSV y las acciones del CLI" {
    token="$(login_token "fede" "pw")"
    rpc_json "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"products.add\",\"params\":{\"token\":\"$token\",\"nombre\":\"escoba\",\"precio\":\"3000\"}}" >/dev/null
    rpc_json "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"products.list\",\"params\":{\"token\":\"$token\"}}" >/dev/null
    rpc_json "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"report.generate\",\"params\":{\"token\":\"$token\"}}" >/dev/null

    grep -q $'\tfede\talta id="1"$' "$LOG"
    grep -q $'\tfede\tlistado$' "$LOG"
    grep -q $'\tfede\treporte$' "$LOG"
    [ "$(awk -F'\t' 'NF != 4 { bad++ } END { print bad+0 }' "$LOG")" -eq 0 ]
}
