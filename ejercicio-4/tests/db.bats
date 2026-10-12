# tests/db.bats — ejecuta: make test
# Cubre lib/db.sh (SQLite) + products/auth contra DB temporal (nunca var/db real).

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
  source "$BATS_TEST_DIRNAME/../lib/report.sh"
  init_db
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "init_db crea tablas usuarios+productos y valid_table filtra" {
  run valid_table "productos"
  [ "$status" -eq 0 ]
  run valid_table "inventada"
  [ "$status" -ne 0 ]
  tables="$(sqlite3 "$DB" ".tables")"
  [[ "$tables" == *"productos"* ]]
  [[ "$tables" == *"usuarios"* ]]
}

@test "init_db es idempotente (puede correrse dos veces)" {
  run init_db
  [ "$status" -eq 0 ]
  run init_db
  [ "$status" -eq 0 ]
}

@test "add_product guarda y rechaza duplicado sin escribir" {
  run add_product "A1" "Yerba Mate" "120.50" "1" "u1"
  [ "$status" -eq 0 ]
  run record_exists productos "A1"
  [ "$status" -eq 0 ]
  run add_product "A1" "Otro" "10" "1" "u1"
  [ "$status" -ne 0 ]
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 1 ]
}

@test "add_product inválido no escribe" {
  run add_product "A1" "Yerba" "mal-precio" "1" "u1"
  [ "$status" -ne 0 ]
  count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM productos;")"
  [ "$count" -eq 0 ]
}

@test "sql_escape: nombre con comilla simple no rompe ni inyecta" {
  run add_product "B1" "O'Brien" "5" "1" "u1"
  [ "$status" -eq 0 ]
  run record_exists productos "B1"
  [ "$status" -eq 0 ]
  name="$(sqlite3 "$DB" "SELECT nombre FROM productos WHERE id='B1';")"
  [ "$name" = "O'Brien" ]
}

@test "update/remove usan load/save y dejan mensajes" {
  add_product "A1" "Yerba" "10" "1" "u1" >/dev/null
  run update_product "A1" "Yerba Mate" "20.50" "1" "u1"
  [ "$status" -eq 0 ]
  price="$(sqlite3 "$DB" "SELECT precio FROM productos WHERE id='A1';")"
  [ "$price" = "20.50" ]
  run remove_product "A1" "1" "u1"
  [ "$status" -eq 0 ]
  run record_exists productos "A1"
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
