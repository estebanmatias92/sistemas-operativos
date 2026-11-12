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

## Documentación

La documentación profunda vive en [`docs/`](docs/README.md):

| Documento | Contenido |
|---|---|
| [01 — Arquitectura](docs/01-arquitectura.md) | capas, módulos, topología y archivos |
| [02 — Flujos](docs/02-flujos.md) | ciclo HTTP, RPC privado, sesión y reporte |
| [03 — Referencia](docs/03-referencia.md) | contrato HTTP/RPC, códigos, env vars y formatos |
| [04 — Operación](docs/04-operacion.md) | arranque, runbook, backup y seguridad |
| [05 — Decisiones](docs/05-decisiones.md) | ADRs y alternativas descartadas |

Los diagramas son docs-as-code: fuentes PlantUML en
[`docs/diagrams/`](docs/diagrams/README.md), compiladas a SVG con `make docs`.
Las capturas de la UI están en [`docs/assets/`](docs/assets/).

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

`POST /` con `Content-Type: application/json`. Los errores de aplicación
responden **HTTP 200** con envelope `error`; solo los fallos de
transporte/estáticos usan 4xx.

- **Públicos:** `saludar`, `auth.register`, `auth.login`.
- **Privados** (requieren `params.token`): `auth.logout`, `products.list`,
  `products.add`, `products.update`, `products.remove`, `report.generate`.

El token viaja en `params.token` (sin cookies ni CORS: mismo origen). El
contrato completo —params, results, códigos `-32xxx` y ejemplos por método—
está en [`docs/03-referencia.md`](docs/03-referencia.md#superficie-rpc).

```bash
# Saludo (público)
curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"saludar"}'

# Login -> token para los métodos privados
TOKEN=$(curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"auth.login","params":{"username":"matt","password":"12345"}}' \
  | jq -r '.result.token')

curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"products.list\",\"params\":{\"token\":\"$TOKEN\"}}"
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

Sesiones fork-safe en `var/session/sessions.tsv`
(`token<TAB>uid<TAB>username<TAB>expires_at`): token de 32 bytes de
`/dev/urandom` hasheado con SHA-256, TTL `SESSION_TTL` (default 3600 s) y
`flock` compartido para validar / exclusivo para crear, revocar y limpiar.
Directorio `700`, archivo `600`; `var/session/` está en `.gitignore` y los
tokens y contraseñas **nunca** se escriben en `system.log`/`error.log`.

Ciclo de vida y concurrencia: [`docs/02-flujos.md`](docs/02-flujos.md#ciclo-de-sesión).

## Seguridad

- Contraseñas con SHA-256; nunca texto plano en disco ni en respuestas.
- SQL solo en la capa model (`sql_escape`, una sentencia por invocación); la
  web no arma SQL.
- `jq` para parsear/serializar JSON; no se evalúan strings del cliente.
- No se loguean request bodies (pueden contener contraseñas) ni se usa
  `innerHTML` para datos: los productos se pintan con `textContent`.
- Sin CORS ni cookies: el token vive en `sessionStorage` y viaja en
  `params.token`.
- **Sin TLS**: para uso local `HTTP_SERVER_HOST=127.0.0.1`; para exponer fuera
  de la red, reverse proxy con HTTPS.

Checklist y amenazas consideradas:
[`docs/04-operacion.md`](docs/04-operacion.md#seguridad) ·
[`docs/05-decisiones.md`](docs/05-decisiones.md).

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
docs/                 # arquitectura, flujos, referencia, operación, ADRs
  diagrams/           # fuentes .puml + SVG compilados (docs-as-code)
  assets/             # capturas de la UI
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
make docs          # compila docs/diagrams/*.puml -> *.svg
make docs-check    # valida sintaxis de los diagramas
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
