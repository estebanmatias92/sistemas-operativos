# tests/errors.bats — ejecuta: make test
# Cubre punto 6 de la consigna: todo error de ejecución queda en error.log
# (errores amables vía log_error + stderr de sqlite3 vía 2>>"$ERRLOG").

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
  source "$BATS_TEST_DIRNAME/../lib/auth.sh"
  init_db
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "alta duplicada: avisa en stderr y deja rastro en error.log" {
  add_product "A1" "Yerba" "10" "1" "u1" >/dev/null
  : > "$ERRLOG"
  run add_product "A1" "Otro" "10" "1" "u1"
  [ "$status" -ne 0 ]
  [[ "$output" == *'ya existe'* ]]
  grep -q 'ya existe' "$ERRLOG"
  grep -q '"A1"' "$ERRLOG"
  grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' "$ERRLOG"
}

@test "precio inválido: no escribe y deja rastro en error.log" {
  run add_product "A1" "Yerba" "mal-precio" "1" "u1"
  [ "$status" -ne 0 ]
  grep -q 'datos de producto inválidos' "$ERRLOG"
  grep -q 'id="A1"' "$ERRLOG"
  grep -q 'precio="mal-precio"' "$ERRLOG"
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 0 ]
}

@test "baja de inexistente: deja rastro en error.log" {
  run remove_product "ZZ" "1" "u1"
  [ "$status" -ne 0 ]
  grep -q 'no existe' "$ERRLOG"
  grep -q '"ZZ"' "$ERRLOG"
}

@test "registro duplicado: deja rastro en error.log" {
  register_user "u1" "12345" >/dev/null
  : > "$ERRLOG"
  run register_user "u1" "otra"
  [ "$status" -ne 0 ]
  grep -q 'ya existe' "$ERRLOG"
  grep -q '"u1"' "$ERRLOG"
}

@test "fallo SQL real (DB inválida): retorna 1 y deja rastro en error.log" {
  DB="$TMPDIR_TEST"
  run record_exists productos "A1"
  [ "$status" -ne 0 ]
  [ -s "$ERRLOG" ]
}
