#!/usr/bin/env bash
set -euo pipefail

# SCHEMA (contrato cátedra, no cambiar):
# productos: id<TAB>nombre<TAB>precio  (id: sin tab/vacío; nombre: con espacios sí, sin tab; precio: ^[0-9]+(\.[0-9]{1,2})?$)
# usuarios:  username<TAB>sha256       (username: sin espacios/tab; hash: hex 64)
#
# Flujo: leer -> validar (booleano, no escribe) -> guardar (no valida).
# Fuente de verdad = disco; arrays solo como caché temporal por operación.
#
# TIPOS (estructuras que circulan por el programa):
#   tsv_row : línea "col1\tcol2[\tcol3]" en disco (db/*.tsv). Ej:
#               db/productos.tsv:  A1\tYerba Mate\t120.50
#               db/usuarios.tsv :  u1\t7e6e0c30...4b6e
#   cache   : array asociativo bash (declare -A). Foto temporal de una tabla:
#             clave = col 1 (ID único), valor = resto opaco con su TAB.
#             Ej (salida de `declare -p cache`):
#               cache=(
#                 [A1]="Yerba Mate\t120.50"
#                 [A2]="Coca Cola\t10.50"
#               )
#             Nunca global persistente: se crea, se usa y se descarta por operación.
declare -r DB_DIR="db"
declare -r PRODUCTS_HTML="productos.html"
declare -r RE_PRECIO='^[0-9]+(\.[0-9]{1,2})?$'
declare -r RE_USER='^[A-Za-z0-9_.-]+$'

declare -r -i OPT_ADD=1
declare -r -i OPT_REMOVE=2
declare -r -i OPT_LIST=3
declare -r -i OPT_UPDATE=4
declare -r -i OPT_REPORT=5
declare -r -i OPT_EXIT=6

# @brief Resuelve nombre lógico -> ruta física ("productos" -> "db/productos.tsv").
# @param $1 nombre de tabla.
table() {
    local name="$1"
    printf '%s/%s.tsv' "$DB_DIR" "$name"
}

# @brief Lista blanca de tablas: un input nunca se convierte en ruta arbitraria.
# @param $1 nombre de tabla.
# @return 0 conocida / 1 desconocida.
valid_table() {
    case "$1" in
        productos|usuarios) return 0 ;;
        *) return 1 ;;
    esac
}

init_db() {
    [[ -d "$DB_DIR" ]] || mkdir -p "$DB_DIR"
    [[ -f "$(table productos)" ]] || touch "$(table productos)"
    [[ -f "$(table usuarios)" ]] || touch "$(table usuarios)"
}

# @brief ¿Existe esta clave en esta tabla? Evita cargar el archivo a memoria.
# @param $1 tabla, $2 clave (col 1).
# @return 0 existe / 1 no existe o tabla inválida.
record_exists() {
    local tbl="$1"
    local key="$2"
    valid_table "$tbl" || return 1
    grep -q -P "^${key}\t" "$(table "$tbl")"  # -q: silencioso; ^...TAB ancla a col 1 exacta
}

append_record() {
    local tbl="$1"
    local line="$2"
    valid_table "$tbl" || return 1
    printf '%s\n' "$line" >> "$(table "$tbl")"
}

# @brief Reescribe la tabla sin la clave pedida vía tmp+mv (atómico).
# @param $1 tabla, $2 clave.
# @note Nunca ">" directo al .tsv: si el proceso se corta, la original sigue intacta.
delete_record() {
    local tbl="$1"
    local key="$2"
    local f tmp
    valid_table "$tbl" || return 1
    f="$(table "$tbl")"
    tmp="${f}.tmp"
    grep -v -P "^${key}\t" "$f" > "$tmp" || [[ $? -eq 1 ]]  # exit 1 = no quedó ninguna línea, no es error
    mv "$tmp" "$f"
}

# @brief Foto de la tabla en el cache del llamador (ver TIPOS).
# @param $1 tabla.
# @param $2 cache por nombre (se vacía y se llena).
# @return 0 ok / 1 tabla inválida.
load_table() {
    local tbl="$1"
    local -n ref="$2"  # -n: alias al array del llamador, no copia
    local k resto

    valid_table "$tbl" || return 1
    ref=()  # vacía el array antes de llenarlo

    while IFS=$'\t' read -r k resto; do  # IFS temporal solo para este read; -r no interpreta "\"
        [[ -z "$k" ]] && continue  # salta líneas vacías
        ref["$k"]="$resto"
    done < "$(table "$tbl")"  # el archivo alimenta el loop por stdin
}

# @brief Vuelca un cache modificado a su tabla (tmp+mv).
# @param $1 tabla.
# @param $2 cache por nombre.
# @note Solo tras escritura; las lecturas descartan el cache.
save_table() {
    local tbl="$1"
    local -n ref="$2"
    local k
    local f tmp

    valid_table "$tbl" || return 1
    f="$(table "$tbl")"; tmp="${f}.tmp"
    : > "$tmp"  # trunca/crea el temporal

    for k in "${!ref[@]}"; do  # itera las claves del asociativo
        printf '%s\t%s\n' "$k" "${ref[$k]}" >> "$tmp"
    done

    mv "$tmp" "$f"
}

# @brief SHA-256 de una contraseña (hex 64). El módulo de usuarios jamás
# usa texto plano.
# @param $1 contraseña en claro (solo vive en memoria).
hash_password() {
    local pass="$1"
    printf '%s' "$pass" | sha256sum | cut -d' ' -f1  # cut quita el "  -" que agrega sha256sum
}

# Validadores de formato por campo (booleanos puros, sin disco).
# Las regex van en variable SIN comillas: con comillas no matchean.
is_valid_id() {
    local id="$1"
    [[ -n "$id" && "$id" != *$'\t'* ]]  # no vacío y sin tabs (glob con TAB ANSI-C $'...')
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

    if (( ${#cache[@]} == 0 )); then  # ${#...[@]} = cantidad de claves
        printf '\nLISTADO: (vacío)\n'
        return 0
    fi
    printf '\nLISTADO:\n'
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"  # herestring: re-parte el valor en campos
        printf 'ID %s : %s - $%s\n' "$id" "$nombre" "$precio"  # %s tal cual: %.2f depende del locale (coma vs punto)
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
    if [[ -z "${cache[$id]+x}" ]]; then  # +x: ¿existe la clave aunque valga vacío?
        printf 'El producto no existe.\n'
        return 1
    fi
    cache["$id"]="$(printf '%s\t%s' "$nombre" "$precio")"
    save_table productos cache
    printf 'Producto %s actualizado.\n' "$id"
}

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
    local want got
    local f

    f="$(table usuarios)"
    if ! record_exists usuarios "$user"; then
        return 1
    fi
    want="$(grep -P "^${user}\t" "$f" | cut -f2)"  # col 2 = hash guardado
    got="$(hash_password "$pass")"
    [[ "$got" == "$want" ]]
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
        read -rp "Usuario: " user || return 2  # 2=EOF: salir limpio (set -e no actúa bajo un if)
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
                auth_interactive; s=$?  # s captura el código (set -e no rige acá)
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

# @brief Regenera productos.html desde cero (cabecera + una fila por registro).
# @note El HTML es derivado: siempre se puede borrar y regenerar desde el TSV.
generate_report() {
    local -A cache
    local id resto nombre precio
    load_table productos cache

    {
        printf '<!DOCTYPE html>\n<html lang="es">\n<head><meta charset="utf-8">\n'
        printf '<title>Productos</title>\n</head>\n<body>\n'
        printf '<h1>Productos</h1>\n'
        printf '<table border="1">\n<tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>\n'
    } > "$PRODUCTS_HTML"  # el bloque entero se redirige al archivo nuevo
    for id in "${!cache[@]}"; do
        resto="${cache[$id]}"
        IFS=$'\t' read -r nombre precio <<< "$resto"
        printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$id" "$nombre" "$precio" >> "$PRODUCTS_HTML"
    done
    printf '</table>\n</body>\n</html>\n' >> "$PRODUCTS_HTML"
    printf 'Reporte generado en %s.\n' "$PRODUCTS_HTML"
}

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
                add_product "$id" "$nombre" "$precio" || true  # el fallo de validación no aborta el menú (set -e)
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

main
