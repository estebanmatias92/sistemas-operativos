# 04 — Operación

## Requisitos

| Componente | Para qué | Verificación |
|---|---|---|
| `bash` 4+ | runtime | `bash --version` |
| `sqlite3` | DB y capa model | `sqlite3 --version` |
| `jq` | capa web (JSON) | `jq --version` |
| `socat` | servidor web | `socat -V` |
| `sha256sum`, `flock`, `realpath`, `stat`, `wc`, `head` | runtime | coreutils/util-linux |
| `bats` | tests | `bats --version` |
| `whiptail` (libnewt) | solo TUI | `whiptail --version` |
| `plantuml` + `java` + GraphViz | solo regenerar diagramas | `make docs` |

Instalación en Arch:

```bash
sudo pacman -S bash sqlite3 jq socat bats util-linux coreutils
sudo pacman -S libnewt          # opcional: TUI
sudo pacman -S plantuml         # opcional: diagramas
```

En otras distribuciones cambian los nombres de paquete; los binarios son los
mismos.

## Primer arranque

```bash
make init                 # crea var/ y data.sq3, siembra ejemplo, trunca logs
make check                # sintaxis + reglas de capas
make test                 # suite completa
./server.sh --check       # dependencias del servidor web
```

Seed de ejemplo: usuarios `matt` y `jeff` con contraseña `12345`; productos
`escoba` y `balde`. **Es solo para el lab**: no usar esas credenciales fuera
del entorno local.

## Modos de ejecución

```bash
./ejercicio-5.sh --cli          # CLI heredado
./ejercicio-5.sh                # TUI (default; requiere TTY + whiptail)
./server.sh                     # web en 0.0.0.0:8080
HTTP_SERVER_HOST=127.0.0.1 ./server.sh
HTTP_SERVER_PORT=8081 ./server.sh
```

Equivalentes con `make`: `run-cli`, `run`, `run-web`, `run-web-dev`.

La UI web queda en `http://localhost:8080/`: registro/login, inventario,
alta/edición/baja y generación de reporte.

## Verificación rápida

```bash
# Estático
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://localhost:8080/

# Público
curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"saludar"}'

# Login y método privado
TOKEN=$(curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"auth.login","params":{"username":"matt","password":"12345"}}' \
  | jq -r '.result.token')

curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"products.list\",\"params\":{\"token\":\"$TOKEN\"}}"

# Reporte
curl -s -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"report.generate\",\"params\":{\"token\":\"$TOKEN\"}}"
curl -s http://localhost:8080/report/productos.html | head
```

Sin `socat` (una conexión por stdio):

```bash
printf 'GET / HTTP/1.1\r\nHost: x\r\n\r\n' | ./bin/server --handle-request | head
printf 'GET /../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n' | ./bin/server --handle-request | head -1
```

## Entorno aislado para pruebas

Los tests y recetas pueden apuntar a un directorio temporal sin tocar `var/`:

```bash
TMP="$(mktemp -d)"
export DB="$TMP/db.sq3"
export LOG="$TMP/system.log"
export ERRLOG="$TMP/error.log"
export PRODUCTS_HTML="$TMP/report/productos.html"
export SESSION_DIR="$TMP/session"

./scripts/deploy.sh --no-seed
printf 'GET / HTTP/1.1\r\nHost: x\r\n\r\n' | ./bin/server --handle-request | head -3
```

`SESSIONS_FILE` se deriva de `SESSION_DIR`; se puede sobreescribir por separado.
Los tests bats usan este patrón y limpian el temporal en `teardown`.

## Runbook

| Síntoma | Causa probable | Solución |
|---|---|---|
| `falta .../data.sq3; corra make init` | DB no creada | `make init` |
| `Address already in use` | puerto ocupado | `HTTP_SERVER_PORT=8081 ./server.sh` o liberar el puerto (`ss -ltnp`, `fuser -k`) |
| `socat: command not found` | falta dependencia | instalar `socat`; `./server.sh --check` |
| `jq: command not found` | falta dependencia | instalar `jq`; `./server.sh --check` |
| Toda llamada privada da `-32001` | token ausente, vencido o revocado | volver a hacer `auth.login`; el TTL default es 1 h |
| `Permission denied` en `var/session` | permisos/owner incorrectos | `chmod 700 var/session; chmod 600 var/session/sessions.tsv` |
| `GET /report/productos.html` da 404 | reporte no generado | ejecutar `report.generate` |
| `database is locked` | escritor concurrente o proceso externo | reintentar; no editar la DB con otras herramientas |
| El login del seed falla | DB sin seed o contraseña cambiada | `make seed` (idempotente) o `make init` |
| La UI muestra datos viejos | caché del navegador | recarga forzada; los RPC ya usan `no-store` |
| `bind: Cannot assign requested address` | `HTTP_SERVER_HOST` inexistente | usar `0.0.0.0`, `127.0.0.1` o la IP local correcta |

Para diagnosticar siempre están `var/log/system.log` (éxitos) y
`var/log/error.log` (fallos). No contienen tokens ni contraseñas.

## Backup y restauración

La única pieza con estado durable es la DB. Logs, reporte y sesiones son
derivados/efímeros.

```bash
# Con el servidor detenido (más simple)
cp var/db/data.sq3 /backup/data-$(date +%F).sq3

# En caliente, consistente
sqlite3 var/db/data.sq3 ".backup '/backup/data.sq3'"
```

Restauración:

```bash
# detener el servidor
cp /backup/data.sq3 var/db/data.sq3
./scripts/deploy.sh --check       # o make deploy-check
rm -rf var/session                # forzar re-login
```

Si se restaura la DB pero se conservan sesiones, los tokens siguen siendo
válidos mientras no venzan; borrar `var/session/` es la opción conservadora.

## Seguridad

- **Binding por defecto `0.0.0.0`**: accesible desde la red local. Para uso
  exclusivamente local: `HTTP_SERVER_HOST=127.0.0.1 ./server.sh`.
- **Sin TLS**: si se expone fuera de la red local, poner un reverse proxy con
  HTTPS delante. No hay cookies ni CORS; el token viaja en el body.
- **Contraseñas**: SHA-256, nunca texto plano en disco ni en respuestas.
- **Secretos**: tokens y contraseñas no se loguean; `var/session/` está en
  `.gitignore`.
- **Permisos**: `var/session` `700`, `sessions.tsv` `600`.
- **Superficie**: el servidor solo habla HTTP/1.1 y JSON-RPC; no ejecuta
  comandos del cliente ni evalúa strings.
- **Reporte**: se sirve desde `var/report/` con la misma defensa de traversal
  que `static/`.

## Matriz de verificación

| Qué | Comando | Esperado |
|---|---|---|
| Estáticos | `curl -i http://localhost:8080/` | `200`, `text/html` |
| 404 | `curl -i http://localhost:8080/no-existe` | `404` |
| Traversal | request crudo con `/../etc/passwd` | `404` |
| RPC público | `saludar` | `result` + `id` |
| Método inexistente | `no_existe` | `-32601` |
| JSON inválido | body `{` | `-32700` |
| Sin token | `products.list` sin `params.token` | `-32001` |
| Login | `auth.register` + `auth.login` | token + uid |
| CRUD | `products.add/list/update/remove` | datos coherentes |
| Reporte | `report.generate` + `GET /report/productos.html` | tabla `ID/Nombre/Precio` |
| Logs | `cat var/log/system.log` | TSV de 4 columnas |
| Sin secretos | `grep` de password/token en logs | sin coincidencias |
| Calidad | `make check && make test` | verde |
| Regresión | `./ejercicio-5.sh --cli` | mismo flujo que Lab 06 |

## Limpieza

```bash
make clean        # logs + reporte + sesiones (conserva la DB)
make clean-all    # además borra data.sq3 (se reconstruye con make init)
```

`make clean` no toca la DB ni los diagramas versionados.
