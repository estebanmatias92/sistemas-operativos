# lib/crypto.sh — hashing, nunca texto plano en disco.
# Guarda/pragma (puro, sin dependencias).

[[ -n "${_CRYPTO_LOADED:-}" ]] && return 0
declare -g _CRYPTO_LOADED=1

# @brief SHA-256 de una contraseña (hex 64).
# @param $1 contraseña en claro (solo vive en memoria).
hash_password() {
    local pass="$1"
    printf '%s' "$pass" | sha256sum | cut -d' ' -f1
}
