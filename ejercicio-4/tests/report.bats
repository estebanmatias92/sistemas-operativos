# tests/report.bats — ejecuta: make test
# Cubre lib/api/report_api.sh: HTML derivado con tabla ID/Nombre/Precio desde SQLite.

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  export DB="$TMPDIR_TEST/test.sq3"
  export LOG="$TMPDIR_TEST/system.log"
  export ERRLOG="$TMPDIR_TEST/error.log"
  export PRODUCTS_HTML="$TMPDIR_TEST/productos.html"
  source "$BATS_TEST_DIRNAME/../lib/config.sh"
  source "$BATS_TEST_DIRNAME/../lib/validators.sh"
  source "$BATS_TEST_DIRNAME/../lib/crypto.sh"
  source "$BATS_TEST_DIRNAME/../lib/logging.sh"
  source "$BATS_TEST_DIRNAME/../lib/model/db.sh"
  source "$BATS_TEST_DIRNAME/../lib/model/products_store.sh"
  source "$BATS_TEST_DIRNAME/../lib/model/users_store.sh"
  source "$BATS_TEST_DIRNAME/../lib/api/products_api.sh"
  source "$BATS_TEST_DIRNAME/../lib/api/report_api.sh"
  "$BATS_TEST_DIRNAME/../scripts/deploy.sh" --no-seed >/dev/null
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "generate_report crea HTML con cabecera y fila (id autogenerado)" {
  add_product "escoba" "3000" "1" "u1" >/dev/null
  run generate_report "1" "u1"
  [ "$status" -eq 0 ]
  grep -q "<title>Productos</title>" "$PRODUCTS_HTML"
  grep -q "<th>ID</th><th>Nombre</th><th>Precio</th>" "$PRODUCTS_HTML"
  grep -q "<td>1</td><td>escoba</td><td>3000</td>" "$PRODUCTS_HTML"
}
