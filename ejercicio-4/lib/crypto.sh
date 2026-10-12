# lib/crypto.sh — hashing, nunca texto plano en disco.

# @brief SHA-256 de una contraseña (hex 64).
# @param $1 contraseña en claro (solo vive en memoria).
hash_password() {
    local pass="$1"
    printf '%s' "$pass" | sha256sum | cut -d' ' -f1
}
