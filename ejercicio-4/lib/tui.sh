# lib/tui.sh — client TUI (whiptail). ÚNICO archivo nuevo del Lab 06.
# No toca disco directo; delega en los mismos casos de uso que lib/ui.sh
# (products/auth/report). Los casos puros nunca invocan whiptail directo:
# la TUI captura su stdout/stderr y lo exhibe en --msgbox/--textbox.
#
# Convenciones whiptail (ver AGENTS.md):
# - El resultado va a stderr: se captura con swap 3>&1 1>&2 2>&3.
# - exit != 0 = Cancel/Esc = abortar flujo y volver al menú
#   (sin log_error, sin log_action, sin escribir).
# - Cada llamada se protege con if/|| por set -e.

# @brief Verifica dependencia de --tui: whiptail instalado + TTY.
# @return 0 ok / 1 falta dependencia (mensaje amable vía log_error).
tui_require() {
    command -v whiptail >/dev/null || { log_error "Error: whiptail no instalado (se requiere para --tui)."; return 1; }
    [[ -t 0 && -t 1 ]] || { log_error "Error: --tui requiere terminal interactiva (TTY)."; return 1; }
}

# @brief Aviso informativo.
# @param $1 título, $2 texto.
tui_msg() {
    local title="$1"
    local text="$2"
    whiptail --title "$title" --msgbox "$text" 12 55 || true
}

# @brief Pide texto (inputbox). Cancel/Esc = 1 (el llamador vuelve al menú).
# @param $1 título, $2 prompt, $3 nombre de var donde dejar el valor.
tui_input() {
    local title="$1"
    local prompt="$2"
    local -n _out="$3"
    local val
    if ! val="$(whiptail --title "$title" --inputbox "$prompt" 10 40 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _out="$val"
}

# @brief Pide secreto (passwordbox, sin eco). Cancel/Esc = 1.
# @param $1 título, $2 prompt, $3 nombre de var donde dejar el valor.
tui_pass() {
    local title="$1"
    local prompt="$2"
    local -n _out="$3"
    local val
    if ! val="$(whiptail --title "$title" --passwordbox "$prompt" 10 40 3>&1 1>&2 2>&3)"; then
        return 1
    fi
    _out="$val"
}

# @brief Ejecuta un caso de uso y exhibe TODO lo que dijo (stdout+stderr) en msgbox.
# @param $1 título; $@ comando con sus args (ya citados por el llamador).
# @note El error amable ya quedó en error.log (log_error escribe vía tee
#   aunque su stderr esté redirigido); aquí solo se MUESTRA. Siempre retorna 0
#   para no voltear el menú por set -e (el llamador decide con el texto visto).
tui_run_show() {
    local title="$1"
    shift
    local tmp out
    tmp="$(mktemp)" || return 1
    "$@" >"$tmp" 2>&1 || true
    out="$(cat "$tmp")"
    rm -f "$tmp"
    [[ -z "$out" ]] && out="(sin mensaje)"
    whiptail --title "$title" --msgbox "$out" 12 55 || true
    return 0
}

# @brief Exhibe el listado: msgbox corto o textbox con tmpfile si es largo.
# @param $1 uid del operador, $2 username del operador.
tui_list_show() {
    local uid="$1"
    local user="$2"
    local tmp lines
    tmp="$(mktemp)" || return 1
    list_products "$uid" "$user" >"$tmp" 2>&1 || true
    lines="$(wc -l <"$tmp")"
    if (( lines <= 12 )); then
        whiptail --title "Inventario" --scrolltext --msgbox "$(cat "$tmp")" 20 60 || true
    else
        whiptail --title "Inventario" --textbox "$tmp" 20 60 || true
    fi
    rm -f "$tmp"
}

# @brief Alta de usuario en TUI (espejo de register_interactive de auth.sh).
tui_register_interactive() {
    local user pass
    tui_input "Registro" "Nuevo usuario:" user || return 0
    tui_pass "Registro" "Contraseña:" pass || return 0
    tui_run_show "Registro" register_user "$user" "$pass"
}

# @brief Login con 3 intentos (espejo de auth_interactive de auth.sh).
# @param $1 nombre de var donde dejar el uid, $2 nombre de var para el username.
# @return 0 acceso / 1 denegado o Cancel (volver al menú, sin error).
tui_auth_interactive() {
    local -n _uid_out="$1"
    local -n _user_out="$2"
    local -i intentos=0
    local user pass esc uid

    while (( intentos < 3 )); do
        tui_input "Acceso" "Usuario:" user || return 1
        tui_pass "Acceso" "Contraseña:" pass || return 1
        if login_user "$user" "$pass"; then
            esc="$(sql_escape "$user")"
            if uid="$(sqlite3 "$DB" "SELECT id FROM usuarios WHERE username='$esc';" 2>>"$ERRLOG")" && [[ -n "$uid" ]]; then
                _uid_out="$uid"
                _user_out="$user"
            fi
            tui_msg "Acceso" "Acceso concedido."
            return 0
        fi
        intentos=$((intentos + 1))
        tui_msg "Acceso" "Credenciales incorrectas ($intentos/3 intentos)."
    done
    return 1
}

# @brief Menú de acceso en TUI (espejo de auth_menu de auth.sh).
# @param $1 nombre de var donde dejar el uid, $2 nombre de var para el username.
# @return 0 login OK (entrar) / 1 salir o Cancel/Esc.
tui_auth_menu() {
    local -n _menu_uid="$1"
    local -n _menu_user="$2"
    local opt s uid_tmp="" user_tmp=""
    while true; do
        if ! opt="$(whiptail --title "Acceso" --menu "Elija una opción:" 15 50 3 1 "Iniciar sesión" 2 "Registrar usuario" 3 "Salir" 3>&1 1>&2 2>&3)"; then
            return 1
        fi
        case "$opt" in
            1)
                if tui_auth_interactive uid_tmp user_tmp; then
                    _menu_uid="$uid_tmp"
                    _menu_user="$user_tmp"
                    return 0
                fi
                ;;
            2)
                tui_register_interactive || true
                ;;
            3) return 1 ;;
        esac
    done
}

# @brief Menú de inventario en TUI (espejo de product_menu de ui.sh).
# @param $1 uid del operador, $2 username del operador.
tui_product_menu() {
    local uid="$1"
    local user="$2"
    local opt=""
    local id nombre precio

    while [[ "$opt" != "$OPT_EXIT" ]]; do
        if ! opt="$(whiptail --title "Acciones" --menu "Elija una opción:" 17 55 6 1 "Alta producto" 2 "Baja producto" 3 "Mostrar inventario" 4 "Editar producto" 5 "Generar reporte HTML" 6 "Salir" 3>&1 1>&2 2>&3)"; then
            opt="$OPT_EXIT"
        fi

        case "$opt" in
            "$OPT_ADD")
                tui_input "Alta" "Ingrese ID:" id || continue
                tui_input "Alta" "Ingrese Nombre:" nombre || continue
                tui_input "Alta" "Ingrese Precio:" precio || continue
                tui_run_show "Alta" add_product "$id" "$nombre" "$precio" "$uid" "$user"
                ;;
            "$OPT_REMOVE")
                tui_input "Baja" "Ingrese ID a eliminar:" id || continue
                tui_run_show "Baja" remove_product "$id" "$uid" "$user"
                ;;
            "$OPT_LIST")
                tui_list_show "$uid" "$user"
                ;;
            "$OPT_UPDATE")
                tui_input "Edición" "Ingrese ID a editar:" id || continue
                tui_input "Edición" "Ingrese nuevo Nombre:" nombre || continue
                tui_input "Edición" "Ingrese nuevo Precio:" precio || continue
                tui_run_show "Edición" update_product "$id" "$nombre" "$precio" "$uid" "$user"
                ;;
            "$OPT_REPORT")
                tui_run_show "Reporte" generate_report "$uid" "$user"
                ;;
            "$OPT_EXIT")
                tui_msg "Salida" "Saliendo del programa..."
                ;;
        esac
    done
}

# @brief Entrada TUI: exige whiptail+TTY, luego mismo flujo que cli_main.
tui_main() {
    tui_require || return 1
    init_db
    tui_msg "Bienvenida" "Bienvenido al Sistema de Gestion de Inventario"

    local uid="" user=""
    if ! tui_auth_menu uid user; then
        tui_msg "Salida" "Saliendo del programa..."
        return 0
    fi
    tui_product_menu "$uid" "$user"
}
