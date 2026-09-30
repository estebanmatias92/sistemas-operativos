# AGENTS.md — ejercicio-3 (Lab 05 Variabilidad)

Base: `ejercicio-2.sh` (Lab 04: `db/*.tsv` + `grep`/`tmp+mv`).
Objetivo: `ejercicio-3.sh` + `data.sq3` + `system.log` + `error.log` + `productos.html` sin cambios visibles.

## Idea (no romper)

Variabilidad = misma especificación, distinta implementación. Los casos de uso (`add_product`, `register_user`, `remove/update/list_products`, `generate_report`, `login_user`) mantienen semántica; sus firmas se extendieron con `uid`/`usuario` al final (opción B, punto 5: prepara un futuro FK `productos.owner → usuarios.id`); solo se redirige la capa de dependencia (`valid_table`, `sql_escape`, `record_exists`, `append_record`, `delete_record`, `load_table`, `save_table`, `init_db`) de `TSV` a `SQLite3` (`table()` del Lab 04 se eliminó: ya no hay rutas `.tsv` que resolver).

## Contratos (no cambiar sin avisar)

- `data.sq3` (fuente de verdad, reemplaza `db/*.tsv`):
  ```sql
  CREATE TABLE IF NOT EXISTS usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS productos(id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio TEXT NOT NULL);
  ```
  `id`/`username` únicos (no duplicados en altas); `nombre` con espacios sí, sin tab; `precio` `^[0-9]+(\.[0-9]{1,2})?$`; `username` `^[A-Za-z0-9_.-]+$`; `hash` hex 64, nunca texto plano.
- `db/*.tsv`: legacy Lab 04, solo evidencia histórica; ningún código lo lee ni lo escribe (la semilla canónica es `sql/seed.sql`).
- `system.log`: `fecha/hora<TAB>id<TAB>usuario<TAB>acción` por cada operación.
- `error.log`: todo error de ejecución (errores amables vía `log_error()` = `fecha/hora mensaje` en stderr + archivo; `stderr` de `sqlite3` vía `2>>"$ERRLOG"` crudo).
- Mensajes de error enriquecidos: qué pasó + dato involucrado entrecomillado (`id="A1"`, `"u1"`); nunca secretos (contraseñas/hashes jamás se loguean).
- `productos.html` (raíz): título + `<table>` con `ID, Nombre, Precio`, idéntico al Lab 04.
- Altas: validar formato + chequeo duplicado (`SELECT`) antes de `INSERT`; mensaje amable, sin escribir si falla.
- Spec ejecutable en cabecera de `ejercicio-3.sh` (`RE_PRECIO`, `RE_USER`); este archivo es solo espejo.

## Convenciones Bash (acordadas, heredadas Lab 04)

- Shebang `#!/usr/bin/env bash` + `set -euo pipefail` + `chmod +x` antes de probar/entregar.
- Nombres: `minusculas_con_guion_bajo` para vars/funcs, `MAYUSCULAS` para config. Rutas (`DB`, `LOG`, `ERRLOG`, `PRODUCTS_HTML`) van con `declare -g` MUTABLE a propósito (tests las aíslan por env); spec (`RE_PRECIO`, `RE_USER`, `OPT_*`) con `declare -gr/-gri` inmutable. `-g` porque se sourcea dentro de funciones (bats `setup`).
- Siempre citar: `"$id" "$nombre" "$pass"`; `printf` sobre `echo`; `local` dentro de funciones; `return 0/1`, nunca `exit` adentro.
- Fuente de verdad = disco (`var/db/` hoy TSV, `var/db/data.sq3` en Fase SQLite); arrays solo como caché temporal por operación, nunca estado global persistente.
- Ojo `set -e`: `grep -q` sobre logs sí retorna 1 si no encuentra (usar `||` / `if`).
- Modular: `lib/*.sh` sin `exit` ni código top-level (solo funcs + `declare`); orden de carga `config→validators→crypto→logging→db→products/auth→report→ui`; dependencias solo hacia abajo (`ui→casos→db`, `logging` cross-cutting, `validators/crypto` puros).

## Convenciones SQL (acordadas Lab 05)

- Keywords en `MAYÚSCULAS` (`SELECT`, `INSERT INTO`, `UPDATE`, `DELETE FROM`, `CREATE TABLE IF NOT EXISTS`); identificadores en `minusculas` tal cual el schema de Contratos (`productos`, `usuarios`, `id`, `nombre`, `precio`, `username`, `hash`).
- Una sentencia por invocación: `sqlite3 "$DB" "SENTENCIA;"` (comillas dobles Bash afuera, simples SQL adentro). Nunca interpolar `$var` crudo: siempre pasar por `sql_escape` (`esc=${val//\'/\'\'}`) que duplica `'` como `''`.
- Sin `SELECT *`: columnas explícitas en orden estable (`SELECT id,nombre,precio FROM productos`, `SELECT hash FROM usuarios WHERE username=...`).
- Lecturas tabulares con `-separator "$(printf '\t')"` para reusar `IFS=$'\t' read -r` sin cambiar el parsing del Lab 04.
- Schema canónico = heredoc inline en `init_db` (mantiene entregable de un solo `.sh`); `schema.sql` es opcional solo como referencia, nunca requerido en runtime.
- Errores: `stderr` de `sqlite3` va a `"$ERRLOG"` (`2>>"$ERRLOG"`); distinguir cero-filas (`exit 0` + salida vacía → `record_exists` = 1) de fallo constraint (`exit != 0` → mensaje amable + `return 1`, disco intacto). Proteger cada llamada con `if` por `set -e`.
- Transacciones: autocommit por sentencia alcanza; el chequeo amable previo en Bash (`record_exists` vía `SELECT`) se mantiene y `PRIMARY KEY`/`UNIQUE` queda como red de seguridad. Sin `BEGIN/COMMIT` salvo multi-`INSERT` futuro.
- Prohibido `sed -i`, `awk` o `grep` sobre `data.sq3`; `grep` solo sobre `system.log`/`error.log`.

## Layout canónico (esta app)

```text
ejercicio-3/
  ejercicio-3.sh   # ENTREGABLE (generado por `make build` desde lib/; no editar a mano).
  bin/app          # entrypoint flaco dev (source lib/* en orden + main "$@").
  lib/             # fuente de verdad: config, validators, crypto, logging, db,
                   #   products, auth, report, ui (ver orden en Convenciones Bash).
  sql/schema.sql   # fuente canónica SQL; sql/seed.sql = datos ejemplo (INSERT OR IGNORE).
  var/db/          # fuente de verdad runtime: data.sq3 (único archivo; sin *.tsv).
                   # Se crea con init_db (heredoc) o make init (schema + seed).
  var/log/         # system.log (auditoría TSV) + error.log (texto).
  var/report/      # productos.html (derivado, opción 5).
  tests/           # *.bats (validators, db, report). Aíslan disco por env temporal.
  db/              # legacy Lab 04, solo referencia; ningún código lo lee ni lo escribe.
  productos.html   # legacy Lab 04 en raíz (referencia); el vigente vive en var/report/.
  Makefile         # tooling (`make help`): build/test/check/run/init/seed/clean.
  README.md        # uso + schema propuesto + verificación.
  AGENTS.md        # este archivo (espejo de la spec; no duplica lógica).
```

- Dir de trabajo = este dir: `DB`, `LOG`, `ERRLOG`, `PRODUCTS_HTML` son rutas relativas a él (hoy `var/...`).
- Generados (`var/db/data.sq3`, `var/log/*`, `var/report/*`) se pueden borrar y reconstruir (`make init` + uso + opción 5); `db/` no se reconstruye ni se migra automáticamente.
- `var/` se versiona a propósito con un ejemplo (igual que `*.log` antes): evidencia de ejecución para el lab.

## Patrones del lab (usar estos, no alternativas)

```bash
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
read -sp "Contraseña: " pass; echo  # passwords ocultas; read -rp para resto
```

## Verificación

```bash
make help          # lista targets (build/test/check/run/init/seed/clean)
make build         # regenera ejercicio-3.sh desde lib/ (entregable)
make check         # bash -n lib/* + bin/app + bundle (shfmt solo aviso)
make test          # bats tests/ (18 tests: validators, db, errors, report)
make init          # var/db/data.sq3 desde sql/schema.sql + sql/seed.sql
sqlite3 var/db/data.sq3 ".tables" && sqlite3 var/db/data.sq3 ".schema"
cat var/log/system.log var/log/error.log
./bin/app          # dev (modular); ./ejercicio-3.sh = bundle entregable
```

## Trabajo con el usuario

- Prioridad: entender antes que implementar. Dictar de a un micro-paso: código + explicación breve de cada instrucción/expresión, probar, recién avanzar.
- No reintroducir `db/*.tsv` como fuente de verdad ni `MAX=3` ni `declare -A inventario` global; no usar `sed -i`, `awk` o `grep` sobre `data.sq3` donde el lab pide `sqlite3`.
- No cambiar menúes ni mensajes visibles sin avisar (transparencia).
- Entrega: archivo `ejercicio-3.sh` + `data.sq3` de ejemplo en este dir + notificar en Classroom.
