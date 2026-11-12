#!/usr/bin/env bash
set -euo pipefail
# scripts/deploy.sh — ÚNICO dueño de la creación/inicialización de la DB (deploy manual).
# Uso: ./scripts/deploy.sh [--seed|--no-seed|--check]
#   --seed    (default): crea schema + siembra ejemplo (idempotente).
#   --no-seed: crea schema sin sembrar (para tests).
#   --check:   verifica que la DB existe y tiene ambas tablas (fail-fast de la app).
# La app (lib/model, lib/ui) NUNCA crea la DB: llama a require_db y falla amable si falta.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_ROOT"

# shellcheck disable=SC1091
source "$APP_ROOT/lib/config.sh"

mode="--seed"
if (( $# > 0 )); then
    case "${1:-}" in
        --seed|--no-seed|--check) mode="$1" ;;
        --help|-h)
            printf 'Uso: %s [--seed|--no-seed|--check]\n' "${0##*/}"
            exit 0 ;;
        *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 1 ;;
    esac
fi

if [[ "$mode" == "--check" ]]; then
    [[ -f "$DB" ]] || { printf 'Error: falta %s; corra `make init`.\n' "$DB" >&2; exit 1; }
    tables="$(sqlite3 "$DB" ".tables")"
    [[ "$tables" == *"productos"* && "$tables" == *"usuarios"* ]] \
        || { printf 'Error: schema incompleto en %s; corra `make init`.\n' "$DB" >&2; exit 1; }
    printf 'deploy check OK: %s (%s)\n' "$DB" "$tables"
    exit 0
fi

mkdir -p "$(dirname "$DB")" "$(dirname "$LOG")" "$(dirname "$ERRLOG")" "$(dirname "$PRODUCTS_HTML")"
sqlite3 "$DB" < "$APP_ROOT/sql/schema.sql"
if [[ "$mode" == "--seed" ]]; then
    sqlite3 "$DB" < "$APP_ROOT/sql/seed.sql"
fi
[[ -f "$LOG" ]] || : > "$LOG"
[[ -f "$ERRLOG" ]] || : > "$ERRLOG"
printf 'deploy OK: %s\n' "$DB"
sqlite3 "$DB" ".tables"
