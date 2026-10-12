# Ejercicio 4 — Lab 06 Text User Interface (TUI)

Base: `ejercicio-3.sh` (Lab 05: persistencia en `var/db/data.sq3` vía `SQLite3`, auditoría en `system.log`, errores en `error.log`, reporte `productos.html`).

## Idea

Misma **especificación**, distinta **interfaz**: los casos de uso (`add_product`, `register_user`, `remove/update/list_products`, `generate_report`, `login_user`) y la capa de dependencia (`lib/db.sh` contra `SQLite3`) no cambian. Solo se agrega una interfaz de menúes **alternativa con modelo `TUI`** (`whiptail`), transparente para la funcionalidad.

Dos clients sobre el mismo entrypoint (entregable Classroom: `./ejercicio-4.sh`):

```bash
./ejercicio-4.sh --tui   # default: menúes whiptail (requiere TTY + whiptail)
./ejercicio-4.sh --cli   # menúes CLI heredados del Lab 05 (paridad byte-a-byte con ejercicio-3.sh)
./ejercicio-4.sh --help  # uso
```

`--cli` es la referencia de transparencia: todo lo que funciona en `--cli` debe funcionar igual en `--tui`, solo cambia cómo se pide/muestra por pantalla. Los tests `bats` ejercen los casos puros (sin TTY), por lo que ambas interfaces comparten la misma suite.

## Requerimientos funcionales (consigna Lab 06 + heredados)

1. **Interfaz TUI alternativa** (Punto 1): replicar los menúes con `whiptail`, mismas opciones: `ACCESO: 1 login / 2 registro / 3 salir`; `ACCIONES: 1 alta / 2 baja / 3 mostrar / 4 editar / 5 reporte / 6 salir`.
2. **Auth heredado**: `register_user`, `login_user`, 3 intentos en login interactivo.
3. **Productos heredado**: alta, baja, listado, edición con validaciones `RE_PRECIO` / `RE_USER`.
4. **Reporte heredado**: opción 5 regenera `var/report/productos.html` (`ID, Nombre, Precio`).
5. **Inicializar**: al arrancar, si `data.sq3` no existe, construirlo (`init_db`).
6. **Auditar** cada éxito en `system.log` (`fecha/hora<TAB>id<TAB>usuario<TAB>acción`).
7. **Reportar** todo error en `error.log` (amable vía `log_error()` + `stderr` crudo de `sqlite3`).

## Requerimientos no funcionales

- **Transparencia**: `--cli` idéntico al Lab 05; `--tui` mismo flujo, solo cambia el widget.
- **Conservar** criterio Lab 05: `sha256` (nunca texto plano), no duplicados, `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`.
- **Dependencia**: `whiptail (newt)` + TTY solo para `--tui`; `--cli` y `bats` funcionan sin TTY.
- **Mantenibilidad**: casos puros no tocan UI; `lib/ui.sh` (CLI) y `lib/tui.sh` (TUI) son las únicas capas interactivas; `return 0/1`, nunca `exit` adentro.
- **Logs**: mismos formatos y reglas que Lab 05; `Cancel/Esc` en TUI = volver al menú, nunca error en `error.log`.

## Capa UI — necesidades y mapeo a `whiptail`

| Necesidad (hoy CLI en `lib/ui.sh` + `lib/auth.sh`) | Widget TUI (`lib/tui.sh`) |
|---|---|
| `show_welcome`, éxitos (`Acceso concedido`, `Producto X guardado/eliminado/actualizado`, `Reporte generado en...`, `Saliendo...`) | `--msgbox` (se captura el `stdout` del caso puro y se exhibe) |
| `auth_menu`, `product_menu` (opciones `1..3` / `1..6` + `Opción inválida`) | `--menu` (en TUI no hay opción inválida; `Cancel/Esc` = volver/salir) |
| Inputs de texto: ID, nombre, precio, username (`read -rp`) | `--inputbox` (`Cancel` = abortar flujo y volver al menú) |
| Inputs secretos: contraseñas (`read -rsp`) | `--passwordbox` (nunca se loguea ni se muestra) |
| Errores amables (`log_error` → `stderr`) | `--msgbox` con el mismo texto (además sigue yendo a `error.log`) |
| `Credenciales incorrectas (n/3)` (loop 3 intentos) | `--msgbox` por intento fallido, mismo contador |
| `list_products` multilínea (`ID x : y - $z`) | `--msgbox --scrolltext` si corto; `--textbox` con tmpfile si largo |

Convención `whiptail`: el resultado va a `stderr`, se captura con swap `3>&1 1>&2 2>&3`; el `exit != 0` distingue `OK` de `Cancel/Esc`. Cada llamada se protege con `if` por `set -e`.

## Uso

```bash
make help      # lista todos los comandos
make init      # crea var/db/data.sq3 (schema + seed) — una vez
make run       # app modular dev, default --tui (bin/app + lib/)
make run-cli   # app modular en modo CLI (paridad Lab 05)
make run-dist  # entregable generado (./ejercicio-4.sh, default --tui)
```

O directo (sin make):

```bash
chmod +x bin/app ejercicio-4.sh
./bin/app --tui    # modular TUI
./bin/app --cli    # modular CLI
./ejercicio-4.sh           # bundle TUI (default)
./ejercicio-4.sh --cli     # bundle CLI (paridad con ejercicio-3.sh)
```

1. Crea `var/db/data.sq3` (si falta, `make init` o `init_db`) + `var/log/system.log` / `var/log/error.log` según operación.
2. Menú **ACCESO**: `1` iniciar sesión, `2` registrar usuario, `3` salir.
3. Menú **ACCIONES** (post-login): `1` alta, `2` baja, `3` mostrar, `4` editar, `5` generar reporte HTML, `6` salir.
4. En TUI, `Esc`/`Cancelar` vuelve al menú anterior sin escribir en disco ni en `error.log`.

## Archivos (layout canónico)

```text
ejercicio-4.sh   # ENTREGABLE (generado por `make build` desde lib/; no editar a mano)
bin/app          # entrypoint dev (source lib/* + main "$@"; propaga --tui/--cli)
lib/             # config, validators, crypto, logging, db, products, auth, report, ui (CLI), tui (TUI)
sql/schema.sql   # schema canónico; sql/seed.sql = datos ejemplo
var/db/data.sq3  # fuente de verdad (único archivo; sin *.tsv)
var/log/         # system.log (auditoría TSV) + error.log (texto)
var/report/      # productos.html (derivado, opción 5)
tests/           # *.bats — `make test` (casos puros, sin TTY; mismo contrato que Lab 05)
db/              # legacy Lab 04, solo referencia; ningún código lo lee ni lo escribe
Makefile         # `make help` para ver comandos
```

- `ejercicio-4.sh`: bundle entregable (fuente de verdad = `lib/`).
- `lib/ui.sh`: client CLI (código heredado Lab 05, intacto para paridad).
- `lib/tui.sh`: client TUI (único código nuevo del Lab 06; delega en los mismos casos de uso).
- `var/db/data.sq3`: fuente de verdad (reemplaza a `db/*.tsv`, que queda como legacy sin lectura en runtime).
- `var/log/system.log` / `var/log/error.log`: versionados como evidencia de ejecución.
- `var/report/productos.html`: derivado (se regenera con la opción 5).

## Schema propuesto (heredado Lab 05, sin cambios)

```sql
CREATE TABLE IF NOT EXISTS usuarios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS productos(
  id TEXT PRIMARY KEY,
  nombre TEXT NOT NULL,
  precio TEXT NOT NULL
);
```

`PRIMARY KEY` / `UNIQUE` = no-duplicados a nivel DB; el chequeo previo en Bash (`record_exists` vía `SELECT`) se mantiene para mensaje amable sin escribir.

## Verificación

```bash
make help          # lista targets
make check         # bash -n (gate) + shfmt informativo
make test          # bats tests/ — casos puros (validators, db, errors, report, systemlog)
make build         # regenera ejercicio-4.sh desde lib/
make init          # var/db/data.sq3 desde schema + seed
./ejercicio-4.sh --help        # uso dual client
./ejercicio-4.sh --cli         # paridad Lab 05 (sin TTY especial)
./ejercicio-4.sh               # TUI (requiere TTY + whiptail)
sqlite3 var/db/data.sq3 ".tables"      # usuarios productos
sqlite3 var/db/data.sq3 ".schema"      # contraste con sql/schema.sql
cat var/log/system.log var/log/error.log
```

Tests con `bats` (cómo ejecutar y qué cubren, heredado Lab 05):

```bash
bats tests/                 # toda la suite (sin TTY; cubre casos puros compartidos por ambos clients)
bats tests/validators.bats  # validadores puros (precio/usuario/producto)
bats tests/db.bats          # adapter SQLite + casos (alta/duplicado/sql_escape/update/login, seed.sql)
bats tests/errors.bats      # todo error (amable o SQL) deja rastro en error.log
bats tests/report.bats      # HTML con tabla ID/Nombre/Precio
bats tests/systemlog.bats   # cada éxito audita en system.log (fallos no escriben)
```

Los tests aíslan disco por env temporal (`DB`, `LOG`, `ERRLOG` apuntan a `mktemp -d`); nunca tocan `var/` real. La paridad `--cli` vs `--tui` se verifica manual (mismo flujo, mismos logs) porque `whiptail` requiere TTY.

## Referencia `whiptail` (para `lib/tui.sh`)

```bash
whiptail --title "Acceso" --menu "Elija:" 15 50 3 1 "Iniciar sesión" 2 "Registrar usuario" 3 "Salir" 3>&1 1>&2 2>&3
whiptail --title "Alta" --inputbox "Ingrese ID:" 10 40 3>&1 1>&2 2>&3
whiptail --title "Acceso" --passwordbox "Contraseña:" 10 40 3>&1 1>&2 2>&3
whiptail --title "Aviso" --msgbox "Producto A1 guardado." 10 40
```

Contratos que no cambian: `productos.html` (título + `<table>` `ID, Nombre, Precio`), `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`.
