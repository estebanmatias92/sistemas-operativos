#!/usr/bin/env bash
set -euo pipefail
# ejercicio-5.sh — STUB de entrega CLI/TUI (no editar lógica aquí).
# Delega en bin/app; la fuente de verdad es lib/ en capas
# (config -> validators -> crypto -> logging -> model -> api -> ui).
# La interfaz web tiene su propio stub: ./server.sh -> bin/server.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bin/app" "$@"
