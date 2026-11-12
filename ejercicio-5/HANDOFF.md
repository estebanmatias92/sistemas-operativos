# HANDOFF — Laboratorio 07 (ejercicio-5)

Documento de continuidad. Las reglas durables están en `AGENTS.md`; la
documentación de uso, en `README.md`. Acá va el estado real del lab.

## Estado: completo y verificado

Todos los checkpoints están implementados y commiteados en
`sistemas-operativos` (branch `main`). No se hizo push.

| Checkpoint | Commit | Contenido |
|---|---|---|
| 0 | `faa6656` | Baseline desde Lab 06, stub `ejercicio-5.sh`, Makefile y `.gitignore` |
| 1 | `36004e2` | Servidor HTTP estático (`bin/server`, `server.sh`, `lib/web/http.sh`) |
| 2 | `2da9847` | Envelope JSON-RPC 2.0 (`lib/web/rpc.sh`), `saludar`, errores estándar |
| 3 | `975b571` | Sesión fork-safe (`lib/web/session.sh`) y auth RPC |
| 4 | `9ae8dc2` | API `*_data` y CRUD de productos por RPC |
| 5 | `838413a` | `report.generate` y `/report/productos.html` |
| 6 | `c4d17d0` | UI web end-user (`static/index.html`, `app.js`, `styles.css`, favicon) |
| 7 | (cierre) | `tests/web_rpc.bats`, `README.md`, `AGENTS.md`, este `HANDOFF.md` |

## Arquitectura final

```text
bin/app (CLI / TUI) ──┐
                      ├──> lib/api/* ──> lib/model/* ──> var/db/data.sq3
bin/server (web) ─────┘          │
                                 └── config · validators · crypto · logging
```

- `lib/web/`: `session.sh`, `http.sh`, `rpc.sh`, `handlers.sh`, `dispatch.sh`.
- La capa web no usa `sqlite3` ni duplica reglas: los handlers llaman a las
  variantes `*_data` de `lib/api/` y serializan con `jq`.
- `socat` hace `fork` por conexión; la sesión vive en archivo
  (`var/session/sessions.tsv`) con `flock`.

## Decisiones cerradas

1. **Datos estructurados**: `*_data` devuelve TSV/valores por stdout y códigos
   `0` ok / `10` inválido / `11` conflicto-inexistente-credenciales / `12`
   interno. Las funciones históricas conservan mensajes y `return 0/1`.
2. **Errores de aplicación con HTTP 200** y envelope `error` (igual que el
   ejemplo del profesor); 4xx solo para transporte/estáticos.
3. **Métodos HTTP no soportados** → `-32005` con HTTP 200.
4. **Sesión**: token de 32 bytes (`/dev/urandom`) hasheado SHA-256, TTL 3600 s,
   archivo `600`, directorio `700`, `var/session/` gitignorado. Nunca se
   loguean tokens ni contraseñas.
5. **Binding**: `0.0.0.0:8080` por defecto (como el ejemplo); configurable con
   `HTTP_SERVER_HOST`/`HTTP_SERVER_PORT`. Para uso local, `127.0.0.1`.
6. **UI end-user**: login/registro, cabecera con usuario, tabla, alta/edición,
   baja con confirmación, reporte y mensajes de estado. Sin panel de JSON crudo
   ni tabla de RPC (eso queda en `bash-web-rpc-server/`). Datos pintados con
   `textContent`.
7. **Reporte**: `report.generate` devuelve `{path, url}`; la URL se sirve en
   `/report/<basename(PRODUCTS_HTML)>` con la misma protección de path traversal
   que `static/`.
8. **`make dist`** sigue siendo solo CLI/TUI: la web necesita `static/`, `jq`,
   `socat` y la DB.

## Verificación ejecutada

- `make check`: verde (sintaxis de entrypoints y módulos; reglas de capas:
  `sqlite3` solo en `lib/model`, `whiptail`/`read -rp` solo en `lib/ui`,
  `socat` solo en `bin/server` + `lib/web/dispatch.sh`, `jq` solo en `lib/web`).
  `shfmt -d` queda informativo a propósito (estilo `>> "$f"`).
- `make test`: **50/50** casos verdes (28 heredados + 22 nuevos de
  `tests/web_rpc.bats`).
- `./server.sh --check`: todas las dependencias OK.
- Smoke en vivo con `socat` (`127.0.0.1:8084`): estático 200, traversal 404,
  `saludar`, registro/login, alta/listado/edición/baja, reporte con tabla y
  logout; auditoría TSV correcta en `system.log`, sin secretos.
- Regresión CLI contra `ejercicio-4` (registro, login, alta, listado, edición,
  baja, reporte): stdout, `system.log`, `error.log` y `productos.html`
  **idénticos**.
- Flujo de UI en Chromium headless vía CDP: registro, alta, recarga con sesión
  persistida, edición, reporte, baja y logout, con **cero** excepciones JS y
  cero errores de consola. Capturas revisadas.
- `bash-web-rpc-server/` sin cambios desde el baseline (`git log` solo muestra
  el commit 0 para ese path).

## Comandos útiles

```bash
make init && make check && make test
./server.sh --check
./server.sh                              # 8080 en 0.0.0.0
HTTP_SERVER_HOST=127.0.0.1 ./server.sh   # solo local
bats tests/web_rpc.bats                  # capa web (22 casos)
./ejercicio-5.sh --cli                   # regresión CLI
```

## Preguntas abiertas / límites documentados

- Notificaciones JSON-RPC (sin `id`) se responden con `id: null`; batch (array)
  se rechaza con `-32600`. Documentado en `README.md`.
- Sin TLS, sin CORS, sin cookies, sin CSRF tokens: pensado para mismo origen.
  Para exponer fuera de la red local hace falta un reverse proxy.
- `submission_file_format: .cpp` en el front matter de la consigna y
  `due_date: 2026-11-06` (ya pasada): confirmar con la cátedra antes de
  cambiarlos.
- `bash-web-rpc-server/` quedó versionado como referencia intacta.
- No push realizado: pendiente de confirmación.
