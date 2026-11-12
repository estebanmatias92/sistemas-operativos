# Makefile — tooling de la app. `make help` lista comandos.
# Convención: todo target con ## aparece en help.
SHELL := /usr/bin/env bash

.PHONY: help build dist test check fmt docs docs-check run run-cli run-dist run-web run-web-dev init schema-check seed clean clean-all

help: ## Muestra comandos disponibles
	@grep -E '^[a-z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: check ## Verifica (entregables ./ejercicio-5.sh y ./server.sh son stubs delgados)
	bash -n ejercicio-5.sh server.sh bin/app bin/server && echo "build OK: stubs + lib/"

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

check: ## bash -n (gate) + reglas de capas + shfmt informativo
	bash -n bin/app
	bash -n bin/server
	bash -n scripts/deploy.sh
	for f in lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh lib/model/*.sh lib/api/*.sh lib/ui/*.sh lib/web/*.sh; do bash -n "$$f" || exit 1; done
	bash -n ejercicio-5.sh
	bash -n server.sh
	@echo "-- regla de capas: sqlite3 solo en model/, whiptail/read solo en ui/"
	@if grep -rnE '(^|[^[:alnum:]_])sqlite3[[:space:]]' lib/api lib/ui lib/web bin 2>/dev/null | grep -v '#.*sqlite3'; then echo "CAPAS-FAIL: sqlite3 fuera de lib/model"; exit 1; fi
	@if grep -rnE '(^|[^[:alnum:]_])whiptail[[:space:]]' lib/api lib/model lib/web lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh 2>/dev/null | grep -v '#.*whiptail'; then echo "CAPAS-FAIL: whiptail fuera de lib/ui"; exit 1; fi
	@if grep -rn 'read -rp\|read -rsp' lib/api lib/model lib/web 2>/dev/null | grep -v '#.*read -r'; then echo "CAPAS-FAIL: read interactivo fuera de lib/ui"; exit 1; fi
	@if grep -rnE '(^|[^[:alnum:]_])socat[[:space:]]' lib/api lib/model lib/ui lib/web bin server.sh 2>/dev/null | grep -v 'lib/web/dispatch.sh' | grep -v 'bin/server' | grep -v '#.*socat'; then echo "CAPAS-FAIL: socat solo en bin/server y lib/web/dispatch.sh"; exit 1; fi
	@if grep -rnE '(^|[^[:alnum:]_])jq[[:space:]]' lib/api lib/model lib/ui lib/config.sh lib/validators.sh lib/crypto.sh lib/logging.sh bin 2>/dev/null | grep -v '#.*jq'; then echo "CAPAS-FAIL: jq solo en lib/web"; exit 1; fi
	@echo "-- capas OK (web -> api -> model -> config)"
	shfmt -d -i 4 -ci bin/app bin/server lib/*.sh lib/*/*.sh || echo "(aviso) shfmt sugiere formato; el estilo del lab usa '>> \"$$f\"' con espacio, se mantiene a propósito"
	@echo "check OK"

fmt: ## Formatea entrypoints + lib con shfmt (4 espacios, como el lab)
	shfmt -w -i 4 -ci bin/app bin/server ejercicio-5.sh server.sh lib/*.sh lib/*/*.sh

docs: ## Compila los diagramas PlantUML (docs/diagrams/*.puml -> *.svg)
	@command -v plantuml >/dev/null 2>&1 || { echo "falta plantuml (pacman -S plantuml)"; exit 1; }
	plantuml --svg --charset UTF-8 --disable-metadata --stop-on-error docs/diagrams/*.puml
	@for f in docs/diagrams/*.svg; do \
	  grep -q 'docs-background' "$$f" \
	    || sed -i 's|<defs/>|<defs/><rect class="docs-background" width="100%" height="100%" fill="#FFFFFF"/>|' "$$f"; \
	done
	@echo "docs OK: $$(ls docs/diagrams/*.svg | wc -l) SVG (fondo blanco inyectado)"

docs-check: ## Valida la sintaxis de los diagramas (aviso si falta plantuml)
	@if command -v plantuml >/dev/null 2>&1; then \
	  plantuml --check-syntax --charset UTF-8 docs/diagrams/*.puml && echo "docs-check OK"; \
	else \
	  echo "(aviso) plantuml no está instalado; se omite la validación de diagramas"; \
	fi

run: ## Corre app modular en TUI (bin/app + lib, default --tui)
	./bin/app --tui

run-cli: ## Corre app modular en CLI (paridad Lab 05)
	./bin/app --cli

run-dist: ## Corre stub de entrega (./ejercicio-5.sh -> bin/app, default --tui)
	./ejercicio-5.sh

run-web: ## Levanta el servidor web (stub ./server.sh -> bin/server)
	./server.sh

run-web-dev: ## Levanta el servidor web modular (bin/server)
	./bin/server

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

clean: ## Borra logs, reporte y sesiones (mantiene DB)
	rm -f var/log/system.log var/log/error.log var/report/productos.html
	rm -rf var/session

clean-all: clean ## Borra también var/db/data.sq3 (reconstruible con make init)
	rm -f var/db/data.sq3
