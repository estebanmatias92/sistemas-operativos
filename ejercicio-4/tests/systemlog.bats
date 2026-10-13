# tests/systemlog.bats — ejecuta: make test
# Cada operación exitosa deja una línea en system.log
# (TSV: fecha/hora<TAB>id<TAB>usuario<TAB>acción). Los fallos no
# escriben acá (quedan en error.log, ver tests/errors.bats).

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
  register_user "u1" "12345" >/dev/null
  UID_U1="$(sqlite3 "$DB" "SELECT id FROM usuarios WHERE username='u1';")"
  : > "$LOG"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "alta exitosa: una línea TSV con fecha, uid, usuario y acción (id autogenerado)" {
  run add_product "Yerba" "10" "$UID_U1" "u1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Producto 1 guardado."* ]]
  [ "$(wc -l < "$LOG")" -eq 1 ]
  grep -Eq $'^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\t' "$LOG"
  grep -q "$(printf '\t%s\t%s\talta id="1"' "$UID_U1" "u1")" "$LOG"
}

@test "baja y edición exitosas: auditan con el id entrecomillado" {
  add_product "Yerba" "10" "$UID_U1" "u1" >/dev/null
  : > "$LOG"
  run update_product "1" "Yerba Mate" "20.50" "$UID_U1" "u1"
  [ "$status" -eq 0 ]
  grep -q "$(printf '\t%s\t%s\tedición id="1"' "$UID_U1" "u1")" "$LOG"
  : > "$LOG"
  run remove_product "1" "$UID_U1" "u1"
  [ "$status" -eq 0 ]
  grep -q "$(printf '\t%s\t%s\tbaja id="1"' "$UID_U1" "u1")" "$LOG"
}

@test "listado y reporte exitosos: auditan sin id de producto" {
  run list_products "$UID_U1" "u1"
  [ "$status" -eq 0 ]
  grep -q "$(printf '\t%s\t%s\tlistado' "$UID_U1" "u1")" "$LOG"
  : > "$LOG"
  run generate_report "$UID_U1" "u1"
  [ "$status" -eq 0 ]
  grep -q "$(printf '\t%s\t%s\treporte' "$UID_U1" "u1")" "$LOG"
}

@test "registro y login exitosos: auditan con username entrecomillado" {
  run register_user "u2" "abcde"
  [ "$status" -eq 0 ]
  grep -q 'registro username="u2"' "$LOG"
  ! grep -q '"12345"' "$LOG"
  ! grep -q '"abcde"' "$LOG"
  : > "$LOG"
  run login_user "u2" "abcde"
  [ "$status" -eq 0 ]
  grep -q 'login username="u2"' "$LOG"
}

@test "fallos no escriben en system.log (inválido, inexistente, login mal)" {
  add_product "Yerba" "10" "$UID_U1" "u1" >/dev/null
  : > "$LOG"
  run add_product "Yerba" "mal-precio" "$UID_U1" "u1"
  [ "$status" -ne 0 ]
  run remove_product "999" "$UID_U1" "u1"
  [ "$status" -ne 0 ]
  run login_user "u1" "clave-mal"
  [ "$status" -ne 0 ]
  [ ! -s "$LOG" ]
}
