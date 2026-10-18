#!/usr/bin/env bash

set -Eeuo pipefail

readonly APP_ROOT="/opt/vpn-ssh-admin"
readonly LAUNCHER="/usr/local/sbin/vpn-ssh-admin"
readonly INSTALLER_LAUNCHER="/usr/local/sbin/oxgi-vpn-installer"
readonly CONFIG_DIR="/etc/vpn-ssh-admin"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/gitechcode-star/script-test/main"
readonly OWNERSHIP_MARKER=".managed-by-vpn-ssh-admin"
readonly MARKER_VALUE="Managed by VPN-SSH-Admin"

script_path="${BASH_SOURCE[0]:-}"
if [[ -n "$script_path" ]]; then
    while [[ -L "$script_path" ]]; do
        script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd -P)"
        link_target="$(readlink -- "$script_path")"
        if [[ "$link_target" == /* ]]; then
            script_path="$link_target"
        else
            script_path="$script_dir/$link_target"
        fi
    done
    readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$script_path")" && pwd -P)"
else
    # When run as `curl ... | bash`, Bash has no script filename to resolve.
    readonly SCRIPT_DIR=""
fi

load_script_info() {
    local info_file temp_info
    temp_info=""
    if [[ -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/script-info.sh" ]]; then
        info_file="$SCRIPT_DIR/script-info.sh"
    elif [[ -r "$PWD/script-info.sh" ]]; then
        info_file="$PWD/script-info.sh"
    else
        temp_info="$(mktemp)"
        if ! curl -fsSL "$REPO_RAW_URL/script-info.sh" -o "$temp_info"; then
            rm -f -- "$temp_info"
            printf 'Error: no pude cargar script-info.sh desde el paquete ni desde el repositorio.\n' >&2
            exit 1
        fi
        info_file="$temp_info"
    fi

    # shellcheck disable=SC1090
    if ! source "$info_file"; then
        [[ -n "$temp_info" ]] && rm -f -- "$temp_info"
        printf 'Error: script-info.sh no es válido.\n' >&2
        exit 1
    fi
    [[ -n "$temp_info" ]] && rm -f -- "$temp_info"
    if [[ -z "${APP_NAME:-}" || ! "${SCRIPT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
        printf 'Error: script-info.sh debe definir APP_NAME y una SCRIPT_VERSION válida.\n' >&2
        exit 1
    fi
}

load_script_info
readonly APP_NAME SCRIPT_VERSION

if [[ -t 1 ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_CYAN=$'\033[36m'
    readonly C_BLUE=$'\033[34m'
    readonly C_GREEN=$'\033[32m'
    readonly C_WHITE=$'\033[37m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_RED=$'\033[31m'
else
    readonly C_RESET=""
    readonly C_BOLD=""
    readonly C_CYAN=""
    readonly C_BLUE=""
    readonly C_GREEN=""
    readonly C_WHITE=""
    readonly C_YELLOW=""
    readonly C_RED=""
fi

fail() {
    printf '%sError: %s%s\n' "$C_RED" "$1" "$C_RESET" >&2
    return 1
}

pause() {
    printf '\nPresiona Enter para continuar...'
    IFS= read -r _ </dev/tty || true
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
    if [[ ! -r /dev/tty ]]; then
        fail "la instalación requiere una terminal interactiva."
        return 1
    fi
}

show_header() {
    clear 2>/dev/null || true

    printf '%s  ____   __  __   _____   _____       %s-----  %s   __      __   ______   _   _%s\n' "$C_GREEN$C_BOLD" "$C_YELLOW" "$C_GREEN$C_BOLD" "$C_RESET"
    printf '%s / __ \  \ \/ /  / ____| |_   _|      %s-----  %s   \ \    / /  |  ____| | \ | |%s\n' "$C_WHITE$C_BOLD" "$C_YELLOW" "$C_WHITE$C_BOLD" "$C_RESET"
    printf '%s| |  | |  \  /  | |  __    | |        %s-----  %s    \ \  / /   | |__    |  \| |%s\n' "$C_WHITE$C_BOLD" "$C_YELLOW" "$C_WHITE$C_BOLD" "$C_RESET"
    printf '%s| |__| |  /  \  | | |_ |   | |        %s-----  %s     \ \/ /    |  __|   | |\  |%s\n' "$C_RED$C_BOLD" "$C_YELLOW" "$C_RED$C_BOLD" "$C_RESET"
    printf '%s \____/  /_/\_\  |_____|   |_|        %s-----  %s      \__/     |_|      |_| \_|%s\n' "$C_RED$C_BOLD" "$C_YELLOW" "$C_RED$C_BOLD" "$C_RESET"
    printf '%s                                   V2%s\n\n' "$C_YELLOW$C_BOLD" "$C_RESET"
}
show_main_menu() {
    show_header
    printf '%sNota:%s al instalar, confirmas que aceptas las condiciones y políticas de uso del proyecto.\n' "$C_YELLOW" "$C_RESET"
    printf 'Úsalo solo en una VPS que tengas autorización para administrar y cumple las reglas\n'
    printf 'de tu proveedor y la legislación aplicable.\n\n'
    printf '1 - INSTALAR SCRIPT\n'
    printf '2 - VERIFICAR VERSIÓN DEL SCRIPT\n'
    printf '3 - ACTUALIZAR MENÚ DE INSTALACIÓN\n'
    printf '0 - SALIR\n\n'
}

is_valid_domain() {
    [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

prompt_domain() {
    local input_domain domain
    while true; do
        read -r -p 'Dominio o subdominio apuntando a esta VPS (DNS A/AAAA): ' input_domain </dev/tty || return 1
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
    local domain source_menu source_installer source_info source_dir temp_source_dir menu_temp installer_temp info_temp domain_temp confirmation package_version
    temp_source_dir=""

    if ! domain="$(prompt_domain)"; then
        printf '\nInstalación cancelada.\n'
        pause
        return
    fi

    printf '\n%sAceptación de condiciones%s\n' "$C_BOLD" "$C_RESET"
    printf 'Confirma que aceptas las condiciones y políticas mostradas en el menú.\n'
    read -r -p 'Escribe ACEPTO para continuar: ' confirmation </dev/tty || return
    if [[ "$confirmation" != "ACEPTO" ]]; then
        printf 'No se aceptaron las condiciones. Instalación cancelada.\n'
        pause
        return
    fi

    source_dir="$SCRIPT_DIR"
    [[ -n "$source_dir" ]] || source_dir="$PWD"
    if [[ -z "$source_dir" || ! -f "$source_dir/menu.sh" || ! -f "$source_dir/install.sh" || ! -f "$source_dir/script-info.sh" ]]; then
        temp_source_dir="$(mktemp -d)"
        if ! curl -fsSL "$REPO_RAW_URL/menu.sh" -o "$temp_source_dir/menu.sh" ||
            ! curl -fsSL "$REPO_RAW_URL/install.sh" -o "$temp_source_dir/install.sh" ||
            ! curl -fsSL "$REPO_RAW_URL/script-info.sh" -o "$temp_source_dir/script-info.sh"; then
            fail "no pude descargar el paquete completo desde el repositorio." || true
            rm -rf -- "$temp_source_dir"
            pause
            return
        fi
        package_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9A-Za-z.+-]*\)"$/\1/p' "$temp_source_dir/script-info.sh" | head -n 1)"
        if [[ "$package_version" != "$SCRIPT_VERSION" ]]; then
            fail "la versión descargada ($package_version) no coincide con el instalador ejecutado ($SCRIPT_VERSION). Vuelve a descargar install.sh e inténtalo otra vez." || true
            rm -rf -- "$temp_source_dir"
            pause
            return
        fi
        source_dir="$temp_source_dir"
    fi
    source_menu="$source_dir/menu.sh"
    source_installer="$source_dir/install.sh"
    source_info="$source_dir/script-info.sh"
    if [[ ! -f "$source_menu" || ! -r "$source_menu" || ! -f "$source_installer" || ! -r "$source_installer" || ! -f "$source_info" || ! -r "$source_info" ]]; then
        fail "se requieren install.sh, menu.sh y script-info.sh en la misma carpeta o en el repositorio configurado." || true
        [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"
        pause
        return
    fi

    if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
        if [[ ! -L "$LAUNCHER" || "$(readlink -- "$LAUNCHER")" != "$APP_ROOT/menu.sh" ]]; then
            fail "$LAUNCHER ya existe y no pertenece a este instalador; no se modificó." || true
            [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"
            pause
            return
        fi
    fi
    if [[ -e "$INSTALLER_LAUNCHER" || -L "$INSTALLER_LAUNCHER" ]]; then
        if [[ ! -L "$INSTALLER_LAUNCHER" || "$(readlink -- "$INSTALLER_LAUNCHER")" != "$APP_ROOT/install.sh" ]]; then
            fail "$INSTALLER_LAUNCHER ya existe y no pertenece a este instalador; no se modificó." || true
            [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"
            pause
            return
        fi
    fi
    if ! check_managed_dir "$APP_ROOT"; then
        fail "$APP_ROOT existe y no está marcado como propiedad de este instalador; no se modificó." || true
        [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"
        pause
        return
    fi
    if ! check_managed_dir "$CONFIG_DIR"; then
        fail "$CONFIG_DIR existe y no está marcado como propiedad de este instalador; no se modificó." || true
        [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"
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

    info_temp="$(mktemp "$APP_ROOT/.script-info.XXXXXX")"
    install -o root -g root -m 0640 "$source_info" "$info_temp"
    mv -f -- "$info_temp" "$APP_ROOT/script-info.sh"

    installer_temp="$(mktemp "$APP_ROOT/.installer.XXXXXX")"
    install -o root -g root -m 0750 "$source_installer" "$installer_temp"
    mv -f -- "$installer_temp" "$APP_ROOT/install.sh"

    if [[ -f "$APP_ROOT/VERSION" && ! -L "$APP_ROOT/VERSION" ]]; then
        rm -f -- "$APP_ROOT/VERSION"
    fi

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
    if [[ ! -L "$INSTALLER_LAUNCHER" ]]; then
        ln -s "$APP_ROOT/install.sh" "$INSTALLER_LAUNCHER"
    fi
    [[ -n "$temp_source_dir" ]] && rm -rf -- "$temp_source_dir"

    printf '\n%sInstalación completada.%s\n' "$C_GREEN" "$C_RESET"
    printf 'Versión instalada: %s\n' "$SCRIPT_VERSION"
    printf 'Dominio guardado en %s/domain.\n' "$CONFIG_DIR"
    printf 'Abre el menú con: sudo vpn-ssh-admin\n'
    printf 'Abre el instalador con: sudo oxgi-vpn-installer\n'
    pause
}

update_installer_menu() {
    local temp_dir new_installer new_menu new_info target menu_target info_target
    local new_version new_name confirmation target_dir menu_target_dir info_target_dir
    local installer_temp menu_temp info_temp backup_temp menu_backup_temp info_backup_temp
    local package_file normalized_file
    temp_dir="$(mktemp -d)"
    new_installer="$temp_dir/install.sh"
    new_menu="$temp_dir/menu.sh"
    new_info="$temp_dir/script-info.sh"
    target=""
    menu_target=""
    info_target=""

    if (( EUID != 0 )); then
        fail "se requieren permisos de root para actualizar el instalador." || true
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    printf 'Descargando el paquete actualizado...\n'
    if ! curl -fsSL "$REPO_RAW_URL/install.sh" -o "$new_installer" ||
        ! curl -fsSL "$REPO_RAW_URL/menu.sh" -o "$new_menu" ||
        ! curl -fsSL "$REPO_RAW_URL/script-info.sh" -o "$new_info"; then
        fail "No pude descargar install.sh, menu.sh y script-info.sh. Comprueba la conexion y que los tres archivos esten publicados." || true
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    # Strip Windows carriage returns before Bash validates the downloaded files.
    for package_file in "$new_installer" "$new_menu" "$new_info"; do
        normalized_file="${package_file}.lf"
        if ! tr -d '\r' < "$package_file" > "$normalized_file"; then
            fail "No pude normalizar los finales de línea del paquete; no se modificó nada." || true
            rm -rf -- "$temp_dir"
            pause
            return
        fi
        mv -f -- "$normalized_file" "$package_file"
    done

    if ! bash -n -- "$new_installer" ||
        ! grep -Fq 'main "$@"' "$new_installer" ||
        ! grep -Fq 'script-info.sh' "$new_installer" ||
        ! bash -n -- "$new_menu" ||
        ! grep -Fq 'show_main_menu()' "$new_menu" ||
        ! grep -Fq 'script-info.sh' "$new_menu" ||
        ! bash -n -- "$new_info" ||
        ! grep -Eq '^APP_NAME=".+"$' "$new_info" ||
        ! grep -Eq '^SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"$' "$new_info"; then
        fail "Los archivos descargados no forman un paquete OXGI valido; no se modifico nada." || true
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    new_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9A-Za-z.+-]*\)"$/\1/p' "$new_info" | head -n 1)"
    new_name="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' "$new_info" | head -n 1)"
    if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ || -z "$new_name" ]]; then
        fail "script-info.sh no contiene un nombre o version validos; no se modifico nada." || true
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/install.sh" && ! -L "$SCRIPT_DIR/install.sh" ]]; then
        target="$SCRIPT_DIR/install.sh"
        menu_target="$SCRIPT_DIR/menu.sh"
        info_target="$SCRIPT_DIR/script-info.sh"
    elif [[ -f "$PWD/install.sh" && ! -L "$PWD/install.sh" ]]; then
        target="$PWD/install.sh"
        menu_target="$PWD/menu.sh"
        info_target="$PWD/script-info.sh"
    elif check_managed_dir "$APP_ROOT" && [[ -f "$APP_ROOT/install.sh" && ! -L "$APP_ROOT/install.sh" ]]; then
        target="$APP_ROOT/install.sh"
        menu_target="$APP_ROOT/menu.sh"
        info_target="$APP_ROOT/script-info.sh"
    elif [[ ! -e "$INSTALLER_LAUNCHER" && ! -L "$INSTALLER_LAUNCHER" ]]; then
        target="$INSTALLER_LAUNCHER"
        menu_target="$(dirname -- "$INSTALLER_LAUNCHER")/menu.sh"
        info_target="$(dirname -- "$INSTALLER_LAUNCHER")/script-info.sh"
    else
        fail "No encontre una copia segura de install.sh para reemplazar." || true
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    printf '\nVersion actual: %s %s\n' "$APP_NAME" "$SCRIPT_VERSION"
    printf 'Version publicada: %s %s\n' "$new_name" "$new_version"
    printf 'Se actualizaran estos archivos:\n  %s\n  %s\n  %s\n' "$target" "$menu_target" "$info_target"
    if [[ -f "$target" && -f "$menu_target" && -f "$info_target" ]] &&
        cmp -s -- "$new_installer" "$target" &&
        cmp -s -- "$new_menu" "$menu_target" &&
        cmp -s -- "$new_info" "$info_target"; then
        printf '\nEl paquete ya esta actualizado.\n'
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    read -r -p 'Escribe ACTUALIZAR para reemplazar el menu completo: ' confirmation </dev/tty || {
        rm -rf -- "$temp_dir"
        return
    }
    if [[ "$confirmation" != "ACTUALIZAR" ]]; then
        printf 'Actualizacion cancelada.\n'
        rm -rf -- "$temp_dir"
        pause
        return
    fi

    target_dir="$(dirname -- "$target")"
    menu_target_dir="$(dirname -- "$menu_target")"
    info_target_dir="$(dirname -- "$info_target")"
    if [[ "$target" == "$INSTALLER_LAUNCHER" ]]; then
        install -d -o root -g root -m 0755 "$target_dir"
    fi
    install -d -o root -g root -m 0755 "$menu_target_dir" "$info_target_dir"

    installer_temp="$(mktemp "$target_dir/.install-sh-update.XXXXXX")"
    menu_temp="$(mktemp "$menu_target_dir/.menu-sh-update.XXXXXX")"
    info_temp="$(mktemp "$info_target_dir/.script-info-update.XXXXXX")"
    install -o root -g root -m 0750 "$new_installer" "$installer_temp"
    install -o root -g root -m 0750 "$new_menu" "$menu_temp"
    install -o root -g root -m 0640 "$new_info" "$info_temp"

    if [[ -f "$target" && ! -L "$target" ]]; then
        backup_temp="$(mktemp "$target_dir/.install-sh-backup.XXXXXX")"
        install -o root -g root -m 0750 "$target" "$backup_temp"
        mv -f -- "$backup_temp" "$target.bak"
    fi
    if [[ -f "$menu_target" && ! -L "$menu_target" ]]; then
        menu_backup_temp="$(mktemp "$menu_target_dir/.menu-sh-backup.XXXXXX")"
        install -o root -g root -m 0750 "$menu_target" "$menu_backup_temp"
        mv -f -- "$menu_backup_temp" "$menu_target.bak"
    fi
    if [[ -f "$info_target" && ! -L "$info_target" ]]; then
        info_backup_temp="$(mktemp "$info_target_dir/.script-info-backup.XXXXXX")"
        install -o root -g root -m 0640 "$info_target" "$info_backup_temp"
        mv -f -- "$info_backup_temp" "$info_target.bak"
    fi

    mv -f -- "$installer_temp" "$target"
    mv -f -- "$menu_temp" "$menu_target"
    mv -f -- "$info_temp" "$info_target"
    rm -rf -- "$temp_dir"

    printf '\n%sMenu completo actualizado (%s %s).%s\n' "$C_GREEN" "$new_name" "$new_version" "$C_RESET"
    printf 'Se guardaron copias .bak de los tres archivos.\n'
    printf 'Reiniciando el instalador actualizado...\n'
    exec bash "$target"
}
show_version_menu() {
    local installed_version="No instalado"
    if [[ -f "$APP_ROOT/script-info.sh" && ! -L "$APP_ROOT/script-info.sh" ]]; then
        installed_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9A-Za-z.+-]*\)"$/\1/p' "$APP_ROOT/script-info.sh" | head -n 1)"
        [[ -n "$installed_version" ]] || installed_version="No identificado"
    elif [[ -f "$APP_ROOT/VERSION" && ! -L "$APP_ROOT/VERSION" ]]; then
        IFS= read -r installed_version < "$APP_ROOT/VERSION" || installed_version="No identificado"
    fi

    show_header
    printf '%sVerificar versión del script%s\n\n' "$C_BOLD" "$C_RESET"
    printf 'Versión instalada: %s\n' "$installed_version"
    printf 'Versión disponible en este instalador: %s\n\n' "$SCRIPT_VERSION"
    printf '1 - VOLVER AL MENÚ\n'
    printf '2 - INSTALAR ESTA VERSIÓN\n\n'

    local choice
    read -r -p 'Selecciona una opción: ' choice </dev/tty || return
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
        read -r -p 'Selecciona una opción: ' choice </dev/tty || return 0
        case "$choice" in
            1) install_current_version ;;
            2) show_version_menu ;;
            3) update_installer_menu ;;
            0) printf 'Hasta luego.\n'; return 0 ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

main "$@"
