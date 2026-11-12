# lib/web/session.sh — sesiones fork-safe en archivo (socat no comparte memoria).
# Formato TSV: token<TAB>uid<TAB>username<TAB>expires_at (epoch).
# Concurrencia: flock compartido para validar y exclusivo para crear/revocar/limpiar.
# Seguridad: tokens y contraseñas NUNCA se loguean; var/session va en .gitignore.

[[ -n "${_WEB_SESSION_LOADED:-}" ]] && return 0
declare -g _WEB_SESSION_LOADED=1

if [[ -z "${SESSIONS_FILE:-}" ]]; then
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/lib/config.sh" 2>/dev/null \
        || source "lib/config.sh" 2>/dev/null || true
fi

# Resultado de session_validate (se copia a RPC_SESSION_* en el layer RPC).
declare -g SESSION_VALID_UID=""
declare -g SESSION_VALID_USER=""
declare -g SESSION_VALID_EXPIRES=""

# @brief Asegura directorio y archivo de sesiones con permisos privados.
session_ensure_file() {
    mkdir -p "$SESSION_DIR" || return 1
    chmod 700 "$SESSION_DIR" 2>/dev/null || true
    (umask 077 && : >>"$SESSIONS_FILE") || return 1
    chmod 600 "$SESSIONS_FILE" 2>/dev/null || true
}

# @brief Reescribe el archivo sin sesiones vencidas (llamado con lock exclusivo).
# @param $1 epoch actual.
_session_cleanup_locked() {
    local now="$1"
    local tmp
    tmp="$(mktemp "$SESSION_DIR/.sessions.XXXXXX")" || return 0
    if awk -F'\t' -v now="$now" 'NF >= 4 && $4 ~ /^[0-9]+$/ && $4 > now' "$SESSIONS_FILE" >"$tmp"; then
        mv -- "$tmp" "$SESSIONS_FILE"
    else
        rm -f -- "$tmp"
    fi
}

# @brief Crea una sesión y devuelve token + vencimiento por stdout.
# @param $1 uid, $2 username.
# @stdout "token<TAB>expires_at".
# @return 0 creada / 1 error de IO.
session_create() {
    local uid="$1"
    local user="$2"
    local now expires token

    session_ensure_file || return 1
    now="$(date +%s)"
    expires=$((now + SESSION_TTL))
    token="$(head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1)"
    [[ -n "$token" ]] || return 1

    (
        flock -x 9 || exit 1
        _session_cleanup_locked "$now"
        printf '%s\t%s\t%s\t%s\n' "$token" "$uid" "$user" "$expires" >>"$SESSIONS_FILE"
    ) 9>"$SESSION_LOCK" || return 1

    printf '%s\t%s\n' "$token" "$expires"
}

# @brief Valida un token vigente y deja uid/username/expiración en SESSION_VALID_*.
# @param $1 token (sha256 hex de 64).
# @return 0 vigente / 1 inválido o vencido.
session_validate() {
    local token="$1"
    local now row

    SESSION_VALID_UID=""
    SESSION_VALID_USER=""
    SESSION_VALID_EXPIRES=""
    [[ "$token" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ -f "$SESSIONS_FILE" ]] || return 1

    now="$(date +%s)"
    row="$(
        {
            flock -s 9 || exit 1
            awk -F'\t' -v tok="$token" -v now="$now" \
                'NF >= 4 && $1 == tok && $4 ~ /^[0-9]+$/ && $4 > now { print $2 "\t" $3 "\t" $4; exit }' \
                "$SESSIONS_FILE"
        } 9>"$SESSION_LOCK" 2>/dev/null
    )" || row=""

    [[ -n "$row" ]] || return 1
    IFS=$'\t' read -r SESSION_VALID_UID SESSION_VALID_USER SESSION_VALID_EXPIRES <<<"$row"
    return 0
}

# @brief Revoca un token (archivo temporal + mv, nunca sed -i).
# @param $1 token.
# @return 0 revocado o ya inexistente / 1 error.
session_revoke() {
    local token="$1"
    local tmp

    [[ "$token" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ -f "$SESSIONS_FILE" ]] || return 0

    (
        flock -x 9 || exit 1
        tmp="$(mktemp "$SESSION_DIR/.sessions.XXXXXX")" || exit 1
        if awk -F'\t' -v tok="$token" '$1 != tok' "$SESSIONS_FILE" >"$tmp"; then
            mv -- "$tmp" "$SESSIONS_FILE"
        else
            rm -f -- "$tmp"
            exit 1
        fi
    ) 9>"$SESSION_LOCK"
}

# @brief Borra sesiones vencidas (idempotente).
session_cleanup() {
    local now

    [[ -f "$SESSIONS_FILE" ]] || return 0
    now="$(date +%s)"
    (
        flock -x 9 || exit 1
        _session_cleanup_locked "$now"
    ) 9>"$SESSION_LOCK"
}
