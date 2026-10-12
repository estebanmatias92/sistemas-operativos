# lib/validators.sh — booleanos puros, sin disco ni SQL.
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
