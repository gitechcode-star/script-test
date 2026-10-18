#!/usr/bin/env bash

# Menu principal de administración del servidor.
# Las acciones de gestión se irán agregando en módulos separados.

set -o nounset

readonly APP_ROOT="/opt/vpn-ssh-admin"
readonly LAUNCHER="/usr/local/sbin/vpn-ssh-admin"
readonly INSTALLER_LAUNCHER="/usr/local/sbin/oxgi-vpn-installer"
readonly CONFIG_DIR="/etc/vpn-ssh-admin"
readonly STATE_DIR="/var/lib/vpn-ssh-admin"
readonly LOG_DIR="/var/log/vpn-ssh-admin"
readonly SERVICE_UNIT="/etc/systemd/system/vpn-ssh-admin.service"
readonly OWNERSHIP_MARKER=".managed-by-vpn-ssh-admin"
readonly MARKER_VALUE="Managed by VPN-SSH-Admin"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/gitechcode-star/script-test/main"

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
    readonly SCRIPT_DIR=""
fi

metadata_file=""
if [[ -n "$SCRIPT_DIR" && -r "$SCRIPT_DIR/script-info.sh" ]]; then
    metadata_file="$SCRIPT_DIR/script-info.sh"
elif [[ -r "$APP_ROOT/script-info.sh" ]]; then
    metadata_file="$APP_ROOT/script-info.sh"
fi
if [[ -z "$metadata_file" ]]; then
    printf 'Error: no encontré script-info.sh junto al menú ni en %s.\n' "$APP_ROOT" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$metadata_file"
if [[ -z "${APP_NAME:-}" || ! "${SCRIPT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    printf 'Error: script-info.sh no contiene un nombre y versión válidos.\n' >&2
    exit 1
fi
readonly APP_NAME SCRIPT_VERSION

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
    printf '║ %-44s ║\n' "Versión $SCRIPT_VERSION"
    printf '%s\n' "╚══════════════════════════════════════════════╝$C_RESET"
}

not_ready() {
    printf '%sEsta opción todavía no está implementada.%s\n' "$C_YELLOW" "$C_RESET"
    pause
}

open_installer_menu() {
    local installer="$APP_ROOT/install.sh"

    if [[ ! -f "$installer" || ! -r "$installer" ]]; then
        printf '%sNo encontré el instalador en %s.%s\n' "$C_RED" "$installer" "$C_RESET"
        pause
        return
    fi

    if (( EUID == 0 )); then
        bash "$installer"
    elif command -v sudo >/dev/null 2>&1; then
        sudo bash "$installer"
    else
        printf '%sAbre el menú como root para ejecutar el instalador.%s\n' "$C_RED" "$C_RESET"
        pause
    fi
}

update_system() {
    local temp_dir stage_dir file version package
    local -a packages=()
    local -a files=(menu.sh install.sh script-info.sh dependencies.txt)

    if (( EUID != 0 )); then
        printf '%sEjecuta el menú como root para actualizar los archivos e instalar dependencias.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if [[ ! -f "$APP_ROOT/$OWNERSHIP_MARKER" ]] || ! grep -Fxq "$MARKER_VALUE" "$APP_ROOT/$OWNERSHIP_MARKER"; then
        printf '%sNo pude confirmar que %s pertenezca a esta instalación.%s\n' "$C_RED" "$APP_ROOT" "$C_RESET"
        pause
        return
    fi

    if ! temp_dir="$(mktemp -d)" || ! stage_dir="$(mktemp -d "$APP_ROOT/.system-update.XXXXXX")"; then
        printf '%sNo pude preparar el espacio temporal para la actualización.%s\n' "$C_RED" "$C_RESET"
        [[ -n "${temp_dir:-}" ]] && rm -rf -- "$temp_dir"
        pause
        return
    fi
    printf 'Descargando la actualización completa...\n'
    for file in "${files[@]}"; do
        if ! curl -fsSL "$REPO_RAW_URL/$file" -o "$temp_dir/$file" ||
            ! tr -d '\r' < "$temp_dir/$file" > "$temp_dir/$file.lf"; then
            printf '%sNo pude descargar o preparar %s; no se actualizó el menú.%s\n' "$C_RED" "$file" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
        mv -f -- "$temp_dir/$file.lf" "$temp_dir/$file"
    done

    if ! bash -n -- "$temp_dir/menu.sh" ||
        ! grep -Fq 'show_main_menu()' "$temp_dir/menu.sh" ||
        ! bash -n -- "$temp_dir/install.sh" ||
        ! grep -Fq 'main "$@"' "$temp_dir/install.sh" ||
        ! bash -n -- "$temp_dir/script-info.sh" ||
        ! grep -Eq '^APP_NAME=".+"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"$' "$temp_dir/script-info.sh"; then
        printf '%sEl paquete descargado no es válido; no se modificaron los archivos.%s\n' "$C_RED" "$C_RESET"
        rm -rf -- "$temp_dir" "$stage_dir"
        pause
        return
    fi

    while IFS= read -r package || [[ -n "$package" ]]; do
        package="${package%%#*}"
        package="${package//[[:space:]]/}"
        [[ -z "$package" ]] && continue
        if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
            printf '%sLa lista de dependencias contiene un nombre inválido: %s%s\n' "$C_RED" "$package" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
        packages+=("$package")
    done < "$temp_dir/dependencies.txt"

    version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9A-Za-z.+-]*\)"$/\1/p' "$temp_dir/script-info.sh" | head -n 1)"
    printf 'Versión disponible: %s\n' "${version:-desconocida}"
    printf 'Instalando o actualizando dependencias del paquete...\n'
    if (( ${#packages[@]} > 0 )); then
        if ! apt-get update || ! apt-get install -y -- "${packages[@]}"; then
            printf '%sNo se pudieron instalar las dependencias; los archivos del menú no se actualizaron.%s\n' "$C_RED" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
    fi

    for file in "${files[@]}"; do
        if [[ -f "$APP_ROOT/$file" && ! -L "$APP_ROOT/$file" ]]; then
            if ! cp -p -- "$APP_ROOT/$file" "$APP_ROOT/$file.bak"; then
                printf '%sNo pude guardar la copia de seguridad de %s; cancelé la actualización.%s\n' "$C_RED" "$file" "$C_RESET"
                rm -rf -- "$temp_dir" "$stage_dir"
                pause
                return
            fi
        fi
        case "$file" in
            menu.sh|install.sh)
                if ! install -o root -g root -m 0750 "$temp_dir/$file" "$stage_dir/$file"; then
                    printf '%sNo pude preparar %s; no se reemplazaron los archivos.%s\n' "$C_RED" "$file" "$C_RESET"
                    rm -rf -- "$temp_dir" "$stage_dir"
                    pause
                    return
                fi
                ;;
            *)
                if ! install -o root -g root -m 0640 "$temp_dir/$file" "$stage_dir/$file"; then
                    printf '%sNo pude preparar %s; no se reemplazaron los archivos.%s\n' "$C_RED" "$file" "$C_RESET"
                    rm -rf -- "$temp_dir" "$stage_dir"
                    pause
                    return
                fi
                ;;
        esac
    done
    for file in "${files[@]}"; do
        if ! mv -f -- "$stage_dir/$file" "$APP_ROOT/$file"; then
            printf '%sFalló el reemplazo de %s. Revisa las copias .bak en %s.%s\n' "$C_RED" "$file" "$APP_ROOT" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
    done
    rm -rf -- "$temp_dir" "$stage_dir"
    printf '%sSistema actualizado correctamente. Reiniciando el menú...%s\n' "$C_GREEN" "$C_RESET"
    exec bash "$APP_ROOT/menu.sh"
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
        printf '%sGestión de usuarios%s\n\n' "$C_BOLD" "$C_RESET"
        printf '  1) Usuarios SSH\n'
        printf '  2) Usuarios V2Ray/Xray\n'
        printf '  0) Volver\n\n'
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1|2) not_ready ;;
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
        printf '  1) Administrar usuarios\n'
        printf '  2) Administrar servicios\n'
        printf '  3) Información del servidor\n'
        printf '  5) Copias de seguridad\n'
        printf '  6) Actualizar el sistema\n'
        printf '  7) Desinstalar este sistema\n'
        printf '  8) Abrir menú de instalación\n'
        printf '  0) Salir\n\n'

        if (( EUID != 0 )); then
            printf '%sAviso: inicia el menú como root para habilitar tareas administrativas.%s\n\n' "$C_YELLOW" "$C_RESET"
        fi

        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1) show_users_menu ;;
            2) show_services_menu ;;
            3|5) not_ready ;;
            6) update_system ;;
            7) uninstall_system ;;
            8) open_installer_menu ;;
            0) printf '%sHasta luego.%s\n' "$C_GREEN" "$C_RESET"; exit 0 ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_main_menu
