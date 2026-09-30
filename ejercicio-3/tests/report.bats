# tests/report.bats — ejecuta: make test
# Cubre lib/report.sh: HTML derivado con tabla ID/Nombre/Precio desde SQLite.

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
  source "$BATS_TEST_DIRNAME/../lib/db.sh"
  source "$BATS_TEST_DIRNAME/../lib/products.sh"
  source "$BATS_TEST_DIRNAME/../lib/report.sh"
  init_db
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "generate_report crea HTML con cabecera y fila" {
  add_product "1" "escoba" "3000" >/dev/null
  run generate_report
  [ "$status" -eq 0 ]
  grep -q "<title>Productos</title>" "$PRODUCTS_HTML"
  grep -q "<th>ID</th><th>Nombre</th><th>Precio</th>" "$PRODUCTS_HTML"
  grep -q "<td>1</td><td>escoba</td><td>3000</td>" "$PRODUCTS_HTML"
}
