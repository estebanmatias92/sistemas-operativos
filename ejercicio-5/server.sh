#!/usr/bin/env bash
set -euo pipefail
# server.sh — STUB de entrega de la interfaz web (no editar lógica aquí).
# Delega en bin/server; la fuente de verdad es lib/ en capas
# (config -> validators -> crypto -> logging -> model -> api -> web).
# La app CLI/TUI tiene su propio stub: ./ejercicio-5.sh -> bin/app.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bin/server" "$@"
