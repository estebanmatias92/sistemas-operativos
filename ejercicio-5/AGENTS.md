# AGENTS.md — ejercicio-5 (Lab 07 Arquitectura de Capas / Web RPC)

Base: `ejercicio-4` (Lab 06: capas `ui → api → model → config`, SQLite, logs, reporte, CLI/TUI).
Objetivo: `ejercicio-5` con las mismas capas + una interfaz web (`lib/web/`) sobre HTTP + JSON-RPC 2.0, conservando `CLI`/`TUI` y el ejemplo del profesor.

## Idea (no romper)

La app ya tiene dos clients (`--cli`, `--tui`) sobre una misma API. La web es un **tercer client de presentación**: traduce HTTP/JSON-RPC a llamadas de `lib/api/`; no arma SQL ni duplica reglas. El flujo sigue siendo `web → api → model → config` (`logging` cross-cutting, `validators`/`crypto` puros). `socat` abre el puerto y hace `fork` por conexión: **no hay estado en memoria compartida**; la sesión vive en archivo y los datos en SQLite.

## Ejemplo del profesor (solo referencia)

`bash-web-rpc-server/` es el ejemplo didáctico (`server.sh` + `static/index.html`). **No borrar, no modificar, no usar como `static/` de la app.** Anatomía:

| Función | Rol |
|---|---|
| `http_load_headers` | Lee request line + headers desde stdin. |
| `http_load_request` | Lee el body según `Content-Length` (tope 512 KB). |
| `rpc_load_request` | Valida JSON y extrae `jsonrpc`, `method`, `id`, `params`. |
| `http_process_request` | `GET`: resuelve archivo en `static/`, MIME, tamaño y path traversal. |
| `rpc_process_request` | Dispatch por `RPC_PUBLIC_HANDLER` / `RPC_PRIVATE_HANDLER`. |
| `rpc_load_response` | Arma el envelope `result`/`error` con `jq`. |
| `http_send_headers` / `http_send_response` | Escribe la respuesta y cierra (`Connection: close`). |
| `main_dispatch` | Sin args: banner + `socat TCP-LISTEN:PORT,reuseaddr,fork EXEC:"$0 --handle-request"`; también `--check`, `--help`, `--version`. |

Al adaptarlo: funciones con guarda (`_X_LOADED`), sin código top-level y sin `exit` dentro de `lib/`; la única lista de `source` va en `bin/server`.

## Contratos heredados (no cambiar sin avisar)

- `data.sq3` es la fuente de verdad; la crea `scripts/deploy.sh` (`make init`); el runtime solo `require_db` (nunca crea schema).
- Schema: `usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL)`; `productos(id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT NOT NULL, precio TEXT NOT NULL)`.
- IDs autogenerados; `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`, `RE_REF_ID='^[0-9]+$'`; `hash` SHA-256 hex 64, nunca texto plano.
- `system.log`: `fecha/hora<TAB>id<TAB>usuario<TAB>acción` por éxito. `error.log`: todo error de ejecución. `Cancel/Esc` en TUI nunca es error.
- `productos.html`: título + `<table>` con `ID, Nombre, Precio`.
- Mensajes visibles de `CLI`/`TUI` no cambian. `return 0/1` dentro de `lib/`; `exit` solo en entrypoints.
- Solo `lib/model/` invoca `sqlite3`; solo `lib/ui/` invoca `whiptail` y `read -rp`/`read -rsp`.
- SQL: keywords en MAYÚSCULAS, identificadores en minúsculas, una sentencia por invocación, valores siempre por `sql_escape`, sin `SELECT *`.

## Layout objetivo

```text
ejercicio-5/
  ejercicio-5.sh        # STUB de entrega -> bin/app (CLI/TUI)
  server.sh             # STUB de entrega -> bin/server (web)
  bin/app               # entrypoint CLI/TUI (heredado)
  bin/server            # entrypoint web (nueva única lista de sources)
  lib/
    config.sh           # + HTTP_*/SESSION_* (rutas mutables, spec inmutable)
    validators.sh
    crypto.sh
    logging.sh
    model/              # db.sh, products_store.sh, users_store.sh (único sqlite3)
    api/                # products_api.sh, auth_api.sh, report_api.sh (+ *_data)
    ui/                 # cli.sh, tui.sh, dispatch.sh (heredado)
    web/                # http.sh, rpc.sh, handlers.sh, session.sh, dispatch.sh
  static/               # index.html, app.js, styles.css, favicon.ico
  sql/, scripts/, tests/, var/
  bash-web-rpc-server/  # ejemplo del profesor (intacto)
```

`bin/server` carga en orden: `config → validators → crypto → logging → model/* → api/* → web/session → web/http → web/rpc → web/handlers → web/dispatch` y llama `main "$@"`. `server.sh` es un stub que delega en `bin/server` (misma idea que `ejercicio-5.sh` → `bin/app`).

## Capa web (nueva)

- `lib/web/http.sh`: `http_load_headers`, `http_load_request`, `http_set_status`, `http_set_header`, `http_set_body`, `file_mimetype`, `http_process_static`, `http_not_found`, `http_send_headers`, `http_send_response`; globals `HTTP_*`.
- `lib/web/rpc.sh`: `rpc_load_request`, `rpc_success`, `rpc_error`, errores estándar, `rpc_load_registry`, `rpc_process_request`, `rpc_load_response`; globals `RPC_*`.
- `lib/web/handlers.sh`: `rpc_handle_*` (un handler por método); leen `RPC_REQUEST_PARAMS` y `RPC_SESSION_UID/USER`.
- `lib/web/session.sh`: `session_create`, `session_validate`, `session_revoke`, `session_cleanup`.
- `lib/web/dispatch.sh`: `main`, `server_main`, `server_handle_request`, `server_check_dependencies`, `server_show_help`.

Reglas: `lib/web` puede usar `jq`, `realpath`, `stat`, `wc`, `head`, `date`, `mkdir`, `flock`, `sha256sum`; **no** `sqlite3` (solo `lib/model`) ni `whiptail` (solo `lib/ui`). `socat` solo en `lib/web/dispatch.sh`/`bin/server`.

`GET` sirve `static/` y, para el reporte, `/report/productos.html` se resuelve contra `var/report/` (misma protección de path traversal). `POST /` es JSON-RPC. El resto de métodos HTTP → `-32005` con HTTP 200. El servidor escucha en `HTTP_SERVER_HOST` (default `0.0.0.0`, como el ejemplo) y `HTTP_SERVER_PORT` (default `8080`); ambos configurables por env. Para uso local: `HTTP_SERVER_HOST=127.0.0.1`.

## Superficie RPC

| Método | Tipo | Params | Result |
|---|---|---|---|
| `saludar` | público | — | `"Saludos desde el servidor en bash!"` |
| `auth.register` | público | `{username, password}` | `{uid, username}` |
| `auth.login` | público | `{username, password}` | `{token, uid, username, expires_at}` |
| `auth.logout` | privado | `{token}` | `{ok: true}` |
| `products.list` | privado | `{token}` | `{products: [{id, nombre, precio}]}` |
| `products.add` | privado | `{token, nombre, precio}` | `{id, nombre, precio}` |
| `products.update` | privado | `{token, id, nombre, precio}` | `{id, nombre, precio}` |
| `products.remove` | privado | `{token, id}` | `{id}` |
| `report.generate` | privado | `{token}` | `{path, url}` |

Códigos: `-32700` parse, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal, `-32001` unauthorized, `-32002` invalid credentials, `-32003` not found, `-32004` conflict, `-32005` method not allowed. Los errores de aplicación responden HTTP 200 con envelope `error` (igual que el ejemplo); solo los fallos de transporte/estáticos usan 4xx.

`rpc_load_registry` registra públicos (`saludar`, `auth.register`, `auth.login`) en `RPC_PUBLIC_HANDLER` y privados (`auth.logout`, `products.*`, `report.generate`) en `RPC_PRIVATE_HANDLER`. `rpc_process_request` valida el token de los privados **antes** de invocar el handler, setea `RPC_SESSION_UID`/`RPC_SESSION_USER` y responde `-32001` si falta o expiró. Los handlers no vuelven a chequear el token.

## Sesión (fork-safe)

- `SESSION_DIR="${SESSION_DIR:-var/session}"`, `SESSIONS_FILE="${SESSIONS_FILE:-$SESSION_DIR/sessions.tsv}"`, `SESSION_TTL="${SESSION_TTL:-3600}"`.
- Token: `head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1`.
- Formato: `token<TAB>uid<TAB>username<TAB>expires_at` (epoch). `auth.login` devuelve el token y `expires_at`; `auth.logout` lo revoca; `session_cleanup` borra vencidos.
- Concurrencia: `flock` sobre `"$SESSIONS_FILE.lock"`; revoke/cleanup con archivo temporal + `mv` (nunca `sed -i` sobre `data.sq3`).
- Permisos: `SESSION_DIR` `700`, `sessions.tsv` `600`.
- Nunca loguear tokens ni contraseñas. `var/session/` va en `.gitignore`.

## API con datos estructurados

Agregar variantes `*_data` que devuelvan datos por stdout (TSV/valores) y conservar las funciones actuales como formateadores exactos de `CLI`/`TUI`:

- `add_product_data nombre precio uid user` → `id`; auditoría `alta id="N"`.
- `list_products_data uid user` → filas `id<TAB>nombre<TAB>precio`; auditoría `listado`.
- `update_product_data id nombre precio uid user` → `id`; auditoría `edición id="N"`.
- `remove_product_data id uid user` → `id`; auditoría `baja id="N"`.
- `register_user_data user pass` → `uid<TAB>user`; auditoría `registro username="..."`.
- `login_user_data user pass` → `uid<TAB>user`; auditoría `login username="..."` (fallo silencioso, sin log).
- `generate_report_data uid user` → `path`; auditoría `reporte`.

`add_product`, `list_products`, `update_product`, `remove_product`, `register_user`, `login_user`, `generate_report` pasan a llamar a `*_data` y mantienen **exactamente** sus mensajes. Los handlers web arman JSON con `jq` a partir del TSV; no parsean texto humano.

Códigos de retorno de `*_data` (los handlers mapean a códigos RPC sin duplicar reglas):
`0` ok · `10` dato inválido (`-32602`) · `11` conflicto/inexistente/credenciales (`-32004`/`-32003`/`-32002`) · `12` error interno (`-32603`). Las funciones históricas traducen cualquier fallo a `return 1`.

## UI estática

`static/index.html` + `static/app.js` + `static/styles.css`: **UI end-user**, no panel de pruebas. Pantalla de acceso (login/registro), cabecera con usuario y logout, tabla de inventario, formulario de alta/edición, confirmación de baja, botón de reporte y mensajes de estado. Sin panel de JSON crudo ni tabla de procedimientos RPC: eso queda en el ejemplo del profesor (`bash-web-rpc-server/static/index.html`), que no se toca. `fetch('/', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({jsonrpc:'2.0', method, params, id})})`. El token se guarda en `sessionStorage` y viaja en `params.token`; no se usa cookie ni CORS (mismo origen). El reporte se abre con `url` devuelta por `report.generate`. Los datos se pintan con `textContent`, nunca `innerHTML`.

## Makefile y `make check`

- Targets nuevos: `run-web` (`./server.sh`), `run-web-dev` (`./bin/server`); `build`/`check`/`fmt` incluyen `server.sh`, `bin/server` y `lib/web/*.sh`.
- `check` debe verificar: `bash -n` de entrypoints y módulos; `sqlite3` solo en `lib/model`; `whiptail` solo en `lib/ui`; `read -rp`/`read -rsp` solo en `lib/ui`; `socat` solo en `bin/server`/`lib/web/dispatch.sh`; `jq` solo en `lib/web`.
- `make init` sigue siendo el único dueño de `data.sq3`; `make test` corre bats sin TTY.

## Verificación

```bash
make init && make check && make test
./server.sh --check
./server.sh                 # o make run-web; escucha en 8080 (0.0.0.0)
HTTP_SERVER_HOST=127.0.0.1 ./server.sh   # solo local
curl -s http://localhost:8080/ | head
curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"saludar"}'
curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"products.list","params":{"token":"..."}}'
printf 'GET /../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n' | ./bin/server --handle-request   # 404
./ejercicio-5.sh --cli      # regresión CLI
./ejercicio-5.sh            # regresión TUI
```

Pruebas bats nuevas (`tests/web_rpc.bats`): envelope (`jsonrpc`/`id`/`params`), errores estándar, público vs privado, token inválido/vencido, CRUD vía handlers, reporte y path traversal. Aislar `DB`, `LOG`, `ERRLOG`, `SESSION_DIR` con `mktemp -d`.

## Guardrails / pitfalls

- **No** tocar `bash-web-rpc-server/`; **no** usarlo como `static/` de la app.
- **No** copiar `AGENTS.md`/`HANDOFF.md`/`README.md` de `ejercicio-4` encima de los de `ejercicio-5` (el paso 0 excluye esos archivos).
- `set -e` + `read`: `read -r`/`read -N` pueden devolver != 0 en EOF; proteger con `if ! read ...` o `|| true`.
- `stdout` de `--handle-request` es **solo** la respuesta HTTP; logs y diagnósticos van a `stderr`/`error.log`.
- `Content-Length` en bytes, no caracteres: `wc -c` para UTF-8.
- `socat` hace `fork`: nada de arrays/estado global para sesión; usar archivo/DB.
- Path traversal: `realpath -m` + prefijo con `/` final; rechazar `..`.
- Body > 512 KB: `413` y cerrar; JSON inválido: `-32700`.
- Notificaciones (sin `id`) y batch (array) fuera de alcance; documentarlo en README.
- No `sed -i`, `awk` ni `grep` sobre `data.sq3`; `grep` solo sobre logs.
- No loguear secretos; tokens y contraseñas nunca en `system.log`/`error.log` ni en respuestas.

## Trabajo con el usuario

- Entender antes de implementar; micro-pasos con código + explicación breve, probar y recién avanzar.
- No cambiar contratos, menúes ni mensajes visibles sin avisar.
- Mantener `CLI`/`TUI` como referencia de transparencia; la web no debe romperlos.
- Commits por checkpoint en el repo `sistemas-operativos` (branch `main`); no push sin confirmación.
