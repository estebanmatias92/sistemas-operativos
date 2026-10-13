#!/usr/bin/env bash
set -euo pipefail
# ejercicio-4.sh — STUB de entrega (no editar lógica aquí).
# Delega en bin/app; la fuente de verdad es lib/ en capas
# (config -> validators -> crypto -> logging -> model -> api -> ui).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bin/app" "$@"
