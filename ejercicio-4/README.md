# Ejercicio 4 — Lab 06 Text User Interface (TUI)

Base: `ejercicio-3.sh` (Lab 05: persistencia en `var/db/data.sq3` vía `SQLite3`, auditoría en `system.log`, errores en `error.log`, reporte `productos.html`).

## Idea

Misma **especificación**, distinta **interfaz**: los casos de uso (`add_product`, `register_user`, `remove/update/list_products`, `generate_report`, `login_user`, en `lib/api/`) y la capa de persistencia (`lib/model/` contra `SQLite3`) no cambian. Solo se agrega una interfaz de menúes **alternativa con modelo `TUI`** (`whiptail`), transparente para la funcionalidad.

Dos clients sobre el mismo entrypoint (entregable Classroom: `./ejercicio-4.sh`, stub que delega en `bin/app`):

```bash
./ejercicio-4.sh --tui   # default: menúes whiptail (requiere TTY + whiptail)
./ejercicio-4.sh --cli   # menúes CLI heredados del Lab 05 (paridad salvo alta: ya no pide ID)
./ejercicio-4.sh --help  # uso
```

`--cli` es la referencia de transparencia: todo lo que funciona en `--cli` debe funcionar igual en `--tui`, solo cambia cómo se pide/muestra por pantalla (el alta ya no pide ID en ningún client: es `AUTOINCREMENT`). Los tests `bats` ejercen la API compartida (sin TTY).

## Requerimientos funcionales (consigna Lab 06 + heredados)

1. **Interfaz TUI alternativa** (Punto 1): replicar los menúes con `whiptail`, mismas opciones: `ACCESO: 1 login / 2 registro / 3 salir`; `ACCIONES: 1 alta / 2 baja / 3 mostrar / 4 editar / 5 reporte / 6 salir`.
2. **Auth heredado**: `register_user`, `login_user`, 3 intentos en login interactivo.
3. **Productos**: alta sin ID manual (lo genera `AUTOINCREMENT` y se anuncia `Producto N guardado.`); baja, listado y edición con validaciones `RE_PRECIO` / `RE_USER` / `RE_REF_ID`.
4. **Reporte heredado**: opción 5 regenera `var/report/productos.html` (`ID, Nombre, Precio`).
5. **Inicializar**: `scripts/deploy.sh` (`make init`) es el ÚNICO dueño de `data.sq3`; al arrancar, la app solo verifica con `require_db` y falla amable (`corra make init`) si falta.
6. **Auditar** cada éxito en `system.log` (`fecha/hora<TAB>id<TAB>usuario<TAB>acción`).
7. **Reportar** todo error en `error.log` (amable vía `log_error()` + `stderr` crudo de `sqlite3`).

## Requerimientos no funcionales

- **Transparencia**: `--cli` idéntico al Lab 05; `--tui` mismo flujo, solo cambia el widget.
- **Conservar** criterio Lab 05: `sha256` (nunca texto plano), no duplicados, `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`.
- **Dependencia**: `whiptail (newt)` + TTY solo para `--tui`; `--cli` y `bats` funcionan sin TTY.
- **Mantenibilidad**: 3 capas con flujo `ui → api → model → config` (`logging` cross-cutting, `validators`/`crypto` puros); la API nunca invoca `sqlite3`/`whiptail`/`read` y el model nunca invoca `whiptail`/`read` (`make check` lo verifica); `lib/ui/cli.sh` (CLI) y `lib/ui/tui.sh` (TUI) son las únicas capas interactivas; `return 0/1`, nunca `exit` adentro.
- **Logs**: mismos formatos y reglas que Lab 05; `Cancel/Esc` en TUI = volver al menú, nunca error en `error.log`.

## Capa UI — necesidades y mapeo a `whiptail`

| Necesidad (hoy CLI en `lib/ui/cli.sh`) | Widget TUI (`lib/ui/tui.sh`) |
|---|---|
| `show_welcome`, éxitos (`Acceso concedido`, `Producto X guardado/eliminado/actualizado`, `Reporte generado en...`, `Saliendo...`) | `--msgbox` (se captura el `stdout` del caso puro y se exhibe) |
| `auth_menu`, `product_menu` (opciones `1..3` / `1..6` + `Opción inválida`) | `--menu` (en TUI no hay opción inválida; `Cancel/Esc` = volver/salir) |
| Inputs de texto: nombre, precio, username + ID solo en baja/edición (`read -rp`) | `--inputbox` (`Cancel` = abortar flujo y volver al menú) |
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
make run-dist  # stub de entrega (./ejercicio-4.sh -> bin/app, default --tui)
```

O directo (sin make):

```bash
chmod +x bin/app ejercicio-4.sh
./bin/app --tui    # modular TUI
./bin/app --cli    # modular CLI
./ejercicio-4.sh           # stub entrega -> bin/app, TUI (default)
./ejercicio-4.sh --cli     # stub entrega -> bin/app, CLI (paridad con Lab 05 salvo alta sin ID)
```

1. `scripts/deploy.sh --seed` crea `var/db/data.sq3` (`make init`) + `var/log/system.log` / `var/log/error.log` según operación (la app exige DB con `require_db`, nunca la crea).
2. Menú **ACCESO**: `1` iniciar sesión, `2` registrar usuario, `3` salir.
3. Menú **ACCIONES** (post-login): `1` alta, `2` baja, `3` mostrar, `4` editar, `5` generar reporte HTML, `6` salir.
4. En TUI, `Esc`/`Cancelar` vuelve al menú anterior sin escribir en disco ni en `error.log`.

## Archivos (layout canónico)

```text
ejercicio-4.sh   # STUB de entrega (delega en bin/app; no editar lógica)
bin/app          # entrypoint dev (source lib/* en orden + main "$@"; propaga --tui/--cli)
lib/             # config, validators, crypto, logging, model/ (único con sqlite3),
                 #   api/ (casos puros), ui/ (cli, tui, dispatch: únicos interactivos)
scripts/deploy.sh # ÚNICO dueño de la DB (schema + seed); `make init` delega
sql/schema.sql   # schema canónico; sql/seed.sql = datos ejemplo
var/db/data.sq3  # fuente de verdad (único archivo; sin *.tsv)
var/log/         # system.log (auditoría TSV) + error.log (texto)
var/report/      # productos.html (derivado, opción 5)
tests/           # *.bats — `make test` (API compartida, sin TTY)
db/              # legacy Lab 04, solo referencia; ningún código lo lee ni lo escribe
Makefile         # `make help` para ver comandos
```

- `ejercicio-4.sh`: stub de entrega (delega en `bin/app`; fuente de verdad = `lib/`).
- `lib/ui/cli.sh`: client CLI; `lib/ui/tui.sh`: client TUI (delega en la misma API).
- `var/db/data.sq3`: fuente de verdad (reemplaza a `db/*.tsv`, que queda como legacy sin lectura en runtime).
- `var/log/system.log` / `var/log/error.log`: versionados como evidencia de ejecución.
- `var/report/productos.html`: derivado (se regenera con la opción 5).

## Schema (productos con id autogenerado)

```sql
CREATE TABLE IF NOT EXISTS usuarios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS productos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  precio TEXT NOT NULL
);
```

`PRIMARY KEY` / `UNIQUE` = no-duplicados a nivel DB; el alta ya no pide id (lo devuelve `last_insert_rowid()`); baja/edición referencian el id numérico (`RE_REF_ID`).

## Verificación

```bash
make help          # lista targets
make check         # bash -n (gate) + shfmt informativo
make test          # bats tests/ — casos puros (validators, db, errors, report, systemlog)
make build         # verifica stub + lib/ (sin compilado; `make dist` = bundle opcional en dist/)
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
bats tests/validators.bats  # validadores puros (precio/usuario/datos/ref-id)
bats tests/db.bats          # model SQLite + api (alta autoincrement/sql_escape/update/login, seed.sql)
bats tests/errors.bats      # todo error (amable o SQL) deja rastro en error.log
bats tests/report.bats      # HTML con tabla ID/Nombre/Precio
bats tests/systemlog.bats   # cada éxito audita en system.log (fallos no escriben)
```

Los tests aíslan disco por env temporal (`DB`, `LOG`, `ERRLOG` apuntan a `mktemp -d`); nunca tocan `var/` real. La paridad `--cli` vs `--tui` se verifica manual (mismo flujo, mismos logs) porque `whiptail` requiere TTY.

## Referencia `whiptail` (para `lib/ui/tui.sh`)

```bash
whiptail --title "Acceso" --menu "Elija:" 15 50 3 1 "Iniciar sesión" 2 "Registrar usuario" 3 "Salir" 3>&1 1>&2 2>&3
whiptail --title "Alta" --inputbox "Ingrese Nombre:" 10 40 3>&1 1>&2 2>&3
whiptail --title "Acceso" --passwordbox "Contraseña:" 10 40 3>&1 1>&2 2>&3
whiptail --title "Aviso" --msgbox "Producto 1 guardado." 10 40
```

Contratos que no cambian: `productos.html` (título + `<table>` `ID, Nombre, Precio`), `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`.
