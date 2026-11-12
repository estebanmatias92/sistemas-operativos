# Ejercicio 5 — Lab 07 Arquitectura de Capas / Web RPC

Base: `ejercicio-4` (Lab 06: capas `ui → api → model → config`, SQLite,
`system.log`/`error.log`, reporte `productos.html`, clients CLI y TUI).

## Idea

La app ya tiene dos clients (`--cli`, `--tui`) sobre una misma API. El Lab 07
agrega un **tercer client de presentación**: una interfaz web sobre HTTP +
JSON-RPC 2.0 que traduce requests a llamadas de `lib/api/`, sin armar SQL ni
duplicar reglas.

```text
bin/app (CLI / TUI) ──┐
                      ├──> lib/api/* ──> lib/model/* ──> var/db/data.sq3
bin/server (web) ─────┘          │
                                 └── config · validators · crypto · logging
```

- `lib/web/` solo habla HTTP, JSON-RPC y sesión; no invoca `sqlite3`.
- Los handlers usan las variantes `*_data` de la API (datos por stdout) y arman
  JSON con `jq`.
- `socat` abre el puerto y hace `fork` por conexión: **no hay estado en memoria
  compartida**. La sesión vive en `var/session/sessions.tsv` y los datos en
  SQLite.

## Dependencias

```bash
sudo pacman -S bash sqlite3 jq socat bats util-linux coreutils
# opcional TUI:
sudo pacman -S libnewt   # provee whiptail
```

- `bash` 4+, `sqlite3`, `jq`, `socat`, `sha256sum`, `flock`, `realpath`,
  `stat`, `wc`, `head`.
- `bats` para tests; `whiptail` solo para `--tui`.
- Verificación: `./server.sh --check`.

## Puesta en marcha

```bash
make init                 # crea var/db/data.sq3 (schema + seed) — una vez
make check                # bash -n + reglas de capas + shfmt informativo
make test                 # suite bats (sin TTY)
./server.sh --check       # dependencias del servidor web
```

Seed de ejemplo: usuarios `matt` y `jeff` con contraseña `12345`; productos
`escoba` y `balde`.

### Interfaz web

```bash
./server.sh               # o: make run-web       (8080, 0.0.0.0)
./bin/server              # o: make run-web-dev
HTTP_SERVER_PORT=8081 ./server.sh
HTTP_SERVER_HOST=127.0.0.1 ./server.sh
```

Abrí `http://localhost:8080/`. La UI permite registrarse, iniciar sesión,
listar/agregar/editar/eliminar productos y generar el reporte HTML.

> Por defecto escucha en `0.0.0.0` (como el ejemplo del profesor), así que es
> accesible desde la red local. Para uso exclusivamente local:
> `HTTP_SERVER_HOST=127.0.0.1 ./server.sh`.

### CLI / TUI heredados

```bash
./ejercicio-5.sh --cli    # paridad Lab 05
./ejercicio-5.sh --tui    # default; requiere TTY + whiptail
./ejercicio-5.sh --help
```

`CLI` y `TUI` conservan exactamente los mismos mensajes, validaciones,
auditoría y reporte que el Lab 06 (verificado por regresión y por los tests).

## Superficie RPC

`POST /` con `Content-Type: application/json`. Todos los errores de aplicación
responden **HTTP 200** con envelope `error`; solo los fallos de
transporte/estáticos usan 4xx.

| Método | Tipo | params | result |
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

El token viaja en `params.token` (no hay cookies ni CORS: mismo origen).

### Códigos de error

| Código | Significado |
|---|---|
| `-32700` | JSON inválido |
| `-32600` | request inválido (sin `method`, `jsonrpc` ≠ `2.0`, batch) |
| `-32601` | método inexistente |
| `-32602` | params inválidos |
| `-32603` | error interno |
| `-32001` | no autorizado / token ausente, inválido o vencido |
| `-32002` | credenciales inválidas |
| `-32003` | producto inexistente |
| `-32004` | usuario duplicado |
| `-32005` | método HTTP no permitido |

### Ejemplos con `curl`

```bash
# Saludo (público)
curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"saludar"}'

# Registro y login
curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"auth.register","params":{"username":"ana","password":"secreto"}}'

TOKEN=$(curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"auth.login","params":{"username":"ana","password":"secreto"}}' \
  | jq -r '.result.token')

# CRUD
curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"products.add\",\"params\":{\"token\":\"$TOKEN\",\"nombre\":\"escoba\",\"precio\":\"3000\"}}"

curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"products.list\",\"params\":{\"token\":\"$TOKEN\"}}"

curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"products.update\",\"params\":{\"token\":\"$TOKEN\",\"id\":1,\"nombre\":\"escoba nueva\",\"precio\":\"3500\"}}"

curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"products.remove\",\"params\":{\"token\":\"$TOKEN\",\"id\":1}}"

# Reporte: devuelve {path, url}; se sirve en /report/productos.html
curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"report.generate\",\"params\":{\"token\":\"$TOKEN\"}}"
curl -s http://localhost:8080/report/productos.html

# Logout
curl -s -X POST http://localhost:8080/ -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"auth.logout\",\"params\":{\"token\":\"$TOKEN\"}}"
```

## HTTP estático

| Ruta | Origen | Notas |
|---|---|---|
| `/` | `static/index.html` | UI end-user |
| `/app.js`, `/styles.css`, `/favicon.ico` | `static/` | MIME explícito |
| `/report/productos.html` | `dirname(PRODUCTS_HTML)` | reporte generado |

`GET` resuelve con `realpath -m` + prefijo con `/` final; cualquier intento de
path traversal devuelve `404`. Otros métodos HTTP responden `-32005` con HTTP
200. Bodies mayores a 512 KB devuelven `413`.

## Sesión

- Archivo: `var/session/sessions.tsv` (`token<TAB>uid<TAB>username<TAB>expires_at`).
- Token: 32 bytes de `/dev/urandom` hasheados con SHA-256 (64 hex).
- TTL: `SESSION_TTL` (default 3600 s = 1 h).
- Concurrencia: `flock` compartido para validar, exclusivo para crear/revocar/
  limpiar; revocación y limpieza con archivo temporal + `mv`.
- Permisos: directorio `700`, archivo `600`.
- `var/session/` está en `.gitignore`. Los tokens y contraseñas **nunca** se
  escriben en `system.log`/`error.log` ni se devuelven en errores.

## Seguridad

- Contraseñas con SHA-256; nunca texto plano en disco ni en respuestas.
- SQL siempre por la capa model (`sql_escape`, valores escapados, una sentencia
  por invocación); la web no arma SQL.
- `jq` para parsear/serializar JSON; no se evalúan strings del cliente.
- No se loguean request bodies (pueden contener contraseñas).
- UI sin `innerHTML` para datos: los productos se pintan con `textContent`.
- Sin CORS y sin cookies: el token vive en `sessionStorage` y viaja en
  `params.token`.
- **No hay TLS**: para exponer fuera de la red local, usar un reverse proxy.

## Tests

```bash
bats tests/                 # todos
bats tests/web_rpc.bats     # capa web end-to-end por stdio (22 casos)
bats tests/db.bats          # model + API
bats tests/errors.bats      # errores en error.log
bats tests/report.bats      # HTML ID/Nombre/Precio
bats tests/systemlog.bats   # auditoría
bats tests/validators.bats  # validadores puros
```

`tests/web_rpc.bats` levanta `bin/server --handle-request` con `DB`, `LOG`,
`ERRLOG`, `SESSION_DIR` y `PRODUCTS_HTML` en un `mktemp -d`: nunca toca `var/`
real. Cubre envelope, errores estándar, auth/sesión, token vencido, CRUD,
reporte, path traversal, 413/400/405, auditoría y ausencia de secretos en logs.

Regresión de transparencia: se ejecutó el mismo flujo CLI sobre `ejercicio-4` y
`ejercicio-5` (registro, login, alta, listado, edición, baja, reporte) y se
compararon stdout, `system.log` y `error.log`: idénticos.

## Layout

```text
ejercicio-5.sh        # STUB de entrega CLI/TUI -> bin/app
server.sh             # STUB de entrega web -> bin/server
bin/app               # entrypoint CLI/TUI (sources lib/* en orden)
bin/server            # entrypoint web (sources lib/* + lib/web/*)
lib/
  config.sh           # rutas + spec + HTTP_*/SESSION_*
  validators.sh       # booleanos puros
  crypto.sh           # SHA-256
  logging.sh          # system.log / error.log
  model/              # db.sh, products_store.sh, users_store.sh (único sqlite3)
  api/                # products_api, auth_api, report_api (+ *_data)
  ui/                 # cli.sh, tui.sh, dispatch.sh (únicos interactivos)
  web/                # session.sh, http.sh, rpc.sh, handlers.sh, dispatch.sh
static/               # index.html, app.js, styles.css, favicon.ico
sql/                  # schema.sql, seed.sql
scripts/deploy.sh     # ÚNICO dueño de data.sq3 (`make init`)
tests/                # *.bats
var/                  # db, log, report, session (session gitignorado)
bash-web-rpc-server/  # ejemplo del profesor (intacto, referencia)
```

## Makefile

```bash
make help
make init          # DB + seed
make check         # sintaxis + capas + shfmt informativo
make test          # bats
make build         # valida stubs y entrypoints
make run           # TUI
make run-cli       # CLI
make run-dist      # stub ./ejercicio-5.sh
make run-web       # stub ./server.sh
make run-web-dev   # ./bin/server
make dist          # bundle single-file opcional para CLI/TUI
make clean         # logs + reporte + sesiones
```

Reglas de capas que verifica `make check`:

- `sqlite3` solo en `lib/model/`.
- `whiptail` y `read -rp`/`read -rsp` solo en `lib/ui/`.
- `socat` solo en `bin/server` y `lib/web/dispatch.sh`.
- `jq` solo en `lib/web/`.

## Alcance y límites

- HTTP/1.1, una conexión por request (`Connection: close`), sin keep-alive.
- Notificaciones JSON-RPC (sin `id`) no tienen tratamiento especial: se
  responde con `id: null`. Batch (array) se rechaza con `-32600`.
- Sin TLS, sin CORS, sin cookies, sin CSRF tokens: pensado para mismo origen.
- El bundle `make dist` es solo para CLI/TUI; la web necesita `static/`,
  `jq`, `socat` y la DB.
- `bash-web-rpc-server/` es el ejemplo didáctico del profesor: se conserva
  intacto y no se usa como `static/` de la app.
