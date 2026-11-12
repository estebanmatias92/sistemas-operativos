# Makefile — tooling de la app. `make help` lista comandos.
# Convención: todo target con ## aparece en help.
SHELL := /usr/bin/env bash

.PHONY: help build dist test check fmt run run-cli run-dist init schema-check seed clean clean-all

help: ## Muestra comandos disponibles
	@grep -E '^[a-z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: check ## Verifica (el entregable ./ejercicio-5.sh es stub delgado, sin compilado)
	bash -n ejercicio-5.sh bin/app && echo "build OK: stub + lib/"

dist: ## Genera bundle monolítico opcional en dist/ (solo emergencia single-file; gitignorado)
	@mkdir -p dist
	@{ \
	  printf '#!/usr/bin/env bash\n'; \
	  printf 'set -euo pipefail\n'; \
	  printf '# GENERADO por `make dist` desde lib/ — solo emergencia single-file (no es el entregable).\n'; \
	  printf '# Fuente de verdad: lib/ (config -> validators -> crypto -> logging -> model -> api -> ui).\n'; \
	  for f in lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh lib/model/db.sh lib/model/products_store.sh lib/model/users_store.sh lib/api/products_api.sh lib/api/auth_api.sh lib/api/report_api.sh lib/ui/cli.sh lib/ui/tui.sh lib/ui/dispatch.sh; do \
	    printf '\n# ---- %s ----\n' "$$f"; \
	    grep -v '^# lib/' "$$f" || true; \
	  done; \
	  printf '\nmain "$$@"\n'; \
	} > dist/ejercicio-5.sh
	@chmod +x dist/ejercicio-5.sh
	@bash -n dist/ejercicio-5.sh && echo "dist OK: dist/ejercicio-5.sh"

test: ## Corre suite bats (tests/*.bats)
	bats tests/

check: ## bash -n (gate) + regla de capas ui->api->model + shfmt informativo
	bash -n bin/app
	bash -n scripts/deploy.sh
	for f in lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh lib/model/*.sh lib/api/*.sh lib/ui/*.sh; do bash -n "$$f" || exit 1; done
	bash -n ejercicio-5.sh
	@echo "-- regla de capas: sqlite3 solo en model/, whiptail/read solo en ui/"
	@if grep -rn 'sqlite3' lib/api lib/ui bin 2>/dev/null | grep -v '#.*sqlite3'; then echo "CAPAS-FAIL: sqlite3 fuera de lib/model"; exit 1; fi
	@if grep -rn 'whiptail' lib/api lib/model lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh 2>/dev/null | grep -v '#.*whiptail'; then echo "CAPAS-FAIL: whiptail fuera de lib/ui"; exit 1; fi
	@if grep -rn 'read -rp\|read -rsp' lib/api lib/model 2>/dev/null | grep -v '#.*read -r'; then echo "CAPAS-FAIL: read interactivo fuera de lib/ui"; exit 1; fi
	@echo "-- capas OK (ui -> api -> model -> config)"
	shfmt -d -i 4 -ci bin/app lib/*.sh lib/*/*.sh || echo "(aviso) shfmt sugiere formato; el estilo del lab usa '>> \"$$f\"' con espacio, se mantiene a propósito"
	@echo "check OK"

fmt: ## Formatea bin + lib con shfmt (4 espacios, como el lab)
	shfmt -w -i 4 -ci bin/app ejercicio-5.sh lib/*.sh

run: ## Corre app modular en TUI (bin/app + lib, default --tui)
	./bin/app --tui

run-cli: ## Corre app modular en CLI (paridad Lab 05)
	./bin/app --cli

run-dist: ## Corre stub de entrega (./ejercicio-5.sh -> bin/app, default --tui)
	./ejercicio-5.sh

init: ## Crea var/ + data.sq3 (schema) + seed ejemplo (delega en scripts/deploy.sh)
	./scripts/deploy.sh --seed
	: > var/log/system.log
	: > var/log/error.log

schema-check: ## Contrasta .schema contra sql/schema.sql
	sqlite3 var/db/data.sq3 ".schema"

seed: ## Re-siembra data.sq3 desde sql/seed.sql (idempotente)
	sqlite3 var/db/data.sq3 < sql/seed.sql

deploy-check: ## Verifica DB desplegada (fail-fast de la app)
	./scripts/deploy.sh --check

clean: ## Borra logs y reporte generado (mantiene DB)
	rm -f var/log/system.log var/log/error.log var/report/productos.html

clean-all: clean ## Borra también var/db/data.sq3 (reconstruible con make init)
	rm -f var/db/data.sq3
