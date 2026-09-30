#!/usr/bin/env bash
set -euo pipefail
# GENERADO por `make build` desde lib/*.sh — no editar a mano.
# Fuente de verdad: lib/. Entregable Classroom: ./ejercicio-3.sh

# ---- lib/config.sh ----
# Se importa primero; no tiene lógica, solo declare -gr.
# -g: sourcing dentro de funciones (bats setup, bin/app) crea globals, no locals.
# Rutas MUTABLES a propósito (declare -g sin -r): tests y runtime las
# sobreescriben por env (DB=... source config). Fuente de verdad = "$DB".
# Spec (RE_*, OPT_*) sí inmutable (-gr/-gri).
# Orden de carga: config -> validators -> crypto -> logging -> db -> auth/products/report -> ui.

declare -g APP_ROOT="${APP_ROOT:-.}"
declare -g DB="${DB:-var/db/data.sq3}"
declare -g LOG="${LOG:-var/log/system.log}"
declare -g ERRLOG="${ERRLOG:-var/log/error.log}"
declare -g PRODUCTS_HTML="${PRODUCTS_HTML:-var/report/productos.html}"

declare -gr RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'
declare -gr RE_USER='^[A-Za-z0-9_.-]+$'

declare -gri OPT_ADD=1
declare -gri OPT_REMOVE=2
declare -gri OPT_LIST=3
declare -gri OPT_UPDATE=4
declare -gri OPT_REPORT=5
declare -gri OPT_EXIT=6

# ---- lib/validators.sh ----
# Las regex van en variable SIN comillas: con comillas no matchean.

is_valid_id() {
    local id="$1"
    [[ -n "$id" && "$id" != *$'\t'* ]]
}

is_valid_name() {
    local nombre="$1"
    [[ -n "$nombre" && "$nombre" != *$'\t'* ]]
}

is_valid_price() {
    local precio="$1"
    [[ "$precio" =~ $RE_PRECIO ]]
}

is_valid_username() {
    local user="$1"
    [[ "$user" =~ $RE_USER ]]
}

# @brief Regla "¿este producto puede guardarse?" (solo formato; el duplicado
# lo chequea el llamador con record_exists).
# @param $1 id, $2 nombre, $3 precio.
# @return 0 válido / 1 inválido.
product_valid() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    is_valid_id "$id" && is_valid_name "$nombre" && is_valid_price "$precio"
}

# ---- lib/crypto.sh ----

# @brief SHA-256 de una contraseña (hex 64).
# @param $1 contraseña en claro (solo vive en memoria).
hash_password() {
    local pass="$1"
    printf '%s' "$pass" | sha256sum | cut -d' ' -f1
}

# ---- lib/logging.sh ----
# Formato system.log: fecha/hora<TAB>id<TAB>usuario<TAB>acción

# @brief Adjunta una línea de auditoría.
# @param $1 id, $2 usuario, $3 acción.
log_action() {
    local id="$1"
    local user="$2"
    local accion="$3"
    mkdir -p "$(dirname "$LOG")"
    printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$id" "$user" "$accion" >> "$LOG"
}

# @brief Adjunta un error a error.log + stderr (no sale del programa).
# @param $@ mensaje.
log_error() {
    mkdir -p "$(dirname "$ERRLOG")"
    printf '%s\n' "$*" | tee -a "$ERRLOG" >&2
}

# ---- lib/db.sh ----
# Variabilidad Lab 05: mismas firmas que el adapter TSV del Lab 04, distinta
# implementación. Nadie fuera de aquí invoca `sqlite3` ni arma SQL crudo.
#
# TIPOS:
#   cache   : array asociativo temporal del llamador (se crea, usa y descarta).
#             clave = id/username, valor = resto opaco con su TAB.
#             Ej: cache=([A1]="Yerba Mate\t120.50"). Nunca global persistente.

# @brief Escapa un valor para interpolarlo como literal SQL (' -> '').
# @param $1 valor crudo.
# @stdout valor escapado. Siempre usar antes de interpolar en SQL.
sql_escape() {
    local val="$1"
    printf '%s' "${val//\'/\'\'}"
}

# @brief Lista blanca de tablas: un input nunca se convierte en SQL arbitrario.
# @param $1 nombre de tabla.
# @return 0 conocida / 1 desconocida.
valid_table() {
    case "$1" in
        productos|usuarios) return 0 ;;
        *) return 1 ;;
    esac
}

# @brief Crea el schema si falta (idempotente). Consigna punto 3: si data.sq3
# no existe en el dir de trabajo, construirlo. Espejo de sql/schema.sql.
init_db() {
    mkdir -p "$(dirname "$DB")" "$(dirname "$LOG")" "$(dirname "$ERRLOG")" "$(dirname "$PRODUCTS_HTML")"
    if ! sqlite3 "$DB" <<'SQL' 2>>"$ERRLOG"; then
CREATE TABLE IF NOT EXISTS usuarios(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS productos(id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio TEXT NOT NULL);
SQL
        return 1
    fi
    [[ -f "$LOG" ]] || : > "$LOG"
    [[ -f "$ERRLOG" ]] || : > "$ERRLOG"
}

# @brief ¿Existe esta clave? SELECT amable (salida vacía = no existe).
# @param $1 tabla, $2 clave (id o username).
# @return 0 existe / 1 no existe o tabla inválida.
# @note sqlite3 retorna 0 aun sin filas: chequear salida vacía, no $?.
record_exists() {
    local tbl="$1"
    local key="$2"
    local esc out
    valid_table "$tbl" || return 1
    esc="$(sql_escape "$key")"
    if [[ "$tbl" == "productos" ]]; then
        if ! out="$(sqlite3 "$DB" "SELECT 1 FROM productos WHERE id='$esc';" 2>>"$ERRLOG")"; then
            return 1
        fi
    else
        if ! out="$(sqlite3 "$DB" "SELECT 1 FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG")"; then
            return 1
        fi
    fi
    [[ -n "$out" ]]
}

# @brief Alta cruda (sin validar): el llamador valida formato + duplicado antes.
# @param $1 tabla, $2 línea "col1\tcol2[\tcol3]" (mismo formato que el TSV del Lab 04).
# @return 0 insertado / 1 tabla inválida o fallo constraint (disco intacto).
append_record() {
    local tbl="$1"
    local line="$2"
    local c1 c2 c3 e1 e2 e3
    valid_table "$tbl" || return 1
    IFS=$'\t' read -r c1 c2 c3 <<< "$line"
    e1="$(sql_escape "$c1")"
    e2="$(sql_escape "$c2")"
    e3="$(sql_escape "$c3")"
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "INSERT INTO productos(id,nombre,precio) VALUES('$e1','$e2','$e3');" 2>>"$ERRLOG" || return 1
    else
        sqlite3 "$DB" "INSERT INTO usuarios(username,hash) VALUES('$e1','$e2');" 2>>"$ERRLOG" || return 1
    fi
}

# @brief Baja por clave.
# @param $1 tabla, $2 clave.
delete_record() {
    local tbl="$1"
    local key="$2"
    local esc
    valid_table "$tbl" || return 1
    esc="$(sql_escape "$key")"
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "DELETE FROM productos WHERE id='$esc';" 2>>"$ERRLOG" || return 1
    else
        sqlite3 "$DB" "DELETE FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG" || return 1
    fi
}

# @brief Foto de la tabla en el cache del llamador (ver TIPOS).
# @param $1 tabla.
# @param $2 cache por nombre (se vacía y se llena).
# @return 0 ok / 1 tabla inválida o fallo SQL.
load_table() {
    local tbl="$1"
    local -n ref="$2"
    local k resto
    local sep rows

    valid_table "$tbl" || return 1
    ref=()
    sep="$(printf '\t')"

    if [[ "$tbl" == "productos" ]]; then
        if ! rows="$(sqlite3 "$DB" -separator "$sep" "SELECT id,nombre,precio FROM productos;" 2>>"$ERRLOG")"; then
            return 1
        fi
    else
        if ! rows="$(sqlite3 "$DB" -separator "$sep" "SELECT username,hash FROM usuarios;" 2>>"$ERRLOG")"; then
            return 1
        fi
    fi
    [[ -z "$rows" ]] && return 0
    while IFS=$'\t' read -r k resto; do
        [[ -z "$k" ]] && continue
        ref["$k"]="$resto"
    done <<< "$rows"
}

# @brief Vuelca un cache modificado (compat Lab 04): DELETE + re-INSERT.
# Mantiene el flujo `load -> mutar -> save` de update_product sin cambios.
# @param $1 tabla.
# @param $2 cache por nombre.
save_table() {
    local tbl="$1"
    local -n ref="$2"
    local k resto nombre precio e1 e2 e3

    valid_table "$tbl" || return 1
    if [[ "$tbl" == "productos" ]]; then
        sqlite3 "$DB" "DELETE FROM productos;" 2>>"$ERRLOG" || return 1
        for k in "${!ref[@]}"; do
            resto="${ref[$k]}"
            IFS=$'\t' read -r nombre precio <<< "$resto"
            e1="$(sql_escape "$k")"
            e2="$(sql_escape "$nombre")"
            e3="$(sql_escape "$precio")"
            sqlite3 "$DB" "INSERT INTO productos(id,nombre,precio) VALUES('$e1','$e2','$e3');" 2>>"$ERRLOG" || return 1
        done
    else
        sqlite3 "$DB" "DELETE FROM usuarios;" 2>>"$ERRLOG" || return 1
        for k in "${!ref[@]}"; do
            e1="$(sql_escape "$k")"
            e2="$(sql_escape "${ref[$k]}")"
            sqlite3 "$DB" "INSERT INTO usuarios(username,hash) VALUES('$e1','$e2');" 2>>"$ERRLOG" || return 1
        done
    fi
}

# ---- lib/products.sh ----

# @brief Alta: valida formato, rechaza duplicado y hace append.
# @param $1 id, $2 nombre (admite espacios), $3 precio (ver RE_PRECIO).
# @return 0 guardado / 1 inválido o duplicado (disco intacto).
add_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"

    if ! product_valid "$id" "$nombre" "$precio"; then
        printf 'Error: datos de producto inválidos.\n' >&2
        return 1
    fi
    if record_exists productos "$id"; then
        printf 'Error: el producto "%s" ya existe.\n' "$id" >&2
        return 1
    fi
    append_record productos "$(printf '%s\t%s\t%s' "$id" "$nombre" "$precio")"
    printf 'Producto %s guardado.\n' "$id"
}

remove_product() {
    local id="$1"
    if ! record_exists productos "$id"; then
        printf 'El producto no existe.\n'
        return 1
    fi
    delete_record productos "$id"
    printf 'Producto %s eliminado.\n' "$id"
}

# @brief Muestra el inventario desde un cache local que se descarta al salir.
# @note Lectura sin escritura: disco queda intacto.
list_products() {
    local -A cache
    local id resto nombre precio
    load_table productos cache

    if (( ${#cache[@]} == 0 )); then
        printf '\nLISTADO: (vacío)\n'
        return 0
    fi
    printf '\nLISTADO:\n'
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"
        printf 'ID %s : %s - $%s\n' "$id" "$nombre" "$precio"
    done
}

# @brief Modificación en memoria: load -> validar nuevo -> mutar -> save.
# @param $1 id, $2 nombre nuevo, $3 precio nuevo.
# @return 0 actualizado / 1 id inexistente o dato inválido (disco intacto).
update_product() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    local -A cache

    if ! product_valid "$id" "$nombre" "$precio"; then
        printf 'Error: datos de producto inválidos.\n' >&2
        return 1
    fi
    load_table productos cache
    if [[ -z "${cache[$id]+x}" ]]; then
        printf 'El producto no existe.\n'
        return 1
    fi
    cache["$id"]="$(printf '%s\t%s' "$nombre" "$precio")"
    save_table productos cache
    printf 'Producto %s actualizado.\n' "$id"
}

# ---- lib/auth.sh ----

# @brief Alta con hash: valida, chequea duplicado y persiste username+hash.
# @param $1 username (ver RE_USER), $2 contraseña (solo vive en memoria).
# @return 0 registrado / 1 inválido o duplicado.
register_user() {
    local user="$1"
    local pass="$2"
    local hash

    if ! is_valid_username "$user"; then
        printf 'Error: nombre de usuario inválido.\n' >&2
        return 1
    fi
    if [[ -z "$pass" ]]; then
        printf 'Error: contraseña vacía.\n' >&2
        return 1
    fi
    if record_exists usuarios "$user"; then
        printf 'Error: el usuario "%s" ya existe.\n' "$user" >&2
        return 1
    fi
    hash="$(hash_password "$pass")"
    append_record usuarios "$(printf '%s\t%s' "$user" "$hash")"
    printf 'Usuario %s registrado.\n' "$user"
}

# @brief Reproduce el hash de lo tipeado y lo compara con el guardado.
# @param $1 username, $2 contraseña tipeada.
# @return 0 acceso / 1 denegado.
login_user() {
    local user="$1"
    local pass="$2"
    local want got esc

    if ! record_exists usuarios "$user"; then
        return 1
    fi
    esc="$(sql_escape "$user")"
    if ! want="$(sqlite3 "$DB" "SELECT hash FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG")"; then
        return 1
    fi
    got="$(hash_password "$pass")"
    [[ -n "$want" && "$got" == "$want" ]]
}

register_interactive() {
    local user pass
    read -rp "Nuevo usuario: " user || return 2
    read -rsp "Contraseña: " pass || return 2; echo
    register_user "$user" "$pass"
}

# @brief Login con 3 intentos (heredado de ejercicio-1).
# @return 0 acceso / 1 denegado / 2 EOF.
auth_interactive() {
    local -i intentos=0
    local user pass

    while (( intentos < 3 )); do
        read -rp "Usuario: " user || return 2
        read -rsp "Contraseña: " pass || return 2; echo
        if login_user "$user" "$pass"; then
            printf 'Acceso concedido.\n'
            return 0
        fi
        intentos=$((intentos + 1))
        printf 'Credenciales incorrectas (%d/3 intentos).\n' "$intentos"
    done
    return 1
}

# @brief Menú de acceso: sin login o registro no se llega al inventario.
# @return 0 login OK (entrar) / 1 salir o EOF.
# @note El 1 de un fallo de validación NO sale del menú.
auth_menu() {
    local opt="" s=0
    while true; do
        printf '\nACCESO:\n'
        printf '1. Iniciar sesión\n'
        printf '2. Registrar usuario\n'
        printf '3. Salir\n'
        read -rp "Opción: " opt || return 1
        case "$opt" in
            1)
                auth_interactive; s=$?
                if (( s == 0 )); then return 0; fi
                if (( s == 2 )); then return 1; fi
                ;;
            2)
                register_interactive; s=$?
                if (( s == 2 )); then return 1; fi
                ;;
            3) return 1 ;;
            *) printf '\nOpción inválida.\n' ;;
        esac
    done
}

# ---- lib/report.sh ----

# @brief Regenera el HTML desde cero (cabecera + una fila por registro).
# @note El HTML es derivado: siempre se puede borrar y regenerar.
generate_report() {
    local -A cache
    local id resto nombre precio
    load_table productos cache

    mkdir -p "$(dirname "$PRODUCTS_HTML")"
    {
        printf '<!DOCTYPE html>\n<html lang="es">\n<head><meta charset="utf-8">\n'
        printf '<title>Productos</title>\n</head>\n<body>\n'
        printf '<h1>Productos</h1>\n'
        printf '<table border="1">\n<tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>\n'
    } > "$PRODUCTS_HTML"
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"
        printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$id" "$nombre" "$precio" >> "$PRODUCTS_HTML"
    done
    printf '</table>\n</body>\n</html>\n' >> "$PRODUCTS_HTML"
    printf 'Reporte generado en %s.\n' "$PRODUCTS_HTML"
}

# ---- lib/ui.sh ----
# No toca disco directo; delega en casos de uso.

show_welcome() {
    printf "Bienvenido al Sistema de Gestion de Inventario\n\n"
}

product_menu() {
    local opt=""
    local id nombre precio

    while [[ "$opt" != "$OPT_EXIT" ]]; do
        printf '\nACCIONES:\n'
        printf '1. Alta producto\n'
        printf '2. Baja producto\n'
        printf '3. Mostrar inventario\n'
        printf '4. Editar producto\n'
        printf '5. Generar reporte HTML\n'
        printf '6. Salir\n'
        read -rp "Opción: " opt || return 0

        case "$opt" in
            "$OPT_ADD")
                read -rp "Ingrese ID: " id || return 0
                read -rp "Ingrese Nombre: " nombre || return 0
                read -rp "Ingrese Precio: " precio || return 0
                add_product "$id" "$nombre" "$precio" || true
                ;;
            "$OPT_REMOVE")
                read -rp "Ingrese ID a eliminar: " id || return 0
                remove_product "$id" || true
                ;;
            "$OPT_LIST")
                list_products
                ;;
            "$OPT_UPDATE")
                read -rp "Ingrese ID a editar: " id || return 0
                read -rp "Ingrese nuevo Nombre: " nombre || return 0
                read -rp "Ingrese nuevo Precio: " precio || return 0
                update_product "$id" "$nombre" "$precio" || true
                ;;
            "$OPT_REPORT")
                generate_report
                ;;
            "$OPT_EXIT")
                printf '\nSaliendo del programa...\n'
                ;;
            *)
                printf '\nOpción inválida.\n'
                ;;
        esac
    done
}

main() {
    init_db
    show_welcome

    if ! auth_menu; then
        printf '\nSaliendo del programa...\n'
        return 0
    fi
    product_menu
}

main "$@"
