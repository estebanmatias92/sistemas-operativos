# lib/validators.sh — booleanos puros, sin disco ni SQL.
# Las regex van en variable SIN comillas: con comillas no matchean.
# Guarda/pragma + auto-source defensivo de config (modo modular standalone).

[[ -n "${_VALIDATORS_LOADED:-}" ]] && return 0
declare -g _VALIDATORS_LOADED=1

if [[ -z "${RE_PRECIO:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

is_valid_id() {
    local id="$1"
    [[ -n "$id" && "$id" != *$'\t'* ]]
}

# @brief Id de referencia autogenerado (baja/edición): entero positivo.
# @param $1 id a validar.
is_valid_ref_id() {
    local id="$1"
    [[ "$id" =~ $RE_REF_ID ]]
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

# @brief Regla "¿estos datos pueden guardarse?" (solo formato, sin id manual).
# @param $1 nombre, $2 precio.
# @return 0 válido / 1 inválido.
product_data_valid() {
    local nombre="$1"
    local precio="$2"
    is_valid_name "$nombre" && is_valid_price "$precio"
}

# @brief Compat Lab 04/05: product_valid con id explícito (deprecado).
# El id manual ya no existe (AUTOINCREMENT); solo valida formato igual que antes.
# @param $1 id (ignorado salvo no-vacío), $2 nombre, $3 precio.
product_valid() {
    local id="$1"
    local nombre="$2"
    local precio="$3"
    is_valid_id "$id" && product_data_valid "$nombre" "$precio"
}
