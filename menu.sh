#!/usr/bin/env bash

# Menu principal de administración del servidor.
# Las acciones de gestión se irán agregando en módulos separados.

set -o nounset

readonly APP_NAME="Administración VPN/SSH"
readonly VERSION="0.2.7"
readonly APP_ROOT="/opt/vpn-ssh-admin"
readonly LAUNCHER="/usr/local/sbin/vpn-ssh-admin"
readonly INSTALLER_LAUNCHER="/usr/local/sbin/oxgi-vpn-installer"
readonly CONFIG_DIR="/etc/vpn-ssh-admin"
readonly STATE_DIR="/var/lib/vpn-ssh-admin"
readonly LOG_DIR="/var/log/vpn-ssh-admin"
readonly SERVICE_UNIT="/etc/systemd/system/vpn-ssh-admin.service"
readonly OWNERSHIP_MARKER=".managed-by-vpn-ssh-admin"
readonly MARKER_VALUE="Managed by VPN-SSH-Admin"

if [[ -t 1 ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_CYAN=$'\033[36m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_RED=$'\033[31m'
else
    readonly C_RESET=""
    readonly C_BOLD=""
    readonly C_CYAN=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_RED=""
fi

pause() {
    printf '\nPresiona Enter para continuar...'
    IFS= read -r _ || true
}

show_header() {
    clear 2>/dev/null || true
    printf '%s%s\n' "$C_CYAN$C_BOLD" "╔══════════════════════════════════════════════╗"
    printf '║ %-44s ║\n' "$APP_NAME"
    printf '║ %-44s ║\n' "Versión $VERSION"
    printf '%s\n' "╚══════════════════════════════════════════════╝$C_RESET"
}

not_ready() {
    printf '%sEsta opción todavía no está implementada.%s\n' "$C_YELLOW" "$C_RESET"
    pause
}

uninstall_system() {
    show_header
    printf '%sDesinstalar este sistema%s\n\n' "$C_BOLD" "$C_RESET"

    if (( EUID != 0 )); then
        printf '%sEsta operación requiere permisos de administrador (root).%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi

    local -a targets=()
    local path

    for path in "$APP_ROOT" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"; do
        if [[ -d "$path" && ! -L "$path" && -f "$path/$OWNERSHIP_MARKER" && ! -L "$path/$OWNERSHIP_MARKER" ]] &&
            grep -Fxq "$MARKER_VALUE" "$path/$OWNERSHIP_MARKER"; then
            targets+=("$path")
        fi
    done
    if [[ -L "$LAUNCHER" ]] && [[ "$(readlink -- "$LAUNCHER")" == "$APP_ROOT/menu.sh" ]]; then
        targets+=("$LAUNCHER")
    fi
    if [[ -L "$INSTALLER_LAUNCHER" ]] && [[ "$(readlink -- "$INSTALLER_LAUNCHER")" == "$APP_ROOT/install.sh" ]]; then
        targets+=("$INSTALLER_LAUNCHER")
    fi
    if [[ -f "$SERVICE_UNIT" && ! -L "$SERVICE_UNIT" ]] && grep -Fxq '# Managed by VPN-SSH-Admin' "$SERVICE_UNIT"; then
        targets+=("$SERVICE_UNIT")
    fi

    if (( ${#targets[@]} == 0 )); then
        printf 'No encontré archivos instalados en las rutas administradas por este script.\n'
        printf 'No se modificó el servidor.\n'
        pause
        return
    fi

    printf 'Se eliminarán únicamente estas rutas:\n'
    for path in "${targets[@]}"; do
        printf '  - %s\n' "$path"
    done
    printf '\nTambién se intentará detener y deshabilitar el servicio propio si existe.\n'
    printf 'No se eliminarán paquetes del sistema ni configuraciones compartidas.\n\n'
    printf '%sEsto puede borrar cuentas y datos guardados por el sistema VPN/SSH.%s\n' "$C_RED" "$C_RESET"
    read -r -p 'Para confirmar, escribe ELIMINAR: ' confirmation || return
    if [[ "$confirmation" != "ELIMINAR" ]]; then
        printf 'Cancelado. No se modificó el servidor.\n'
        pause
        return
    fi

    if [[ -f "$SERVICE_UNIT" && ! -L "$SERVICE_UNIT" ]] && grep -Fxq '# Managed by VPN-SSH-Admin' "$SERVICE_UNIT" && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now vpn-ssh-admin.service >/dev/null 2>&1 || true
    fi

    for path in "${targets[@]}"; do
        case "$path" in
            "$APP_ROOT"|"$CONFIG_DIR"|"$STATE_DIR"|"$LOG_DIR") rm -rf -- "$path" ;;
            "$LAUNCHER") rm -f -- "$path" ;;
            "$INSTALLER_LAUNCHER") rm -f -- "$path" ;;
            "$SERVICE_UNIT") rm -f -- "$path" ;;
        esac
    done

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    printf '\n%sSe eliminaron los archivos propios registrados en las rutas anteriores.%s\n' "$C_GREEN" "$C_RESET"
    printf 'Los paquetes compartidos y la configuración general del servidor permanecen intactos.\n'
    pause
}

show_users_menu() {
    while true; do
        show_header
        printf '%sGestión de cuentas%s\n\n' "$C_BOLD" "$C_RESET"
        printf '  1) Crear cuenta\n'
        printf '  2) Listar cuentas\n'
        printf '  3) Eliminar cuenta\n'
        printf '  0) Volver\n\n'
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1|2|3) not_ready ;;
            0) return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_services_menu() {
    while true; do
        show_header
        printf '%sServicios%s\n\n' "$C_BOLD" "$C_RESET"
        printf '  1) Ver estado de servicios\n'
        printf '  2) Reiniciar un servicio\n'
        printf '  3) Ver registros\n'
        printf '  0) Volver\n\n'
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1|2|3) not_ready ;;
            0) return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_main_menu() {
    while true; do
        show_header
        printf '  1) Administrar cuentas\n'
        printf '  2) Administrar servicios\n'
        printf '  3) Información del servidor\n'
        printf '  4) Red y puertos\n'
        printf '  5) Copias de seguridad\n'
        printf '  6) Actualizar el sistema\n'
        printf '  7) Desinstalar este sistema\n'
        printf '  0) Salir\n\n'

        if (( EUID != 0 )); then
            printf '%sAviso: inicia el menú como root para habilitar tareas administrativas.%s\n\n' "$C_YELLOW" "$C_RESET"
        fi

        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1) show_users_menu ;;
            2) show_services_menu ;;
            3|4|5|6) not_ready ;;
            7) uninstall_system ;;
            0) printf '%sHasta luego.%s\n' "$C_GREEN" "$C_RESET"; return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_main_menu
