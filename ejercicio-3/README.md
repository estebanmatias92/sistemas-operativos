# Ejercicio 3 — Lab 05 Variabilidad de Implementación

Base: `ejercicio-2.sh` (Lab 04: auth con `sha256`, persistencia en `db/*.tsv`, reporte `productos.html`).

## Idea

Misma **especificación**, distinta **implementación** (variabilidad): los menúes y casos de uso se comportan exactamente igual para el usuario, pero por dentro las funciones no tocan `TSV` (ese formato sobrevive solo en `system.log`) y persisten en `SQLite3` (`var/db/data.sq3`).

En `Bash` no hay clases abstractas ni `templates`: la estructura es el uso adecuado de **funciones**. Los casos de uso (`add_product`, `register_user`, `remove/update/list`, `generate_report`) no tocan disco directo; solo la capa de dependencia (`valid_table`, `sql_escape`, `record_exists`, `append_record`, `delete_record`, `load_table`, `save_table`, `init_db`) habla `SQL` contra `var/db/data.sq3`.

## Requerimientos funcionales (consigna)

1. **Instalar** `SQLite3` en la VM (`sudo apt install sqlite3`).
2. **Diseñar** schema `SQL` para `usuario` y `productos` (propuesto abajo).
3. **Inicializar**: al arrancar, si `data.sq3` no existe en el dir de trabajo, construirlo (función `init_db`).
4. **Reimplementar** todo acceso a `TSV` como `SQL` contra `data.sq3`.
5. **Auditar** cada operación en `system.log` (`TSV`: `fecha/hora<TAB>id<TAB>usuario<TAB>acción`).
6. **Reportar** cualquier error en `error.log`.

## Requerimientos no funcionales

- **Transparencia**: menúes idénticos, cambio interno inadvertido.
- **Conservar** criterio actividad 2: contraseñas con `sha256` (nunca texto plano), no duplicados en altas, validaciones `RE_PRECIO` / `RE_USER`.
- **Mantenibilidad**: funciones cortas de una tarea, `return 0/1`, nunca `exit` adentro.
- **Dependencia**: CLI `sqlite3` disponible; `data.sq3` auto-creado.
- **Logs**: `system.log` en `TSV`, `error.log` en texto; ambos versionados a propósito como evidencia de ejecución (regla `*.log` comentada en `.gitignore`).

## Uso

```bash
make help      # lista todos los comandos
make init      # crea var/db/data.sq3 (schema + seed) — una vez
make run       # app modular dev (bin/app + lib/)
make run-dist  # entregable generado (./ejercicio-3.sh)
```

O directo (sin make):

```bash
chmod +x bin/app ejercicio-3.sh
./bin/app        # modular
./ejercicio-3.sh # bundle entregable (generado con `make build`)
```

1. Crea `var/db/data.sq3` (si falta, `make init` o `init_db`) + `var/log/system.log` / `var/log/error.log` según operación.
2. Menú **ACCESO**: `1` iniciar sesión, `2` registrar usuario, `3` salir.
3. Menú **ACCIONES** (post-login): `1` alta, `2` baja, `3` mostrar, `4` editar, `5` generar reporte HTML, `6` salir.

Ejemplo de sesión (igual que ejercicio-2):

```
ACCIONES:
1. Alta producto
...
Opción: 1
Ingrese ID: A1
Ingrese Nombre: Yerba Mate
Ingrese Precio: 120.50
Producto A1 guardado.
...
Opción: 5
Reporte generado en var/report/productos.html.
```

## Archivos (layout canónico)

```text
ejercicio-3.sh   # ENTREGABLE (generado por `make build` desde lib/; no editar a mano)
bin/app          # entrypoint dev (source lib/* + main)
lib/             # config, validators, crypto, logging, db, products, auth, report, ui
sql/schema.sql   # schema canónico; sql/seed.sql = datos ejemplo
var/db/data.sq3  # fuente de verdad (único archivo; sin *.tsv)
var/log/         # system.log (auditoría TSV) + error.log (texto)
var/report/      # productos.html (derivado, opción 5)
tests/           # *.bats — `make test` (bats 1.14+; ya disponible en el entorno)
db/              # legacy Lab 04, solo referencia; ningún código lo lee ni lo escribe
Makefile         # `make help` para ver comandos
```

- `ejercicio-3.sh`: bundle entregable (fuente de verdad = `lib/`).
- `var/db/data.sq3`: fuente de verdad (reemplaza a `db/*.tsv`, que queda como legacy sin lectura en runtime).
- `var/log/system.log`: auditoría (`fecha/hora<TAB>id<TAB>usuario<TAB>acción`, versionado como evidencia).
- `var/log/error.log`: errores de ejecución (versionado como evidencia).
- `var/report/productos.html`: reporte derivado (se regenera con la opción 5, no es fuente de verdad).

## Schema propuesto

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
make test          # bats tests/ — 13 tests (validators, db, report)
make build         # regenera ejercicio-3.sh desde lib/
make init          # var/db/data.sq3 desde schema + seed
sqlite3 var/db/data.sq3 ".tables"      # usuarios productos
sqlite3 var/db/data.sq3 ".schema"      # contraste con sql/schema.sql
cat var/log/system.log var/log/error.log
```

Tests con `bats` (cómo ejecutar y qué cubren):

```bash
bats tests/                 # toda la suite
bats tests/validators.bats  # validadores puros (precio/usuario/producto)
bats tests/db.bats          # adapter SQLite + casos (alta/duplicado/sql_escape/update/login, seed.sql)
bats tests/report.bats      # HTML con tabla ID/Nombre/Precio
```

Los tests aíslan disco por env temporal (`DB`, `LOG`, `ERRLOG` apuntan a `mktemp -d`); nunca tocan `var/` real.

## Referencia SQLite3 (para `ejercicio-3.sh`)

```bash
sqlite3 var/db/data.sq3 "SELECT 1 FROM productos WHERE id='A1';"   # ¿existe? (record_exists)
sqlite3 var/db/data.sq3 "INSERT INTO productos(id,nombre,precio) VALUES('A1','Yerba Mate','120.50');"
sqlite3 var/db/data.sq3 "DELETE FROM productos WHERE id='A1';"
sqlite3 var/db/data.sq3 -separator $'\t' "SELECT id,nombre,precio FROM productos;"  # listar
esc=${val//\'/\'\'}   # escapar ' como '' antes de interpolar en SQL
```

Contratos que no cambian: `productos.html` (título + `<table>` `ID, Nombre, Precio`), `RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'`, `RE_USER='^[A-Za-z0-9_.-]+$'`.
