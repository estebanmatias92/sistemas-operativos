# HANDOFF — Laboratorio 07 (ejercicio-5)

Documento de continuidad para la próxima sesión. Las reglas durables están en
`AGENTS.md`; acá va el estado, las decisiones y el plan concreto.

## Dónde estamos

- `code/` es un symlink a `.../sistemas-operativos/ejercicio-5`.
- Hoy `ejercicio-5/` solo contiene `bash-web-rpc-server/` (ejemplo del profesor,
  versión `plain-version`: `server.sh` + `static/index.html`). **No borrar ni
  modificar.**
- La app base es `ejercicio-4` (Lab 06): capas `ui → api → model → config`,
  SQLite, `system.log`/`error.log`, `productos.html`, CLI/TUI, tests bats y
  Makefile. Todavía **no** está copiada a `ejercicio-5/`.
- Repo: `sistemas-operativos`, branch `main`, remote `origin`
  (`github.com/estebanmatias92/sistemas-operativos`). `ejercicio-5/` está
  untracked (`?? ejercicio-5/`).

## Decisiones tomadas

1. Reescribir la consigna en el `.md` en el lugar, preservando front matter y
   encabezados.
2. Handoff doble: `AGENTS.md` (reglas operativas) + `HANDOFF.md` (este archivo,
   estado y plan).
3. La web vive en `lib/web/` como capa de presentación:
   `web → api → model → config`.
4. Los handlers RPC obtienen datos estructurados con variantes `*_data` de la
   API; `CLI`/`TUI` conservan sus formateadores y mensajes exactos.
5. Sesión con token persistido en `var/session/sessions.tsv` (fork-safe,
   revocable, TTL 1 h).

## Condiciones del trabajo (movidas desde la consigna)

1. **Transparencia funcional**: mismos datos, validaciones, logs y reporte que
   el `ejercicio-4`. `CLI` y `TUI` siguen funcionando sin cambios.
2. **Capas**: la capa web no arma SQL ni duplica reglas; delega en la API
   existente. Solo `lib/model/` usa `sqlite3`.
3. **Seguridad**: contraseñas con hash SHA-256; nunca en respuestas ni logs.
   Los tokens de sesión tampoco se loguean.
4. **Ejemplo del profesor**: `bash-web-rpc-server/` se conserva como referencia
   y no se modifica.
5. **Ejecución local**: el servidor levanta con un comando (`make run-web` o
   `./server.sh`) y escucha en un puerto configurable.

## Qué falta construir

```text
ejercicio-5/
  ejercicio-5.sh        # stub -> bin/app (CLI/TUI, heredado)
  server.sh             # stub -> bin/server (web, nuevo)
  bin/app               # entrypoint CLI/TUI (heredado)
  bin/server            # entrypoint web (nuevo)
  lib/web/              # http.sh, rpc.sh, handlers.sh, session.sh, dispatch.sh
  static/               # index.html, app.js, styles.css, favicon.ico
  bash-web-rpc-server/  # ejemplo intacto
```

La app completa (`lib/`, `sql/`, `scripts/`, `tests/`, `var/`, `Makefile`) se
copia desde `ejercicio-4`.

## Paso 0 — baseline desde `ejercicio-4`

**Cuidado**: no sobrescribir `AGENTS.md`, `HANDOFF.md` ni el `README.md` de
Lab 07. Copiar solo código/tooling y después adaptar la documentación.

Desde el directorio del lab 07:

```bash
rsync -a \
  --exclude 'AGENTS.md' \
  --exclude 'HANDOFF.md' \
  --exclude 'README.md' \
  --exclude '.git' \
  --exclude 'dist' \
  ../2026-10-09-laboratorio-text-user-interface/code/ ./code/
```

Si no hay `rsync`, copiar a un directorio temporal y mergear a mano; **no**
hacer `cp -a .../. ./code/` directo porque pisa el handoff.

Checklist del baseline:

- [ ] Renombrar `ejercicio-4.sh` → `ejercicio-5.sh` y actualizar su comentario.
- [ ] Actualizar `Makefile`: `ejercicio-4.sh` → `ejercicio-5.sh` en
      `build`, `check`, `fmt`, `run-dist` y `dist/ejercicio-*.sh`.
- [ ] Actualizar el comentario de `bin/app` que menciona `ejercicio-4.sh`.
- [ ] Reescribir `README.md` para Lab 07 (no conservar el de Lab 06).
- [ ] Copiar `.gitignore` de `ejercicio-4` y agregar `var/session/`.
- [ ] `make init && make check && make test`.
- [ ] Smoke: `./ejercicio-5.sh --cli` (y `--tui` si hay TTY/whiptail).
- [ ] Commit del baseline.

## Plan de implementación (micro-pasos)

### 1. Servidor mínimo + estáticos

- Crear `lib/web/http.sh`, `lib/web/rpc.sh` (mínimo), `lib/web/dispatch.sh`,
  `bin/server` y `server.sh`.
- `bin/server --handle-request` lee un request HTTP de `stdin` y responde por
  `stdout`; `GET /` sirve `static/index.html`; 404 para inexistente.
- Probar sin `socat`:
  ```bash
  printf 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n' | ./bin/server --handle-request
  ```
- Probar con `curl` levantando `./server.sh`.
- Commit.

### 2. Envelope JSON-RPC

- `rpc_load_request` valida JSON y extrae `jsonrpc`, `method`, `id`, `params`.
- `rpc_success`/`rpc_error`/`rpc_load_response` arman el envelope con `jq`.
- `rpc_load_registry` con `saludar`; método desconocido → `-32601`; JSON
  inválido → `-32700`; sin `method` → `-32600`.
- Probar con `curl` y con `printf ... | ./bin/server --handle-request`.
- Commit.

### 3. Sesión y autenticación

- `lib/web/session.sh`: token, TTL, `flock`, revoke/cleanup.
- `auth.register`, `auth.login`, `auth.logout`.
- Públicos vs privados en el registry; `rpc_process_request` valida el token
  antes del handler y setea `RPC_SESSION_UID`/`RPC_SESSION_USER`.
- Probar: registro, login OK, login malo, método privado sin token, token
  vencido, logout.
- Commit.

### 4. API `*_data` + productos

- Refactor mínimo de `lib/api/`: `*_data` devuelve TSV/valores; las funciones
  actuales formatean igual que antes.
- Handlers `products.list/add/update/remove` con `jq`.
- Probar CRUD completo por RPC y regresión `make test`.
- Commit.

### 5. Reporte

- `generate_report_data` + handler `report.generate`.
- Servir `/report/productos.html` desde `var/report/` con la misma protección
  de path traversal; devolver `{path, url}`.
- Probar que el HTML tiene la tabla `ID, Nombre, Precio`.
- Commit.

### 6. Interfaz web

- `static/index.html`, `static/app.js`, `static/styles.css`.
- Registro/login, tabla, alta/edición/baja, reporte y panel de JSON crudo.
- Token en `sessionStorage`/memoria, enviado en `params.token`.
- Probar el flujo completo en navegador; capturas para el `.md`.
- Commit.

### 7. Cierre

- `README.md` con dependencias, arranque, tabla de métodos y ejemplos `curl`.
- `make check`, `make test`, regresión CLI/TUI.
- Actualizar `AGENTS.md` solo si cambió algún contrato.
- Verificar que `bash-web-rpc-server/` sigue intacto.
- Commit final; no push sin confirmación.

## Anatomía del ejemplo del profesor

| Función | Qué enseña / qué adaptar |
|---|---|
| `http_load_headers` | Parseo de request line + headers desde `stdin`. |
| `http_load_request` | Body según `Content-Length`; tope de 512 KB. |
| `rpc_load_request` | Validación JSON y extracción de campos con `jq`. |
| `http_process_request` | `GET`: archivo, MIME, tamaño y path traversal. |
| `rpc_process_request` | Dispatch por `RPC_PUBLIC_HANDLER` / `RPC_PRIVATE_HANDLER`. |
| `rpc_load_response` | Envelope `result`/`error` con `jq`. |
| `http_send_headers` / `http_send_response` | Respuesta y `Connection: close`. |
| `main_dispatch` | `socat TCP-LISTEN:...,fork EXEC:"$0 --handle-request"`. |

Diferencias con la app: el ejemplo es monolítico y sin auth; la entrega lo
integra a `lib/web/` con guardas, sesión y API en capas. No copiar código
top-level a `lib/`.

## Pitfalls

- `set -e` + `read`: `read -r`/`read -N` pueden devolver != 0 en EOF; usar
  `if ! read ...` o `|| true`.
- `stdout` de `--handle-request` es **solo** la respuesta HTTP; logs a
  `stderr`/`error.log`.
- `Content-Length` en bytes (UTF-8): usar `wc -c`, no `${#body}`.
- `socat` hace `fork`: no guardar sesión en memoria; usar archivo.
- `socat EXEC` debe ejecutar una ruta absoluta y el server debe hacer `cd` al
  `APP_ROOT` antes de sourcear.
- Path traversal: `realpath -m` + prefijo con `/` final.
- Body > 512 KB: `413` y cerrar; JSON inválido: `-32700`.
- Notificaciones (sin `id`) y batch (array) fuera de alcance; documentarlo.
- No loguear request bodies (pueden traer contraseñas).
- `xdg-mime` puede no estar; mejor mapa MIME explícito para
  `html/css/js/json/svg/ico/png` y fallback `application/octet-stream`.
- `flock` es de util-linux; verificar en `--check`.
- Puerto 8080 puede estar ocupado por el ejemplo; usar `HTTP_SERVER_PORT=8081`.

## Matriz de verificación

| Qué | Comando | Esperado |
|---|---|---|
| Estáticos | `curl -i http://localhost:8080/` | `200`, `text/html` |
| 404 | `curl -i http://localhost:8080/no-existe` | `404` |
| Path traversal | `printf 'GET /../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n' \| ./bin/server --handle-request` | `404` |
| RPC OK | `curl -s -X POST ... -d '{"jsonrpc":"2.0","id":1,"method":"saludar"}'` | `result` + `id` |
| Método inexistente | `... "method":"no_existe"` | error `-32601` |
| JSON inválido | `... -d '{'` | error `-32700` |
| Sin token | `... "method":"products.list","params":{}` | error `-32001` |
| Login | `auth.register` + `auth.login` | token + uid |
| CRUD | `products.add/list/update/remove` con token | datos coherentes |
| Reporte | `report.generate` + `GET /report/productos.html` | tabla HTML |
| Logs | `cat var/log/system.log var/log/error.log` | éxitos/fallos esperados |
| Regresión | `./ejercicio-5.sh --cli` / `--tui` | mismo flujo que Lab 06 |
| Calidad | `make check && make test` | verde |

## Git / checkpoints

- Repo: `/home/matt/Projects/github.com/estebanmatias92/isft151-analisis-sistemas/sistemas-operativos`
- Branch `main`; remote `origin`. `ejercicio-5/` untracked.
- Commits sugeridos: baseline, servidor estático, envelope, auth, CRUD,
  reporte, UI, cierre.
- No push sin confirmación.
- `bash-web-rpc-server/` se conserva; si se commitea, que sea tal cual.

## Preguntas abiertas

- `submission_file_format: .cpp` en el front matter y `due_date: 2026-11-06`
  (ya pasada): confirmar con la cátedra antes de cambiarlos.
- ¿Se commitea `bash-web-rpc-server/` como referencia o queda fuera del repo?
- TTL de sesión (1 h) y si hace falta “recordarme”.
- Reporte: servir `/report/productos.html` (recomendado) o devolver el HTML
  embebido en el `result`.
- ¿`make dist` debe bundlear también el servidor web? No es necesario: la web
  necesita `static/` y `socat`; el bundle single-file queda para CLI/TUI.
