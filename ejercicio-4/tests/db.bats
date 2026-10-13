# tests/db.bats — ejecuta: make test
# Cubre lib/model/* (SQLite, id AUTOINCREMENT) + lib/api/* contra DB temporal
# creada por scripts/deploy.sh (nunca var/db real).

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
  source "$BATS_TEST_DIRNAME/../lib/api/report_api.sh"
  "$BATS_TEST_DIRNAME/../scripts/deploy.sh" --no-seed >/dev/null
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "deploy crea tablas usuarios+productos y valid_table filtra" {
  run valid_table "productos"
  [ "$status" -eq 0 ]
  run valid_table "inventada"
  [ "$status" -ne 0 ]
  tables="$(sqlite3 "$DB" ".tables")"
  [[ "$tables" == *"productos"* ]]
  [[ "$tables" == *"usuarios"* ]]
}

@test "deploy es idempotente (puede correrse dos veces)" {
  run "$BATS_TEST_DIRNAME/../scripts/deploy.sh" --no-seed
  [ "$status" -eq 0 ]
  run "$BATS_TEST_DIRNAME/../scripts/deploy.sh" --no-seed
  [ "$status" -eq 0 ]
}

@test "require_db pasa con DB desplegada y falla amable sin ella" {
  run require_db
  [ "$status" -eq 0 ]
  DB="$TMPDIR_TEST/falta.sq3"
  run require_db
  [ "$status" -ne 0 ]
  [[ "$output" == *"make init"* ]]
}

@test "add_product guarda con id autogenerado (sin pedir id manual)" {
  run add_product "Yerba Mate" "120.50" "1" "u1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Producto 1 guardado."* ]]
  run model_product_exists "1"
  [ "$status" -eq 0 ]
}

@test "altas sucesivas generan ids distintos y crecientes" {
  add_product "Yerba" "10" "1" "u1" >/dev/null
  run add_product "Balde" "20" "1" "u1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Producto 2 guardado."* ]]
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 2 ]
}

@test "add_product inválido no escribe" {
  run add_product "Yerba" "mal-precio" "1" "u1"
  [ "$status" -ne 0 ]
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 0 ]
}

@test "sql_escape: nombre con comilla simple no rompe ni inyecta" {
  run add_product "O'Brien" "5" "1" "u1"
  [ "$status" -eq 0 ]
  run model_product_exists "1"
  [ "$status" -eq 0 ]
  name="$(sqlite3 "$DB" "SELECT nombre FROM productos WHERE id=1;")"
  [ "$name" = "O'Brien" ]
}

@test "update quirúrgico preserva el id y deja mensajes" {
  add_product "Yerba" "10" "1" "u1" >/dev/null
  run update_product "1" "Yerba Mate" "20.50" "1" "u1"
  [ "$status" -eq 0 ]
  price="$(sqlite3 "$DB" "SELECT precio FROM productos WHERE id=1;")"
  [ "$price" = "20.50" ]
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 1 ]
  run remove_product "1" "1" "u1"
  [ "$status" -eq 0 ]
  run model_product_exists "1"
  [ "$status" -ne 0 ]
}

@test "update/baja de inexistente no escribe" {
  run update_product "999" "Yerba" "10" "1" "u1"
  [ "$status" -ne 0 ]
  run remove_product "999" "1" "u1"
  [ "$status" -ne 0 ]
  run remove_product "ZZ" "1" "u1"
  [ "$status" -ne 0 ]
}

@test "register/login con sha256 (nunca plano)" {
  run register_user "u1" "12345"
  [ "$status" -eq 0 ]
  stored="$(sqlite3 "$DB" "SELECT hash FROM usuarios WHERE username='u1';")"
  [ -n "$stored" ]
  [[ "$stored" != *"12345"* ]]
  run login_user "u1" "12345"
  [ "$status" -eq 0 ]
  run login_user "u1" "otra"
  [ "$status" -ne 0 ]
}

@test "seed.sql carga datos ejemplo (idempotente)" {
  sqlite3 "$DB" < "$BATS_TEST_DIRNAME/../sql/seed.sql"
  sqlite3 "$DB" < "$BATS_TEST_DIRNAME/../sql/seed.sql"
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -ge 2 ]
}
