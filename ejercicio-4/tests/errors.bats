# tests/errors.bats — ejecuta: make test
# Todo error de ejecución queda en error.log
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
  source "$BATS_TEST_DIRNAME/../lib/model/db.sh"
  source "$BATS_TEST_DIRNAME/../lib/model/products_store.sh"
  source "$BATS_TEST_DIRNAME/../lib/model/users_store.sh"
  source "$BATS_TEST_DIRNAME/../lib/api/products_api.sh"
  source "$BATS_TEST_DIRNAME/../lib/api/auth_api.sh"
  "$BATS_TEST_DIRNAME/../scripts/deploy.sh" --no-seed >/dev/null
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "precio inválido: no escribe y deja rastro en error.log" {
  run add_product "Yerba" "mal-precio" "1" "u1"
  [ "$status" -ne 0 ]
  grep -q 'datos de producto inválidos' "$ERRLOG"
  grep -q 'nombre="Yerba"' "$ERRLOG"
  grep -q 'precio="mal-precio"' "$ERRLOG"
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 0 ]
}

@test "baja de inexistente: deja rastro en error.log" {
  run remove_product "999" "1" "u1"
  [ "$status" -ne 0 ]
  grep -q 'no existe' "$ERRLOG"
  grep -q '"999"' "$ERRLOG"
}

@test "edición de inexistente: deja rastro en error.log" {
  run update_product "999" "Yerba" "10" "1" "u1"
  [ "$status" -ne 0 ]
  grep -q 'no existe' "$ERRLOG"
  grep -q '"999"' "$ERRLOG"
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
  run model_product_list
  [ "$status" -ne 0 ]
  [ -s "$ERRLOG" ]
}
