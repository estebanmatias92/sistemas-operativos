# tests/validators.bats — ejecuta: make test  |  bats tests/
# Cubre lib/validators.sh (puro, sin disco).

setup() {
  source "$BATS_TEST_DIRNAME/../lib/config.sh"
  source "$BATS_TEST_DIRNAME/../lib/validators.sh"
}

@test "precio válido: entero y decimal 1-2 dígitos" {
  run is_valid_price "3000"
  [ "$status" -eq 0 ]
  run is_valid_price "120.50"
  [ "$status" -eq 0 ]
  run is_valid_price "10.5"
  [ "$status" -eq 0 ]
}

@test "precio inválido: vacío, letras, 3 decimales, negativo" {
  run is_valid_price ""
  [ "$status" -ne 0 ]
  run is_valid_price "abc"
  [ "$status" -ne 0 ]
  run is_valid_price "10.123"
  [ "$status" -ne 0 ]
  run is_valid_price "-5"
  [ "$status" -ne 0 ]
}

@test "username válido/inválido según RE_USER" {
  run is_valid_username "matt_92"
  [ "$status" -eq 0 ]
  run is_valid_username "matt 92"
  [ "$status" -ne 0 ]
  run is_valid_username ""
  [ "$status" -ne 0 ]
}

@test "product_valid exige id/nombre no vacíos y precio con formato" {
  run product_valid "A1" "Yerba Mate" "120.50"
  [ "$status" -eq 0 ]
  run product_valid "" "Yerba" "10"
  [ "$status" -ne 0 ]
  run product_valid "A1" "" "10"
  [ "$status" -ne 0 ]
  run product_valid "A1" "Yerba" "mal"
  [ "$status" -ne 0 ]
}
