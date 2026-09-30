# Makefile — tooling de la app. `make help` lista comandos.
# Convención: todo target con ## aparece en help.
SHELL := /usr/bin/env bash

.PHONY: help build test check fmt run run-dist init schema-check seed clean clean-all

help: ## Muestra comandos disponibles
	@grep -E '^[a-z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Genera ejercicio-3.sh (entregable) desde lib/*.sh
	@{ \
	  printf '#!/usr/bin/env bash\n'; \
	  printf 'set -euo pipefail\n'; \
	  printf '# GENERADO por `make build` desde lib/*.sh — no editar a mano.\n'; \
	  printf '# Fuente de verdad: lib/. Entregable Classroom: ./ejercicio-3.sh\n'; \
	  for f in lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh lib/db.sh lib/products.sh lib/auth.sh lib/report.sh lib/ui.sh; do \
	    printf '\n# ---- %s ----\n' "$$f"; \
	    grep -v '^# lib/' "$$f" || true; \
	  done; \
	  printf '\nmain "$$@"\n'; \
	} > ejercicio-3.sh
	@chmod +x ejercicio-3.sh bin/app
	@bash -n ejercicio-3.sh && echo "build OK: ejercicio-3.sh"

test: ## Corre suite bats (tests/*.bats)
	bats tests/

check: ## bash -n (gate) + shfmt (informativo, estilo lab con 4 espacios)
	bash -n bin/app
	for f in lib/*.sh; do bash -n "$$f" || exit 1; done
	bash -n ejercicio-3.sh
	shfmt -d -i 4 -ci bin/app lib/*.sh || echo "(aviso) shfmt sugiere formato; el estilo del lab usa '>> \"$$f\"' con espacio, se mantiene a propósito"
	@echo "check OK"

fmt: ## Formatea bin + lib con shfmt (4 espacios, como el lab)
	shfmt -w -i 4 -ci bin/app lib/*.sh

run: ## Corre app modular (bin/app + lib)
	./bin/app

run-dist: build ## Corre entregable (./ejercicio-3.sh generado)
	./ejercicio-3.sh

init: ## Crea var/ + data.sq3 (schema) + seed ejemplo
	mkdir -p var/db var/log var/report
	sqlite3 var/db/data.sq3 < sql/schema.sql
	sqlite3 var/db/data.sq3 < sql/seed.sql
	: > var/log/system.log
	: > var/log/error.log
	@echo "init OK: var/db/data.sq3"
	sqlite3 var/db/data.sq3 ".tables"

schema-check: ## Contrasta .schema contra sql/schema.sql
	sqlite3 var/db/data.sq3 ".schema"

seed: ## Re-siembra data.sq3 desde sql/seed.sql (idempotente)
	sqlite3 var/db/data.sq3 < sql/seed.sql

clean: ## Borra logs y reporte generado (mantiene DB)
	rm -f var/log/system.log var/log/error.log var/report/productos.html

clean-all: clean ## Borra también var/db/data.sq3 (reconstruible con make init)
	rm -f var/db/data.sq3
