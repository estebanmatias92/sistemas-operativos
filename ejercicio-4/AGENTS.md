# AGENTS.md — ejercicio-4 (Lab 06 Text User Interface)

Base: `ejercicio-3.sh` (Lab 05: `var/db/data.sq3` + `SQLite3` + `system.log`/`error.log`).
Objetivo: `ejercicio-4.sh` (`--tui` default / `--cli` paridad) + `data.sq3` + `system.log` + `error.log` + `productos.html` sin cambios visibles en datos ni en flujo.

## Idea (no romper)

Variabilidad de interfaz = misma especificación, distinto client. Los casos de uso (`add_product`, `register_user`, `remove/update/list_products`, `generate_report`, `login_user`) y la capa de dependencia (`valid_table`, `sql_escape`, `record_exists`, `append_record`, `delete_record`, `load_table`, `save_table`, `init_db`) no cambian; solo se agrega `lib/tui.sh` como client alternativo a `lib/ui.sh`. El dispatcher (`main` + `bin/app`) elige client por argumento: `--tui` (default, `whiptail`) o `--cli` (heredado Lab 05, referencia de transparencia).

## Contratos (no cambiar sin avisar)

- `data.sq3` (fuente de verdad, heredado Lab 05):
  ```sql
  CREATE TABLE IF NOT EXISTS usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS productos(id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio TEXT NOT NULL);
  ```
  `id`/`username` únicos (no duplicados en altas); `nombre` con espacios sí, sin tab; `precio` `^[0-9]+(\.[0-9]{1,2})?$`; `username` `^[A-Za-z0-9_.-]+$`; `hash` hex 64, nunca texto plano.
- `db/*.tsv`: legacy Lab 04, solo evidencia histórica; ningún código lo lee ni lo escribe (la semilla canónica es `sql/seed.sql`).
- `system.log`: `fecha/hora<TAB>id<TAB>usuario<TAB>acción` por cada éxito. Fallos no escriben. `Cancel/Esc` en TUI = volver al menú, sin auditoría ni error.
- `error.log`: todo error de ejecución (errores amables vía `log_error()` = `fecha/hora mensaje` en stderr + archivo; `stderr` de `sqlite3` vía `2>>"$ERRLOG"` crudo). `Cancel/Esc` nunca va a `error.log`.
- Mensajes de error enriquecidos: qué pasó + dato involucrado entrecomillado (`id="A1"`, `"u1"`); nunca secretos (contraseñas/hashes jamás se loguean ni se muestran; en TUI solo vía `--passwordbox`).
- `productos.html`: título + `<table>` con `ID, Nombre, Precio`, idéntico al Lab 04/05. En TUI el `stdout` de `generate_report` se exhibe en `--msgbox`.
- Altas: validar formato + chequeo duplicado (`SELECT`) antes de `INSERT`; mensaje amable, sin escribir si falla (igual en ambos clients).
- Dual client: `--cli` paridad byte-a-byte con `ejercicio-3.sh`; `--tui` mismo flujo y mismos logs, solo cambia el widget. Default sin args = `--tui`.
- Spec ejecutable en cabecera de `ejercicio-4.sh` (`RE_PRECIO`, `RE_USER`, `OPT_*`); este archivo es solo espejo.

## Convenciones Bash (acordadas, heredadas Lab 04/05)

- Shebang `#!/usr/bin/env bash` + `set -euo pipefail` + `chmod +x` antes de probar/entregar.
- Nombres: `minusculas_con_guion_bajo` para vars/funcs, `MAYUSCULAS` para config. Rutas (`DB`, `LOG`, `ERRLOG`, `PRODUCTS_HTML`) van con `declare -g` MUTABLE a propósito (tests las aíslan por env); spec (`RE_PRECIO`, `RE_USER`, `OPT_*`) con `declare -gr/-gri` inmutable. `-g` porque se sourcea dentro de funciones (bats `setup`).
- Siempre citar: `"$id" "$nombre" "$pass"`; `printf` sobre `echo`; `local` dentro de funciones; `return 0/1`, nunca `exit` adentro (tampoco en `lib/tui.sh`).
- Fuente de verdad = disco (`var/db/data.sq3`); arrays solo como caché temporal por operación, nunca estado global persistente.
- Ojo `set -e`: `grep -q` sobre logs y `whiptail` con `Cancel/Esc` (exit != 0) sí retornan != 0 (usar `||` / `if`).
- Modular: `lib/*.sh` sin `exit` ni código top-level (solo funcs + `declare`); orden de carga `config→validators→crypto→logging→db→products/auth→report→ui→tui`; dependencias solo hacia abajo (`ui/tui→casos→db`, `logging` cross-cutting, `validators/crypto` puros). Casos puros nunca invocan `whiptail`/`read` directo.

## Convenciones SQL (acordadas Lab 05, sin cambios)

- Keywords en `MAYÚSCULAS` (`SELECT`, `INSERT INTO`, `UPDATE`, `DELETE FROM`, `CREATE TABLE IF NOT EXISTS`); identificadores en `minusculas` tal cual el schema de Contratos (`productos`, `usuarios`, `id`, `nombre`, `precio`, `username`, `hash`).
- Una sentencia por invocación: `sqlite3 "$DB" "SENTENCIA;"` (comillas dobles Bash afuera, simples SQL adentro). Nunca interpolar `$var` crudo: siempre pasar por `sql_escape` (`esc=${val//\'/\'\'}`) que duplica `'` como `''`.
- Sin `SELECT *`: columnas explícitas en orden estable (`SELECT id,nombre,precio FROM productos`, `SELECT hash FROM usuarios WHERE username=...`).
- Lecturas tabulares con `-separator "$(printf '\t')"` para reusar `IFS=$'\t' read -r` sin cambiar el parsing del Lab 04.
- Schema canónico = heredoc inline en `init_db` (mantiene entregable de un solo `.sh`); `schema.sql` es opcional solo como referencia, nunca requerido en runtime.
- Errores: `stderr` de `sqlite3` va a `"$ERRLOG"` (`2>>"$ERRLOG"`); distinguir cero-filas (`exit 0` + salida vacía → `record_exists` = 1) de fallo constraint (`exit != 0` → mensaje amable + `return 1`, disco intacto). Proteger cada llamada con `if` por `set -e`.
- Transacciones: autocommit por sentencia alcanza; el chequeo amable previo en Bash (`record_exists` vía `SELECT`) se mantiene y `PRIMARY KEY`/`UNIQUE` queda como red de seguridad. Sin `BEGIN/COMMIT` salvo multi-`INSERT` futuro.
- Prohibido `sed -i`, `awk` o `grep` sobre `data.sq3`; `grep` solo sobre `system.log`/`error.log`.

## Convenciones TUI (acordadas Lab 06)

- Solo `lib/tui.sh` invoca `whiptail`; `lib/ui.sh` (CLI) queda intacto para paridad. Casos puros (`products.sh`, `auth.sh`) no saben en qué client corren: la TUI captura su `stdout`/`stderr` y lo exhibe en `--msgbox`.
- Mapeo fijo: menúes → `--menu`; texto → `--inputbox`; secreto → `--passwordbox`; avisos/éxitos/errores → `--msgbox`; listado largo → `--textbox` con tmpfile (+ `--scrolltext` si es `--msgbox` corto).
- Resultado de `whiptail` sale por `stderr`: capturar con swap `3>&1 1>&2 2>&3` (ej: `val="$(whiptail ... 3>&1 1>&2 2>&3)"`). Proteger con `if` por `set -e`; `exit != 0` = `Cancel/Esc` = abortar flujo y volver al menú (sin `log_error`, sin `log_action`, sin escribir).
- Títulos y tamaños estándar (`--title`, `alto ancho`, ej `15 50 3` para menúes, `10 40` para inputs); passwords con `read` nunca en TUI (solo `--passwordbox`).
- Dependencia: `--tui` exige `command -v whiptail` + TTY (`[[ -t 0 && -t 1 ]]`); si falta → mensaje amable vía `log_error()` y `return 1` (no fallback silencioso a CLI). `--cli` y `bats` nunca exigen TTY.
- Dispatcher: `main()` en `lib/ui.sh` (o wrapper) parsea `--tui` (default) / `--cli` / `--help`; `bin/app` propaga `"$@"`. Sin args = `--tui`.

## Layout canónico (esta app)

```text
ejercicio-4/
  ejercicio-4.sh   # ENTREGABLE (generado por `make build` desde lib/; no editar a mano).
  bin/app          # entrypoint flaco dev (source lib/* en orden + main "$@"; propaga --tui/--cli).
  lib/             # fuente de verdad: config, validators, crypto, logging, db,
                   #   products, auth, report, ui (CLI heredado), tui (NUEVO Lab 06).
                   #   Orden: config→validators→crypto→logging→db→products/auth→report→ui→tui.
  sql/schema.sql   # fuente canónica SQL; sql/seed.sql = datos ejemplo (INSERT OR IGNORE).
  var/db/          # fuente de verdad runtime: data.sq3 (único archivo; sin *.tsv).
                   # Se crea con init_db (heredoc) o make init (schema + seed).
  var/log/         # system.log (auditoría TSV) + error.log (texto).
  var/report/      # productos.html (derivado, opción 5).
  tests/           # *.bats (validators, db, errors, report, systemlog). Sin TTY; cubren casos puros
                   #   compartidos por ambos clients (heredados Lab 05).
  db/              # legacy Lab 04, solo referencia; ningún código lo lee ni lo escribe.
  productos.html   # legacy Lab 04 en raíz (referencia); el vigente vive en var/report/.
  Makefile         # tooling (`make help`): build/test/check/run/run-cli/run-dist/init/seed/clean.
  README.md        # uso dual client + mapeo whiptail + verificación.
  AGENTS.md        # este archivo (espejo de la spec; no duplica lógica).
```

- Dir de trabajo = este dir: `DB`, `LOG`, `ERRLOG`, `PRODUCTS_HTML` son rutas relativas a él (`var/...`).
- Generados (`var/db/data.sq3`, `var/log/*`, `var/report/*`) se pueden borrar y reconstruir (`make init` + uso + opción 5); `db/` no se reconstruye ni se migra automáticamente.
- `var/` se versiona a propósito con un ejemplo (igual que `*.log` antes): evidencia de ejecución para el lab.

## Patrones del lab (usar estos, no alternativas)

```bash
# --- heredados Lab 05 (no cambian) ---
sqlite3 "$DB" <<'SQL'   # init_db auto-crea (heredoc inline; schema.sql opcional)
CREATE TABLE IF NOT EXISTS usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS productos(id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio TEXT NOT NULL);
SQL
esc=${id//\'/\'\'}   # sql_escape: duplicar ' como '' antes de interpolar
sqlite3 "$DB" "SELECT 1 FROM productos WHERE id='$esc';"            # record_exists (salida vacía = no existe)
sqlite3 "$DB" "INSERT INTO productos(id,nombre,precio) VALUES('$id','$nombre','$precio');" 2>>"$ERRLOG"
sqlite3 "$DB" "DELETE FROM productos WHERE id='$id';" 2>>"$ERRLOG"
sqlite3 "$DB" -separator "$(printf '\t')" "SELECT id,nombre,precio FROM productos;"
hash=$(printf '%s' "$pass" | sha256sum | cut -d' ' -f1)
printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$uid" "$user" "$accion" >> system.log
# --- nuevos Lab 06 (solo lib/tui.sh) ---
val="$(whiptail --title "Alta" --inputbox "Ingrese ID:" 10 40 3>&1 1>&2 2>&3)" || return 0  # Cancel = volver
pass="$(whiptail --title "Acceso" --passwordbox "Contraseña:" 10 40 3>&1 1>&2 2>&3)" || return 0
opt="$(whiptail --title "Acciones" --menu "Elija:" 15 50 6 1 "Alta producto" 2 "Baja producto" 3 "Mostrar inventario" 4 "Editar producto" 5 "Generar reporte HTML" 6 "Salir" 3>&1 1>&2 2>&3)" || return 0
whiptail --title "Aviso" --msgbox "Producto A1 guardado." 10 40
command -v whiptail >/dev/null || { log_error "Error: whiptail no instalado (se requiere para --tui)."; return 1; }
[[ -t 0 && -t 1 ]] || { log_error "Error: --tui requiere terminal interactiva (TTY)."; return 1; }
```

## Verificación

```bash
make help          # lista targets (build/test/check/run/run-cli/run-dist/init/seed/clean)
make build         # regenera ejercicio-4.sh desde lib/ (entregable)
make check         # bash -n lib/* + bin/app + bundle (shfmt solo aviso)
make test          # bats tests/ (heredados Lab 05: validators, db, errors, report, systemlog; sin TTY)
make init          # var/db/data.sq3 desde sql/schema.sql + sql/seed.sql
./ejercicio-4.sh --help   # uso dual client
./ejercicio-4.sh --cli    # paridad Lab 05
./ejercicio-4.sh          # TUI default (requiere TTY + whiptail)
sqlite3 var/db/data.sq3 ".tables" && sqlite3 var/db/data.sq3 ".schema"
cat var/log/system.log var/log/error.log
./bin/app --cli    # dev CLI; ./bin/app --tui = dev TUI
```

## Trabajo con el usuario

- Prioridad: entender antes que implementar. Dictar de a un micro-paso: código + explicación breve de cada instrucción/expresión, probar, recién avanzar.
- No reintroducir `db/*.tsv` como fuente de verdad ni `MAX=3` ni `declare -A inventario` global; no usar `sed -i`, `awk` o `grep` sobre `data.sq3` donde el lab pide `sqlite3`.
- No cambiar menúes, opciones ni mensajes visibles sin avisar (transparencia). `lib/ui.sh` no se toca salvo el dispatcher; todo lo nuevo va en `lib/tui.sh`.
- No loguear ni exhibir secretos; `Cancel/Esc` nunca es error.
- Entrega: archivo `ejercicio-4.sh` + `data.sq3` de ejemplo en este dir + notificar en Classroom.
