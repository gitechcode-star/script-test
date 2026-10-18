#!/usr/bin/env bash

set -Eeuo pipefail

readonly APP_NAME="OXGI - VPN SCRIPT"
readonly SCRIPT_VERSION="0.1.0"
readonly APP_ROOT="/opt/vpn-ssh-admin"
readonly LAUNCHER="/usr/local/sbin/vpn-ssh-admin"
readonly CONFIG_DIR="/etc/vpn-ssh-admin"
readonly OWNERSHIP_MARKER=".managed-by-vpn-ssh-admin"
readonly MARKER_VALUE="Managed by VPN-SSH-Admin"

if [[ -t 1 ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_CYAN=$'\033[36m'
    readonly C_BLUE=$'\033[34m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_RED=$'\033[31m'
else
    readonly C_RESET=""
    readonly C_BOLD=""
    readonly C_CYAN=""
    readonly C_BLUE=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_RED=""
fi

fail() {
    printf '%sError: %s%s\n' "$C_RED" "$1" "$C_RESET" >&2
    return 1
}

pause() {
    printf '\nPresiona Enter para continuar...'
    IFS= read -r _ || true
}

check_system() {
    if (( EUID != 0 )); then
        fail "ejecuta el instalador como root (por ejemplo: sudo bash install.sh)."
        return 1
    fi
    if [[ ! -r /etc/os-release ]]; then
        fail "no se pudo identificar la distribución."
        return 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || ( "${VERSION_ID:-}" != "22.04" && "${VERSION_ID:-}" != "24.04" ) ]]; then
        fail "solo se admite Ubuntu 22.04 LTS o Ubuntu 24.04 LTS."
        return 1
    fi
    if [[ ! -t 0 ]]; then
        fail "la instalación requiere una terminal interactiva."
        return 1
    fi
}

show_header() {
    clear 2>/dev/null || true
    printf '%s%s╔══════════════════════════════════════════════════╗%s\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
    printf '%s║               OXGI - VPN SCRIPT                 ║%s\n' "$C_RED$C_BOLD" "$C_RESET"
    printf '%s║                 DESARROLLADO POR OXG            ║%s\n' "$C_BLUE" "$C_RESET"
    printf '%s║                  Versión %s                    ║%s\n' "$C_YELLOW" "$SCRIPT_VERSION" "$C_RESET"
    printf '%s%s╚══════════════════════════════════════════════════╝%s\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
}

show_main_menu() {
    show_header
    printf '%sNota:%s al instalar, confirmas que aceptas las condiciones y políticas de uso del proyecto.\n' "$C_YELLOW" "$C_RESET"
    printf 'Úsalo solo en una VPS que tengas autorización para administrar y cumple las reglas\n'
    printf 'de tu proveedor y la legislación aplicable.\n\n'
    printf '1 - INSTALAR SCRIPT\n'
    printf '2 - VERIFICAR VERSIÓN DEL SCRIPT\n'
    printf '0 - SALIR\n\n'
}

is_valid_domain() {
    [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

prompt_domain() {
    local input_domain domain
    while true; do
        read -r -p 'Dominio o subdominio apuntando a esta VPS (DNS A/AAAA): ' input_domain || return 1
        domain="${input_domain,,}"
        domain="${domain%.}"
        if is_valid_domain "$domain"; then
            printf '%s' "$domain"
            return 0
        fi
        printf '%sDominio inválido. Usa un nombre como ejemplo.com o vpn.ejemplo.com.%s\n' "$C_RED" "$C_RESET" >&2
    done
}

check_managed_dir() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        [[ -d "$path" && ! -L "$path" ]] || return 1
        [[ -f "$path/$OWNERSHIP_MARKER" && ! -L "$path/$OWNERSHIP_MARKER" ]] || return 1
        grep -Fxq "$MARKER_VALUE" "$path/$OWNERSHIP_MARKER" || return 1
    fi
}

install_current_version() {
    local domain source_dir source_menu menu_temp version_temp domain_temp confirmation

    if ! domain="$(prompt_domain)"; then
        printf '\nInstalación cancelada.\n'
        pause
        return
    fi

    printf '\n%sAceptación de condiciones%s\n' "$C_BOLD" "$C_RESET"
    printf 'Confirma que aceptas las condiciones y políticas mostradas en el menú.\n'
    read -r -p 'Escribe ACEPTO para continuar: ' confirmation || return
    if [[ "$confirmation" != "ACEPTO" ]]; then
        printf 'No se aceptaron las condiciones. Instalación cancelada.\n'
        pause
        return
    fi

    source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    source_menu="$source_dir/menu.sh"
    if [[ ! -f "$source_menu" || ! -r "$source_menu" ]]; then
        fail "no se encontró menu.sh junto al instalador." || true
        pause
        return
    fi

    if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
        if [[ ! -L "$LAUNCHER" || "$(readlink -- "$LAUNCHER")" != "$APP_ROOT/menu.sh" ]]; then
            fail "$LAUNCHER ya existe y no pertenece a este instalador; no se modificó." || true
            pause
            return
        fi
    fi
    if ! check_managed_dir "$APP_ROOT"; then
        fail "$APP_ROOT existe y no está marcado como propiedad de este instalador; no se modificó."
        pause
        return
    fi
    if ! check_managed_dir "$CONFIG_DIR"; then
        fail "$CONFIG_DIR existe y no está marcado como propiedad de este instalador; no se modificó."
        pause
        return
    fi

    if [[ ! -e "$APP_ROOT" ]]; then
        install -d -o root -g root -m 0755 "$APP_ROOT"
        printf '%s\n' "$MARKER_VALUE" > "$APP_ROOT/$OWNERSHIP_MARKER"
        chmod 0644 "$APP_ROOT/$OWNERSHIP_MARKER"
    fi
    menu_temp="$(mktemp "$APP_ROOT/.menu.XXXXXX")"
    install -o root -g root -m 0750 "$source_menu" "$menu_temp"
    mv -f -- "$menu_temp" "$APP_ROOT/menu.sh"

    version_temp="$(mktemp "$APP_ROOT/.version.XXXXXX")"
    printf '%s\n' "$SCRIPT_VERSION" > "$version_temp"
    chmod 0644 "$version_temp"
    mv -f -- "$version_temp" "$APP_ROOT/VERSION"

    if [[ ! -e "$CONFIG_DIR" ]]; then
        install -d -o root -g root -m 0750 "$CONFIG_DIR"
        printf '%s\n' "$MARKER_VALUE" > "$CONFIG_DIR/$OWNERSHIP_MARKER"
        chmod 0644 "$CONFIG_DIR/$OWNERSHIP_MARKER"
    fi
    domain_temp="$(mktemp "$CONFIG_DIR/.domain.XXXXXX")"
    printf '%s\n' "$domain" > "$domain_temp"
    chmod 0644 "$domain_temp"
    mv -f -- "$domain_temp" "$CONFIG_DIR/domain"

    if [[ ! -L "$LAUNCHER" ]]; then
        ln -s "$APP_ROOT/menu.sh" "$LAUNCHER"
    fi

    printf '\n%sInstalación completada.%s\n' "$C_GREEN" "$C_RESET"
    printf 'Versión instalada: %s\n' "$SCRIPT_VERSION"
    printf 'Dominio guardado en %s/domain.\n' "$CONFIG_DIR"
    printf 'Abre el menú con: sudo vpn-ssh-admin\n'
    pause
}

show_version_menu() {
    local installed_version="No instalado"
    if [[ -f "$APP_ROOT/VERSION" && ! -L "$APP_ROOT/VERSION" ]]; then
        IFS= read -r installed_version < "$APP_ROOT/VERSION" || installed_version="No identificado"
    fi

    show_header
    printf '%sVerificar versión del script%s\n\n' "$C_BOLD" "$C_RESET"
    printf 'Versión instalada: %s\n' "$installed_version"
    printf 'Versión disponible en este instalador: %s\n\n' "$SCRIPT_VERSION"
    printf '1 - VOLVER AL MENÚ\n'
    printf '2 - INSTALAR ESTA VERSIÓN\n\n'

    local choice
    read -r -p 'Selecciona una opción: ' choice || return
    case "$choice" in
        1) return ;;
        2) install_current_version ;;
        *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
    esac
}

main() {
    if ! check_system; then
        return 1
    fi

    local choice
    while true; do
        show_main_menu
        read -r -p 'Selecciona una opción: ' choice || return 0
        case "$choice" in
            1) install_current_version ;;
            2) show_version_menu ;;
            0) printf 'Hasta luego.\n'; return 0 ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

main "$@"
