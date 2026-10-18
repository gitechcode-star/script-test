#!/usr/bin/env bash

# Menu principal de administración del servidor.
# Las acciones de gestión se irán agregando en módulos separados.

set -o nounset

readonly APP_ROOT="/opt/vpn-ssh-admin"
readonly LAUNCHER="/usr/local/sbin/vpn-ssh-admin"
readonly MENU_COMMAND="/usr/local/bin/menu"
readonly MENU_COMMAND_MARKER="# OXGI_MENU_COMMAND_LAUNCHER"
readonly INSTALLER_LAUNCHER="/usr/local/sbin/oxgi-vpn-installer"
readonly CONFIG_DIR="/etc/vpn-ssh-admin"
readonly AUTO_MENU_STATE="/etc/vpn-ssh-admin/auto-menu"
readonly ROOT_BASHRC="/root/.bashrc"
readonly MENU_FUNCTION_BEGIN="# OXGI_MENU_FUNCTION_BEGIN"
readonly MENU_FUNCTION_END="# OXGI_MENU_FUNCTION_END"
readonly AUTO_MENU_BEGIN="# OXGI_AUTO_MENU_BEGIN"
readonly AUTO_MENU_END="# OXGI_AUTO_MENU_END"
readonly STATE_DIR="/var/lib/vpn-ssh-admin"
readonly SSH_USERS_DIR="$STATE_DIR/ssh-users"
readonly SSH_LIMITS_FILE="/etc/security/limits.d/90-oxgi-ssh-users.conf"
readonly SSH_AUTOKILL_SERVICE="/etc/systemd/system/oxgi-ssh-autokill.service"
readonly SSH_AUTOKILL_TIMER="/etc/systemd/system/oxgi-ssh-autokill.timer"
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
if [[ -z "${APP_NAME:-}" || ! "${SCRIPT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ || -z "${OXGI_LOGO:-}" ||
    -z "${OXGI_COLOR_RESET:-}" || -z "${OXGI_COLOR_BOLD:-}" || -z "${OXGI_COLOR_LINE:-}" ||
    -z "${OXGI_COLOR_BRAND_BG:-}" || -z "${OXGI_COLOR_BRAND_FG:-}" || -z "${OXGI_COLOR_GREEN:-}" ||
    -z "${OXGI_COLOR_RED:-}" || -z "${OXGI_COLOR_YELLOW:-}" || -z "${OXGI_COLOR_CYAN:-}" ||
    -z "${OXGI_COLOR_BLUE:-}" || -z "${OXGI_COLOR_WHITE:-}" ||
    [[ -z "${OXGI_LOGO_LINE_1:-}" || -z "${OXGI_LOGO_LINE_2:-}" || -z "${OXGI_LOGO_LINE_3:-}" ||
        -z "${OXGI_LOGO_LINE_4:-}" || -z "${OXGI_LOGO_LINE_5:-}" ]] ||
    ! declare -F oxgi_print_logo >/dev/null; then
    printf 'Error: script-info.sh no contiene un nombre y versión válidos.\n' >&2
    exit 1
fi
readonly APP_NAME SCRIPT_VERSION

if [[ -t 1 ]]; then
    readonly C_RESET="$OXGI_COLOR_RESET"
    readonly C_BOLD="$OXGI_COLOR_BOLD"
    readonly C_CYAN="$OXGI_COLOR_CYAN"
    readonly C_GREEN="$OXGI_COLOR_GREEN"
    readonly C_YELLOW="$OXGI_COLOR_YELLOW"
    readonly C_RED="$OXGI_COLOR_RED"
    readonly C_BLUE="$OXGI_COLOR_BLUE"
else
    readonly C_RESET=""
    readonly C_BOLD=""
    readonly C_CYAN=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_RED=""
    readonly C_BLUE=""
fi

pause() {
    printf '\nPresiona Enter para continuar...'
    IFS= read -r _ || true
}

show_header() {
    clear 2>/dev/null || true
    oxgi_print_logo
    printf '  %sVersión %s%s\n\n' "$C_CYAN$C_BOLD" "$SCRIPT_VERSION" "$C_RESET"
}

menu_item() {
    local number="$1" label="$2" spacing="${3:-}"
    printf '  %s[%02d]%s  %s%s%s\n' "$C_RED$C_BOLD" "$number" "$C_RESET" "$C_YELLOW$C_BOLD" "$label" "$C_RESET"
    [[ "$spacing" == "blank" ]] && printf '\n'
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

update_admin_menu() {
    local temp_dir stage_dir file version
    local -a files=(menu.sh script-info.sh)

    if (( EUID != 0 )); then
        printf '%sEjecuta el menú como root para actualizar sus archivos.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if [[ ! -f "$APP_ROOT/$OWNERSHIP_MARKER" ]] || ! grep -Fxq "$MARKER_VALUE" "$APP_ROOT/$OWNERSHIP_MARKER"; then
        printf '%sNo pude confirmar que %s pertenezca a esta instalación.%s\n' "$C_RED" "$APP_ROOT" "$C_RESET"
        pause
        return
    fi
    if ! temp_dir="$(mktemp -d)" || ! stage_dir="$(mktemp -d "$APP_ROOT/.admin-menu-update.XXXXXX")"; then
        printf '%sNo pude preparar el espacio temporal para la actualización.%s\n' "$C_RED" "$C_RESET"
        [[ -n "${temp_dir:-}" ]] && rm -rf -- "$temp_dir"
        pause
        return
    fi

    printf 'Descargando el menú de administración actualizado...\n'
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
        ! bash -n -- "$temp_dir/script-info.sh" ||
        ! grep -Eq '^APP_NAME=".+"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^OXGI_LOGO=".+"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^OXGI_LOGO_LINE_[1-5]=' "$temp_dir/script-info.sh" ||
        ! grep -Fq 'oxgi_print_logo() {' "$temp_dir/script-info.sh"; then
        printf '%sLos archivos descargados no son válidos; no se modificó el menú.%s\n' "$C_RED" "$C_RESET"
        rm -rf -- "$temp_dir" "$stage_dir"
        pause
        return
    fi

    version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9A-Za-z.+-]*\)"$/\1/p' "$temp_dir/script-info.sh" | head -n 1)"
    for file in "${files[@]}"; do
        if [[ -f "$APP_ROOT/$file" && ! -L "$APP_ROOT/$file" ]] && ! cp -p -- "$APP_ROOT/$file" "$APP_ROOT/$file.bak"; then
            printf '%sNo pude guardar la copia de %s; se canceló la actualización.%s\n' "$C_RED" "$file" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
        local file_mode=0750
        [[ "$file" == "script-info.sh" ]] && file_mode=0640
        if ! install -o root -g root -m "$file_mode" "$temp_dir/$file" "$stage_dir/$file"; then
            printf '%sNo pude preparar %s; no se modificó el menú.%s\n' "$C_RED" "$file" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
    done
    for file in "${files[@]}"; do
        if ! mv -f -- "$stage_dir/$file" "$APP_ROOT/$file"; then
            printf '%sFalló el reemplazo de %s; revisa las copias .bak.%s\n' "$C_RED" "$file" "$C_RESET"
            rm -rf -- "$temp_dir" "$stage_dir"
            pause
            return
        fi
    done
    if ! ensure_menu_command force; then
        printf '%sEl menú se actualizó, pero no pude configurar el comando menu.%s\n' "$C_RED" "$C_RESET"
        rm -rf -- "$temp_dir" "$stage_dir"
        pause
        return
    fi
    install_menu_function || true
    rm -rf -- "$temp_dir" "$stage_dir"
    printf '\n%sMenú de administración actualizado a la versión %s.%s\n' "$C_GREEN" "${version:-desconocida}" "$C_RESET"
    printf 'Reiniciando el menú actualizado...\n'
    exec bash "$APP_ROOT/menu.sh"
}

update_installed_system() {
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
        ! grep -Eq '^SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^OXGI_LOGO=".+"$' "$temp_dir/script-info.sh" ||
        ! grep -Eq '^OXGI_LOGO_LINE_[1-5]=' "$temp_dir/script-info.sh" ||
        ! grep -Fq 'oxgi_print_logo() {' "$temp_dir/script-info.sh"; then
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
    if ! ensure_menu_command force; then
        printf '%sNo pude configurar el comando %s, aunque el menú se actualizó.%s\n' "$C_RED" "$MENU_COMMAND" "$C_RESET"
        rm -rf -- "$temp_dir" "$stage_dir"
        pause
        return
    fi
    if ! install_menu_function; then
        printf '%sEl menú se actualizó y el comando menu funciona, pero no pude registrar la función en %s.%s\n' "$C_YELLOW" "$ROOT_BASHRC" "$C_RESET"
    fi
    rm -rf -- "$temp_dir" "$stage_dir"
    printf '%sSistema actualizado correctamente. Reiniciando el menú...%s\n' "$C_GREEN" "$C_RESET"
    exec bash "$APP_ROOT/menu.sh"
}

remove_auto_menu_hook() {
    local temp_file begin_count end_count

    [[ -f "$ROOT_BASHRC" && ! -L "$ROOT_BASHRC" ]] || return 0
    begin_count="$(grep -Fxc -- "$AUTO_MENU_BEGIN" "$ROOT_BASHRC" || true)"
    end_count="$(grep -Fxc -- "$AUTO_MENU_END" "$ROOT_BASHRC" || true)"
    if [[ "$begin_count" == 0 && "$end_count" == 0 ]]; then
        return 0
    fi
    if [[ "$begin_count" != 1 || "$end_count" != 1 ]]; then
        printf '%sNo pude quitar el inicio automático: los marcadores de %s no están completos o están duplicados.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET" >&2
        return 1
    fi

    temp_file="$(mktemp /root/.bashrc.oxgi.XXXXXX)" || return 1
    if ! awk -v begin="$AUTO_MENU_BEGIN" -v end="$AUTO_MENU_END" '
        $0 == begin { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$ROOT_BASHRC" > "$temp_file"; then
        rm -f -- "$temp_file"
        return 1
    fi
    chmod --reference="$ROOT_BASHRC" "$temp_file" && chown --reference="$ROOT_BASHRC" "$temp_file" && mv -f -- "$temp_file" "$ROOT_BASHRC"
}

remove_menu_function() {
    local temp_file begin_count end_count

    [[ -f "$ROOT_BASHRC" && ! -L "$ROOT_BASHRC" ]] || return 0
    begin_count="$(grep -Fxc -- "$MENU_FUNCTION_BEGIN" "$ROOT_BASHRC" || true)"
    end_count="$(grep -Fxc -- "$MENU_FUNCTION_END" "$ROOT_BASHRC" || true)"
    if [[ "$begin_count" == 0 && "$end_count" == 0 ]]; then
        return 0
    fi
    if [[ "$begin_count" != 1 || "$end_count" != 1 ]]; then
        printf '%sLos marcadores de la función menu en %s no están completos o están duplicados.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET" >&2
        return 1
    fi
    temp_file="$(mktemp /root/.bashrc.oxgi.XXXXXX)" || return 1
    if ! awk -v begin="$MENU_FUNCTION_BEGIN" -v end="$MENU_FUNCTION_END" '
        $0 == begin { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$ROOT_BASHRC" > "$temp_file"; then
        rm -f -- "$temp_file"
        return 1
    fi
    chmod --reference="$ROOT_BASHRC" "$temp_file" && chown --reference="$ROOT_BASHRC" "$temp_file" && mv -f -- "$temp_file" "$ROOT_BASHRC"
}

install_menu_function() {
    local temp_file

    if [[ -L "$ROOT_BASHRC" || ( -e "$ROOT_BASHRC" && ! -f "$ROOT_BASHRC" ) ]]; then
        printf '%sNo puedo instalar la función menu: %s no es un archivo normal.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET" >&2
        return 1
    fi
    if [[ -f "$ROOT_BASHRC" ]] && { grep -Fq -- "$MENU_FUNCTION_BEGIN" "$ROOT_BASHRC" || grep -Fq -- "$MENU_FUNCTION_END" "$ROOT_BASHRC"; }; then
        remove_menu_function || return 1
    fi
    [[ -f "$ROOT_BASHRC" ]] || install -o root -g root -m 0644 /dev/null "$ROOT_BASHRC"
    temp_file="$(mktemp /root/.bashrc.oxgi.XXXXXX)" || return 1
    if ! cat "$ROOT_BASHRC" > "$temp_file" || ! cat >> "$temp_file" <<'EOF'

# OXGI_MENU_FUNCTION_BEGIN
menu() {
    /usr/local/bin/menu "$@"
}
# OXGI_MENU_FUNCTION_END
EOF
    then
        rm -f -- "$temp_file"
        return 1
    fi
    chmod --reference="$ROOT_BASHRC" "$temp_file" && chown --reference="$ROOT_BASHRC" "$temp_file" && mv -f -- "$temp_file" "$ROOT_BASHRC"
}

ensure_menu_command() {
    local force="${1:-no}" temp_file backup_path="" backup_index=0

    if [[ -L "$MENU_COMMAND" ]]; then
        [[ "$(readlink -- "$MENU_COMMAND")" == "$APP_ROOT/menu.sh" ]] && return 0
        if [[ "$force" != force ]]; then
            printf '%s%s ya existe y no pertenece a este sistema.%s\n' "$C_RED" "$MENU_COMMAND" "$C_RESET" >&2
            return 1
        fi
    elif [[ -e "$MENU_COMMAND" ]] && { [[ ! -f "$MENU_COMMAND" ]] || ! grep -Fxq "$MENU_COMMAND_MARKER" "$MENU_COMMAND"; }; then
        if [[ "$force" != force ]]; then
            printf '%s%s ya existe y no pertenece a este sistema.%s\n' "$C_RED" "$MENU_COMMAND" "$C_RESET" >&2
            return 1
        fi
    fi

    if [[ ( -e "$MENU_COMMAND" || -L "$MENU_COMMAND" ) && "$force" == force ]] &&
        { [[ -L "$MENU_COMMAND" ]] || ! grep -Fxq "$MENU_COMMAND_MARKER" "$MENU_COMMAND"; }; then
        backup_path="$MENU_COMMAND.oxgi-backup.$(date +%Y%m%d%H%M%S)"
        while [[ -e "$backup_path" || -L "$backup_path" ]]; do
            ((backup_index += 1))
            backup_path="$MENU_COMMAND.oxgi-backup.$(date +%Y%m%d%H%M%S).$backup_index"
        done
        if ! mv -- "$MENU_COMMAND" "$backup_path"; then
            return 1
        fi
        printf 'Se guardó el lanzador anterior en %s\n' "$backup_path"
    fi

    temp_file="$(mktemp /usr/local/bin/.menu.XXXXXX)" || {
        [[ -n "$backup_path" ]] && mv -- "$backup_path" "$MENU_COMMAND"
        return 1
    }
    if ! cat > "$temp_file" <<'EOF'
#!/usr/bin/env bash
# OXGI_MENU_COMMAND_LAUNCHER
if [[ -x /opt/vpn-ssh-admin/menu.sh ]]; then
    exec bash /opt/vpn-ssh-admin/menu.sh "$@"
fi
for installer_path in /usr/local/sbin/oxgi-vpn-installer /opt/vpn-ssh-admin/install.sh; do
    if [[ -r "$installer_path" ]]; then
        exec bash "$installer_path" "$@"
    fi
done
printf 'Error: no se encontro el instalador en las rutas locales de OXGI.\n' >&2
exit 1
EOF
    then
        rm -f -- "$temp_file"
        [[ -n "$backup_path" ]] && mv -- "$backup_path" "$MENU_COMMAND"
        return 1
    fi
    chmod 0755 "$temp_file" && chown root:root "$temp_file" && mv -f -- "$temp_file" "$MENU_COMMAND" || {
        rm -f -- "$temp_file"
        [[ -n "$backup_path" ]] && mv -- "$backup_path" "$MENU_COMMAND"
        return 1
    }
}
toggle_auto_menu() {
    local temp_file

    if (( EUID != 0 )); then
        printf '%sEjecuta el menú como root para cambiar el inicio automático.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if [[ -L "$CONFIG_DIR" || ! -f "$CONFIG_DIR/$OWNERSHIP_MARKER" ]] || ! grep -Fxq "$MARKER_VALUE" "$CONFIG_DIR/$OWNERSHIP_MARKER"; then
        printf '%sNo pude validar la carpeta de configuración de esta instalación.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if [[ ! -f "$APP_ROOT/menu.sh" || -L "$APP_ROOT/menu.sh" ]]; then
        printf '%sNo encontré el menú instalado en %s.%s\n' "$C_RED" "$APP_ROOT" "$C_RESET"
        pause
        return
    fi
    if [[ -f "$AUTO_MENU_STATE" ]] && grep -Fxq 'enabled' "$AUTO_MENU_STATE"; then
        if ! remove_auto_menu_hook; then
            pause
            return
        fi
        rm -f -- "$AUTO_MENU_STATE"
        printf '%sInicio automático desactivado. Puedes abrir el menú escribiendo: menu%s\n' "$C_GREEN" "$C_RESET"
        pause
        return
    fi

    if ! ensure_menu_command; then
        pause
        return
    fi
    if ! install_menu_function; then
        printf '%sLa función menu no quedó registrada en %s.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET"
        pause
        return
    fi
    if [[ -L "$ROOT_BASHRC" || ( -e "$ROOT_BASHRC" && ! -f "$ROOT_BASHRC" ) ]]; then
        printf '%sNo puedo modificar %s porque no es un archivo normal.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET"
        pause
        return
    fi

    if [[ -f "$ROOT_BASHRC" ]] && { grep -Fq -- "$AUTO_MENU_BEGIN" "$ROOT_BASHRC" || grep -Fq -- "$AUTO_MENU_END" "$ROOT_BASHRC"; }; then
        if ! remove_auto_menu_hook; then
            pause
            return
        fi
    fi
    [[ -f "$ROOT_BASHRC" ]] || install -o root -g root -m 0644 /dev/null "$ROOT_BASHRC"
    temp_file="$(mktemp /root/.bashrc.oxgi.XXXXXX)" || {
        printf '%sNo pude preparar %s.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET"
        pause
        return
    }
    if ! cat "$ROOT_BASHRC" > "$temp_file" || ! cat >> "$temp_file" <<'EOF'

# OXGI_AUTO_MENU_BEGIN
if [[ $- == *i* && -t 0 && -t 1 && ${EUID:-$(id -u)} -eq 0 && -f /etc/vpn-ssh-admin/auto-menu ]] && grep -Fxq 'enabled' /etc/vpn-ssh-admin/auto-menu; then
    exec /usr/local/bin/menu
fi
# OXGI_AUTO_MENU_END
EOF
    then
        rm -f -- "$temp_file"
        printf '%sNo pude guardar el inicio automático en %s.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET"
        pause
        return
    fi
    chmod --reference="$ROOT_BASHRC" "$temp_file" && chown --reference="$ROOT_BASHRC" "$temp_file" && mv -f -- "$temp_file" "$ROOT_BASHRC" || {
        rm -f -- "$temp_file"
        printf '%sNo pude instalar el bloque automático en %s.%s\n' "$C_RED" "$ROOT_BASHRC" "$C_RESET"
        pause
        return
    }

    temp_file="$(mktemp /etc/vpn-ssh-admin/.auto-menu.XXXXXX)" || {
        remove_auto_menu_hook || true
        printf '%sNo pude guardar la preferencia de inicio automático.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    }
    printf 'enabled\n' > "$temp_file"
    chmod 0644 "$temp_file"
    mv -f -- "$temp_file" "$AUTO_MENU_STATE"
    printf '%sInicio automático activado para las terminales interactivas de root.%s\n' "$C_GREEN" "$C_RESET"
    printf 'En terminales nuevas se abrirá el menú; escribe menu para abrirlo manualmente cuando esté desactivado.\n'
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
    local path certificate_domain="" certbot_link_owned=0 username

    if [[ -f "$CONFIG_DIR/domain" && ! -L "$CONFIG_DIR/domain" ]]; then
        IFS= read -r certificate_domain < "$CONFIG_DIR/domain" || true
        if [[ ! "$certificate_domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            printf '%sEl dominio guardado no es válido; no puedo retirar sus recursos SSL de forma segura.%s\n' "$C_RED" "$C_RESET"
            pause
            return
        fi
    fi
    if [[ -L /usr/local/bin/certbot ]] && [[ "$(readlink -- /usr/local/bin/certbot)" == "/snap/bin/certbot" ]]; then
        certbot_link_owned=1
    fi
    local auto_menu_hook=0
    if [[ -f "$ROOT_BASHRC" && ! -L "$ROOT_BASHRC" ]] && grep -Fq -- "$AUTO_MENU_BEGIN" "$ROOT_BASHRC"; then
        auto_menu_hook=1
    fi
    local menu_function_installed=0
    if [[ -f "$ROOT_BASHRC" && ! -L "$ROOT_BASHRC" ]] && grep -Fq -- "$MENU_FUNCTION_BEGIN" "$ROOT_BASHRC"; then
        menu_function_installed=1
    fi

    for path in "$APP_ROOT" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"; do
        if [[ -d "$path" && ! -L "$path" && -f "$path/$OWNERSHIP_MARKER" && ! -L "$path/$OWNERSHIP_MARKER" ]] &&
            grep -Fxq "$MARKER_VALUE" "$path/$OWNERSHIP_MARKER"; then
            targets+=("$path")
        fi
    done
    if [[ -L "$LAUNCHER" ]] && [[ "$(readlink -- "$LAUNCHER")" == "$APP_ROOT/menu.sh" ]]; then
        targets+=("$LAUNCHER")
    fi
    if [[ -L "$MENU_COMMAND" ]] && [[ "$(readlink -- "$MENU_COMMAND")" == "$APP_ROOT/menu.sh" ]]; then
        targets+=("$MENU_COMMAND")
    elif [[ -f "$MENU_COMMAND" && ! -L "$MENU_COMMAND" ]] && grep -Fxq "$MENU_COMMAND_MARKER" "$MENU_COMMAND"; then
        targets+=("$MENU_COMMAND")
    fi
    if [[ -L "$INSTALLER_LAUNCHER" ]] && [[ "$(readlink -- "$INSTALLER_LAUNCHER")" == "$APP_ROOT/install.sh" ]]; then
        targets+=("$INSTALLER_LAUNCHER")
    fi
    if [[ -f "$SERVICE_UNIT" && ! -L "$SERVICE_UNIT" ]] && grep -Fxq '# Managed by VPN-SSH-Admin' "$SERVICE_UNIT"; then
        targets+=("$SERVICE_UNIT")
    fi
    if [[ -f "$SSH_USERS_DIR/$OWNERSHIP_MARKER" && ! -L "$SSH_USERS_DIR/$OWNERSHIP_MARKER" ]] && grep -Fxq "$MARKER_VALUE" "$SSH_USERS_DIR/$OWNERSHIP_MARKER"; then
        while IFS= read -r username; do
            targets+=("Cuenta SSH: $username")
        done < <(ssh_user_names)
        targets+=("$SSH_USERS_DIR")
    fi
    if [[ -f "$SSH_LIMITS_FILE" && ! -L "$SSH_LIMITS_FILE" ]] && grep -Fxq '# OXGI_MANAGED_SSH_USER_LIMITS' "$SSH_LIMITS_FILE"; then
        targets+=("$SSH_LIMITS_FILE")
    fi
    if [[ -f "$SSH_AUTOKILL_SERVICE" && ! -L "$SSH_AUTOKILL_SERVICE" ]] && grep -Fxq '# OXGI_MANAGED_SSH_AUTOKILL' "$SSH_AUTOKILL_SERVICE"; then
        targets+=("$SSH_AUTOKILL_SERVICE")
    fi
    if [[ -f "$SSH_AUTOKILL_TIMER" && ! -L "$SSH_AUTOKILL_TIMER" ]] && grep -Fxq '# OXGI_MANAGED_SSH_AUTOKILL' "$SSH_AUTOKILL_TIMER"; then
        targets+=("$SSH_AUTOKILL_TIMER")
    fi
    if [[ -n "$certificate_domain" ]]; then
        for path in "/etc/letsencrypt/live/$certificate_domain" "/etc/letsencrypt/archive/$certificate_domain" "/etc/letsencrypt/renewal/$certificate_domain.conf"; do
            if [[ -e "$path" || -L "$path" ]]; then
                targets+=("$path")
            fi
        done
    fi
    if (( certbot_link_owned )); then
        targets+=("/usr/local/bin/certbot")
    fi
    if (( auto_menu_hook )); then
        targets+=("Bloque de inicio automático en $ROOT_BASHRC")
    fi
    if (( menu_function_installed )); then
        targets+=("Función menu en $ROOT_BASHRC")
    fi

    if (( ${#targets[@]} == 0 )); then
        printf 'No encontré archivos instalados en las rutas administradas por este script.\n'
        printf 'No se modificó el servidor.\n'
        pause
        return
    fi

    printf 'Se eliminarán los archivos y recursos creados por la instalación:\n'
    for path in "${targets[@]}"; do
        printf '  - %s\n' "$path"
    done
    if (( certbot_link_owned )) && command -v snap >/dev/null 2>&1 && snap list certbot >/dev/null 2>&1; then
        printf '  - Paquete Certbot de Snap (instalado por este instalador)\n'
    fi
    printf '\nTambién se detendrá y quitará el servicio propio si existe.\n'
    printf '%sSe borrarán el dominio y los datos SSL asociados guardados por esta instalación.%s\n' "$C_RED" "$C_RESET"
    read -r -p 'Para confirmar, escribe ELIMINAR: ' confirmation || return
    if [[ "$confirmation" != "ELIMINAR" ]]; then
        printf 'Cancelado. No se modificó el servidor.\n'
        pause
        return
    fi

    if [[ -n "$certificate_domain" ]]; then
        if command -v certbot >/dev/null 2>&1; then
            if ! certbot delete --cert-name "$certificate_domain" --non-interactive; then
                printf '%sCertbot no pudo retirar el certificado de %s; cancelo para no dejar una desinstalación a medias.%s\n' "$C_RED" "$certificate_domain" "$C_RESET"
                pause
                return
            fi
        fi
        rm -rf -- "/etc/letsencrypt/live/$certificate_domain" "/etc/letsencrypt/archive/$certificate_domain"
        rm -f -- "/etc/letsencrypt/renewal/$certificate_domain.conf"
    fi
    if [[ -f "$SSH_AUTOKILL_TIMER" && ! -L "$SSH_AUTOKILL_TIMER" ]] && grep -Fxq '# OXGI_MANAGED_SSH_AUTOKILL' "$SSH_AUTOKILL_TIMER" && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now oxgi-ssh-autokill.timer >/dev/null 2>&1 || true
    fi
    for path in "${targets[@]}"; do
        case "$path" in
            Cuenta\ SSH:\ *)
                username="${path#Cuenta SSH: }"
                if ! delete_ssh_user_account "$username"; then
                    printf '%sNo pude eliminar la cuenta SSH %s; cancelé la desinstalación para conservar los archivos de administración.%s\n' "$C_RED" "$username" "$C_RESET"
                    pause
                    return
                fi
                ;;
        esac
    done
    if ! remove_auto_menu_hook; then
        printf '%sNo continué para no dejar una configuración automática rota.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if ! remove_menu_function; then
        printf '%sNo continué para conservar los archivos del menú; no pude quitar la función de inicio.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi

    if [[ -f "$SERVICE_UNIT" && ! -L "$SERVICE_UNIT" ]] && grep -Fxq '# Managed by VPN-SSH-Admin' "$SERVICE_UNIT" && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now vpn-ssh-admin.service >/dev/null 2>&1 || true
    fi
    if (( certbot_link_owned )) && command -v snap >/dev/null 2>&1 && snap list certbot >/dev/null 2>&1; then
        if ! snap remove certbot --purge; then
            printf '%sNo pude retirar Certbot de Snap; el resto de la desinstalación continúa.%s\n' "$C_RED" "$C_RESET"
        fi
    fi

    for path in "${targets[@]}"; do
        case "$path" in
            "$APP_ROOT"|"$CONFIG_DIR"|"$STATE_DIR"|"$LOG_DIR") rm -rf -- "$path" ;;
            "$SSH_USERS_DIR")
                rm -rf -- "$path"
                ;;
            Cuenta\ SSH:\ *) ;;
            "$SSH_LIMITS_FILE"|"$SSH_AUTOKILL_SERVICE"|"$SSH_AUTOKILL_TIMER") rm -f -- "$path" ;;
            "$LAUNCHER") rm -f -- "$path" ;;
            "$MENU_COMMAND") rm -f -- "$path" ;;
            "$INSTALLER_LAUNCHER") rm -f -- "$path" ;;
            "Bloque de inicio automático en $ROOT_BASHRC") ;;
            "Función menu en $ROOT_BASHRC") ;;
            /etc/letsencrypt/live/*|/etc/letsencrypt/archive/*) rm -rf -- "$path" ;;
            /etc/letsencrypt/renewal/*.conf|/usr/local/bin/certbot) rm -f -- "$path" ;;
            "$SERVICE_UNIT") rm -f -- "$path" ;;
        esac
    done

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    rmdir -- "$STATE_DIR" 2>/dev/null || true

    printf '\n%sSe eliminaron los archivos del sistema y el certificado SSL asociado.%s\n' "$C_GREEN" "$C_RESET"
    pause
}

ensure_ssh_users_dir() {
    if [[ -L "$STATE_DIR" || ( -e "$STATE_DIR" && ! -d "$STATE_DIR" ) ]]; then
        printf '%sLa ruta de datos de usuarios no es un directorio seguro.%s\n' "$C_RED" "$C_RESET" >&2
        return 1
    fi
    install -d -o root -g root -m 0750 "$STATE_DIR" || return 1
    if [[ -L "$SSH_USERS_DIR" || ( -e "$SSH_USERS_DIR" && ! -d "$SSH_USERS_DIR" ) ]]; then
        printf '%sLa ruta de usuarios SSH no es un directorio seguro.%s\n' "$C_RED" "$C_RESET" >&2
        return 1
    fi
    install -d -o root -g root -m 0700 "$SSH_USERS_DIR" || return 1
    if [[ -e "$SSH_USERS_DIR/$OWNERSHIP_MARKER" ]]; then
        grep -Fxq "$MARKER_VALUE" "$SSH_USERS_DIR/$OWNERSHIP_MARKER" || {
            printf '%sLa carpeta de usuarios SSH no pertenece a este sistema.%s\n' "$C_RED" "$C_RESET" >&2
            return 1
        }
    elif find "$SSH_USERS_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        printf '%sLa carpeta de usuarios SSH ya contiene datos no administrados por este sistema.%s\n' "$C_RED" "$C_RESET" >&2
        return 1
    else
        printf '%s\n' "$MARKER_VALUE" > "$SSH_USERS_DIR/$OWNERSHIP_MARKER" || return 1
        chmod 0600 "$SSH_USERS_DIR/$OWNERSHIP_MARKER"
    fi
}

ssh_user_names() {
    local file name
    for file in "$SSH_USERS_DIR"/*.meta; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        name="${file##*/}"
        name="${name%.meta}"
        [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || continue
        printf '%s\n' "$name"
    done | sort
}

read_ssh_user_data() {
    local username="$1" file
    file="$SSH_USERS_DIR/$username.meta"
    SSH_USER_EXPIRY=""
    SSH_USER_LIMIT=""
    [[ -f "$file" && ! -L "$file" ]] || return 1
    IFS= read -r SSH_USER_EXPIRY < "$file" || return 1
    SSH_USER_LIMIT="$(sed -n '2p' "$file")"
    [[ "$SSH_USER_EXPIRY" =~ ^[0-9]+$ && "$SSH_USER_LIMIT" =~ ^[1-9][0-9]*$ ]]
}

write_ssh_limits() {
    local file username expiry limit temp_file
    if [[ -L "$SSH_LIMITS_FILE" ]]; then
        printf '%s%s es un enlace simbólico; no cambiaré límites PAM externos.%s\n' "$C_RED" "$SSH_LIMITS_FILE" "$C_RESET" >&2
        return 1
    fi
    if [[ -e "$SSH_LIMITS_FILE" ]] && ! grep -Fxq '# OXGI_MANAGED_SSH_USER_LIMITS' "$SSH_LIMITS_FILE"; then
        printf '%s%s existe y no pertenece al script; no cambiaré los límites PAM.%s\n' "$C_RED" "$SSH_LIMITS_FILE" "$C_RESET" >&2
        return 1
    fi
    if ! grep -Eq '^[[:space:]]*session[[:space:]].*pam_limits\.so' /etc/pam.d/sshd /etc/pam.d/common-session 2>/dev/null ||
        ! /usr/sbin/sshd -T 2>/dev/null | grep -Fxq 'usepam yes'; then
        printf '%sSSH/PAM no tiene pam_limits.so activo con UsePAM; no puedo aplicar de forma fiable el límite de sesiones por usuario.%s\n' "$C_RED" "$C_RESET" >&2
        return 1
    fi
    temp_file="$(mktemp /etc/security/limits.d/.90-oxgi-ssh-users.XXXXXX)" || return 1
    {
        printf '# OXGI_MANAGED_SSH_USER_LIMITS\n'
        for file in "$SSH_USERS_DIR"/*.meta; do
            [[ -f "$file" && ! -L "$file" ]] || continue
            username="${file##*/}"
            username="${username%.meta}"
            [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || continue
            IFS= read -r expiry < "$file" || continue
            limit="$(sed -n '2p' "$file")"
            [[ "$limit" =~ ^[1-9][0-9]*$ ]] || continue
            printf '%s hard maxlogins %s\n' "$username" "$limit"
        done
    } > "$temp_file" || { rm -f -- "$temp_file"; return 1; }
    chmod 0644 "$temp_file" && chown root:root "$temp_file" && mv -f -- "$temp_file" "$SSH_LIMITS_FILE"
}

parse_ssh_duration() {
    local duration="$1" base_epoch="$2" amount unit result
    if [[ ! "$duration" =~ ^([1-9][0-9]*)([dhm])$ ]]; then
        return 1
    fi
    amount="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
        h) result=$((base_epoch + amount * 3600)) ;;
        d|m)
            local base_date
            base_date="$(date -d "@$base_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" || return 1
            if [[ "$unit" == "d" ]]; then
                result="$(date -d "$base_date +$amount days" +%s 2>/dev/null)" || return 1
            else
                result="$(date -d "$base_date +$amount months" +%s 2>/dev/null)" || return 1
            fi
            ;;
    esac
    [[ "$result" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$result"
}

save_ssh_user_data() {
    local username="$1" expiry="$2" limit="$3" temp_file expiry_lock_date
    temp_file="$(mktemp "$SSH_USERS_DIR/.user.XXXXXX")" || return 1
    printf '%s\n%s\n' "$expiry" "$limit" > "$temp_file" || { rm -f -- "$temp_file"; return 1; }
    chmod 0600 "$temp_file" && chown root:root "$temp_file" && mv -f -- "$temp_file" "$SSH_USERS_DIR/$username.meta" || return 1
    # chage accepts dates only; lock at the start of the day after expiry so an
    # account is never disabled before its exact metadata expiration time.
    local expiry_date
    expiry_date="$(date -d "@$expiry" +%F)" || return 1
    expiry_lock_date="$(date -d "$expiry_date +1 day" +%F)" || return 1
    chage -E "$expiry_lock_date" "$username"
}

ssh_user_expiry_text() {
    local expiry="$1" now remaining days hours minutes
    now="$(date +%s)"
    if (( expiry <= now )); then
        printf 'VENCIDO'
        return
    fi
    remaining=$((expiry - now))
    days=$((remaining / 86400))
    hours=$(((remaining % 86400) / 3600))
    minutes=$(((remaining % 3600) / 60))
    printf '%s (restan %sd %sh %sm)' "$(date -d "@$expiry" '+%Y-%m-%d %H:%M:%S %Z')" "$days" "$hours" "$minutes"
}

ssh_user_remote_ips() {
    local username="$1" user_uid state recv_q send_q local_endpoint remote_endpoint process pid process_uid remote_ip
    user_uid="$(id -u "$username" 2>/dev/null)" || return
    {
    while read -r state recv_q send_q local_endpoint remote_endpoint process; do
        [[ "$state" == ESTAB && "$process" == *sshd* ]] || continue
        [[ "$process" =~ pid=([0-9]+) ]] || continue
        pid="${BASH_REMATCH[1]}"
        process_uid="$(ps -o uid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
        [[ "$process_uid" == "$user_uid" ]] || continue
        remote_ip="${remote_endpoint#[}"
        if [[ "$remote_ip" == *']:'* ]]; then
            remote_ip="${remote_ip%]:*}"
        else
            remote_ip="${remote_ip%:*}"
        fi
        [[ -n "$remote_ip" ]] && printf '%s\n' "$remote_ip"
    done < <(ss -tnpH state established 2>/dev/null)
    who -u 2>/dev/null | awk -v user="$username" '$1 == user { for (i = 1; i <= NF; i++) if ($i ~ /^\(.*\)$/) { gsub(/[()]/, "", $i); print $i } }'
    } | sort -u
}

ssh_user_connection_count() {
    local username="$1" count
    count="$(ssh_user_remote_ips "$username" | awk 'END {print NR+0}')"
    printf '%s\n' "$count"
}

show_ssh_connection_details() {
    local username="$1" password="${2:-}" limit expiry ports domain
    read_ssh_user_data "$username" || return 1
    limit="$SSH_USER_LIMIT"
    expiry="$SSH_USER_EXPIRY"
    ports="$(/usr/sbin/sshd -T 2>/dev/null | awk '$1 == "port" {printf "%s%s", separator, $2; separator=", "}')"
    [[ -n "$ports" ]] || ports="22 (predeterminado)"
    domain="$(cat "$CONFIG_DIR/domain" 2>/dev/null || printf 'IP del servidor')"
    printf '\nUsuario: %s\n' "$username"
    [[ -n "$password" ]] && printf 'Contraseña: %s\n' "$password"
    printf 'Protocolo: SSH sobre TCP\nServidor: %s\nPuerto(s) SSH: %s\n' "$domain" "$ports"
    printf 'Vencimiento: %s\n' "$(ssh_user_expiry_text "$expiry")"
    printf 'Límite simultáneo de sesiones: %s\n' "$limit"
}

list_ssh_users() {
    local username expiry limit connected index=0
    local -a users=()
    mapfile -t users < <(ssh_user_names)
    if (( ${#users[@]} == 0 )); then
        printf 'No hay usuarios SSH administrados por este script.\n'
        return
    fi
    printf '%-4s %-20s %-34s %-18s %s\n' 'N.º' 'USUARIO' 'VENCIMIENTO / TIEMPO RESTANTE' 'IP ACTIVAS' 'LÍMITE'
    printf '%s\n' '--------------------------------------------------------------------------------------------------------------'
    for username in "${users[@]}"; do
        ((index += 1))
        if ! read_ssh_user_data "$username" || ! getent passwd "$username" >/dev/null; then
            printf '%-4s %-20s %s\n' "$index" "$username" 'cuenta o registro no disponible'
            continue
        fi
        expiry="$SSH_USER_EXPIRY"
        limit="$SSH_USER_LIMIT"
        connected="$(ssh_user_connection_count "$username")"
        printf '%-4s %-20s %-34s %s/%s\n' "$index" "$username" "$(ssh_user_expiry_text "$expiry")" "$connected" "$limit"
    done
}

choose_ssh_user() {
    local prompt="$1" choice index=0 username
    local -a users=()
    mapfile -t users < <(ssh_user_names)
    if (( ${#users[@]} == 0 )); then
        printf 'No hay usuarios SSH administrados por este script.\n'
        return 1
    fi
    for username in "${users[@]}"; do
        ((index += 1))
        printf '  %s) %s\n' "$index" "$username"
    done
    read -r -p "$prompt" choice || return 1
    [[ "$choice" == 0 ]] && return 1
    [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice <= ${#users[@]} )) || {
        printf 'Selección inválida.\n'
        return 1
    }
    SSH_SELECTED_USER="${users[choice-1]}"
}

create_ssh_user() {
    local username password password_confirm duration expiry limit pam_config
    (( EUID == 0 )) || { printf '%sEsta opción requiere root.%s\n' "$C_RED" "$C_RESET"; pause; return; }
    ensure_ssh_users_dir || { pause; return; }
    pam_config="$(grep -E '^[[:space:]]*session[[:space:]].*pam_limits\.so' /etc/pam.d/sshd /etc/pam.d/common-session 2>/dev/null || true)"
    if [[ -z "$pam_config" ]] || ! /usr/sbin/sshd -T 2>/dev/null | grep -Fxq 'usepam yes'; then
        printf '%sPAM no tiene pam_limits.so activo; no puedo garantizar el límite de conexiones simultáneas.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    read -r -p 'Nombre del usuario (a-z, 0-9, guion o guion bajo): ' username || return
    username="${username,,}"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || getent passwd "$username" >/dev/null; then
        printf '%sNombre inválido o ya existente en el sistema.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if [[ -e "$SSH_USERS_DIR/$username.meta" ]]; then
        printf '%sYa existe un registro administrado para ese usuario.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    read -r -s -p 'Contraseña: ' password </dev/tty || { printf '\n'; return; }
    printf '\n'
    read -r -s -p 'Confirma la contraseña: ' password_confirm </dev/tty || { printf '\n'; return; }
    printf '\n'
    if [[ -z "$password" || "$password" == *:* || "$password" != "$password_confirm" ]]; then
        unset password password_confirm
        printf '%sLa contraseña está vacía, contiene “:” o no coincide.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    unset password_confirm
    read -r -p 'Duración (#d días, #m meses, #h horas; ejemplo 30d): ' duration || { unset password; return; }
    if ! expiry="$(parse_ssh_duration "$duration" "$(date +%s)")"; then
        unset password
        printf '%sDuración inválida. Usa, por ejemplo, 30d, 2m o 12h.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    read -r -p 'Límite de conexiones simultáneas (Enter = 1): ' limit || { unset password; return; }
    limit="${limit:-1}"
    if [[ ! "$limit" =~ ^[1-9][0-9]*$ ]] || (( limit > 1000 )); then
        unset password
        printf '%sEl límite debe ser un número entre 1 y 1000.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if ! useradd --create-home --shell /bin/bash "$username"; then
        unset password
        printf '%sNo pude crear la cuenta SSH; no se modificó ninguna cuenta existente.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if ! printf '%s:%s\n' "$username" "$password" | chpasswd; then
        userdel -r "$username" >/dev/null 2>&1 || true
        unset password
        printf '%sNo pude configurar la contraseña; retiré la cuenta recién creada.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if ! save_ssh_user_data "$username" "$expiry" "$limit"; then
        userdel -r "$username" >/dev/null 2>&1 || true
        rm -f -- "$SSH_USERS_DIR/$username.meta"
        unset password
        printf '%sNo pude guardar el vencimiento del usuario; retiré la cuenta para no dejarla sin administrar.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if ! write_ssh_limits; then
        userdel -r "$username" >/dev/null 2>&1 || true
        rm -f -- "$SSH_USERS_DIR/$username.meta"
        unset password
        pause
        return
    fi
    show_ssh_connection_details "$username" "$password"
    unset password
    printf '\nGuarda estos datos ahora; la contraseña no se almacena en el sistema.\n'
    pause
}

renew_ssh_user() {
    local username duration base_epoch expiry limit
    (( EUID == 0 )) || { printf '%sEsta opción requiere root.%s\n' "$C_RED" "$C_RESET"; pause; return; }
    ensure_ssh_users_dir || { pause; return; }
    list_ssh_users
    choose_ssh_user 'Número del usuario para renovar (0 cancela): ' || { pause; return; }
    username="$SSH_SELECTED_USER"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && getent passwd "$username" >/dev/null && read_ssh_user_data "$username" || { printf 'No pude validar esa cuenta.\n'; pause; return; }
    base_epoch="$SSH_USER_EXPIRY"
    (( base_epoch > $(date +%s) )) || base_epoch="$(date +%s)"
    limit="$SSH_USER_LIMIT"
    read -r -p 'Tiempo adicional (#d días, #m meses, #h horas): ' duration || return
    if ! expiry="$(parse_ssh_duration "$duration" "$base_epoch")"; then
        printf '%sDuración inválida. Usa, por ejemplo, 30d, 2m o 12h.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    read -r -p "Límite simultáneo de conexiones (Enter conserva $limit): " limit || return
    limit="${limit:-$SSH_USER_LIMIT}"
    if [[ ! "$limit" =~ ^[1-9][0-9]*$ ]] || (( limit > 1000 )) || ! save_ssh_user_data "$username" "$expiry" "$limit" || ! write_ssh_limits; then
        printf '%sNo pude renovar la cuenta ni actualizar sus límites.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    printf '%sUsuario %s renovado.%s\n' "$C_GREEN" "$username" "$C_RESET"
    show_ssh_connection_details "$username"
    pause
}

delete_ssh_user_account() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
    if getent passwd "$username" >/dev/null; then
        pkill -KILL -u "$username" 2>/dev/null || true
        userdel -r "$username" || return 1
    fi
    rm -f -- "$SSH_USERS_DIR/$username.meta"
}

delete_ssh_user() {
    local username confirmation
    (( EUID == 0 )) || { printf '%sEsta opción requiere root.%s\n' "$C_RED" "$C_RESET"; pause; return; }
    ensure_ssh_users_dir || { pause; return; }
    list_ssh_users
    choose_ssh_user 'Número del usuario que se eliminará (0 cancela): ' || { pause; return; }
    username="$SSH_SELECTED_USER"
    read -r -p "Escribe ELIMINAR para borrar $username y su carpeta personal: " confirmation || return
    if [[ "$confirmation" != ELIMINAR ]] || ! delete_ssh_user_account "$username" || ! write_ssh_limits; then
        printf '%sNo se eliminó la cuenta o no se pudieron actualizar los límites.%s\n' "$C_RED" "$C_RESET"
    else
        printf '%sUsuario %s eliminado.%s\n' "$C_GREEN" "$username" "$C_RESET"
    fi
    pause
}

show_online_ssh_users() {
    local username ips connected limit online=0
    ensure_ssh_users_dir || { pause; return; }
    printf '%-20s %-12s %s\n' 'USUARIO' 'IP ACTIVAS' 'LÍMITE'
    for username in $(ssh_user_names); do
        read_ssh_user_data "$username" || continue
        limit="$SSH_USER_LIMIT"
        ips="$(ssh_user_remote_ips "$username" | paste -sd ', ' -)"
        connected="$(ssh_user_connection_count "$username")"
        if (( connected > 0 )); then
            printf '%-20s %-12s %s/%s  %s\n' "$username" "$connected" "$connected" "$limit" "$ips"
            ((online += 1))
        fi
    done
    (( online > 0 )) || printf 'No hay usuarios SSH conectados en este momento.\n'
    pause
}

expire_ssh_users() {
    local username expired=0
    [[ -f "$SSH_USERS_DIR/$OWNERSHIP_MARKER" ]] && grep -Fxq "$MARKER_VALUE" "$SSH_USERS_DIR/$OWNERSHIP_MARKER" || return 0
    systemctl is-enabled --quiet oxgi-ssh-autokill.timer 2>/dev/null || return 0
    while IFS= read -r username; do
        read_ssh_user_data "$username" || continue
        if (( SSH_USER_EXPIRY <= $(date +%s) )); then
            if delete_ssh_user_account "$username"; then
                printf 'Eliminado usuario SSH vencido: %s\n' "$username"
                ((expired += 1))
            fi
        fi
    done < <(ssh_user_names)
    (( expired == 0 )) || write_ssh_limits
}

toggle_ssh_autokill() {
    local choice service_temp timer_temp
    (( EUID == 0 )) || { printf '%sEsta opción requiere root.%s\n' "$C_RED" "$C_RESET"; pause; return; }
    ensure_ssh_users_dir || { pause; return; }
    if { [[ -e "$SSH_AUTOKILL_SERVICE" || -L "$SSH_AUTOKILL_SERVICE" ]] && { [[ -L "$SSH_AUTOKILL_SERVICE" ]] || ! grep -Fxq '# OXGI_MANAGED_SSH_AUTOKILL' "$SSH_AUTOKILL_SERVICE"; }; } ||
        { [[ -e "$SSH_AUTOKILL_TIMER" || -L "$SSH_AUTOKILL_TIMER" ]] && { [[ -L "$SSH_AUTOKILL_TIMER" ]] || ! grep -Fxq '# OXGI_MANAGED_SSH_AUTOKILL' "$SSH_AUTOKILL_TIMER"; }; }; then
        printf '%sYa existe una unidad con ese nombre que no pertenece a este script; no la modificaré.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    if systemctl is-enabled --quiet oxgi-ssh-autokill.timer 2>/dev/null; then
        read -r -p 'Auto kill está ACTIVADO. Escribe DESACTIVAR para apagarlo: ' choice || return
        [[ "$choice" == DESACTIVAR ]] || { printf 'Sin cambios.\n'; pause; return; }
        systemctl disable --now oxgi-ssh-autokill.timer >/dev/null 2>&1 || { printf '%sNo pude detener el temporizador.%s\n' "$C_RED" "$C_RESET"; pause; return; }
        rm -f -- "$SSH_AUTOKILL_TIMER" "$SSH_AUTOKILL_SERVICE"
        systemctl daemon-reload
        printf '%sAuto kill desactivado.%s\n' "$C_GREEN" "$C_RESET"
    else
        service_temp="$(mktemp /etc/systemd/system/.oxgi-ssh-autokill.service.XXXXXX)" || { pause; return; }
        timer_temp="$(mktemp /etc/systemd/system/.oxgi-ssh-autokill.timer.XXXXXX)" || { rm -f -- "$service_temp"; pause; return; }
        cat > "$service_temp" <<EOF
[Unit]
Description=Eliminar usuarios SSH OXGI vencidos
# OXGI_MANAGED_SSH_AUTOKILL

[Service]
Type=oneshot
ExecStart=$APP_ROOT/menu.sh --expire-ssh-users
EOF
        cat > "$timer_temp" <<'EOF'
[Unit]
Description=Revisar vencimiento de usuarios SSH OXGI
# OXGI_MANAGED_SSH_AUTOKILL

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=oxgi-ssh-autokill.service

[Install]
WantedBy=timers.target
EOF
        chmod 0644 "$service_temp" "$timer_temp"
        chown root:root "$service_temp" "$timer_temp"
        if ! mv -f -- "$service_temp" "$SSH_AUTOKILL_SERVICE"; then
            rm -f -- "$service_temp" "$timer_temp"
            printf '%sNo pude instalar las unidades del temporizador.%s\n' "$C_RED" "$C_RESET"
            pause
            return
        fi
        if ! mv -f -- "$timer_temp" "$SSH_AUTOKILL_TIMER"; then
            rm -f -- "$SSH_AUTOKILL_SERVICE" "$timer_temp"
            printf '%sNo pude instalar las unidades del temporizador.%s\n' "$C_RED" "$C_RESET"
            pause
            return
        fi
        if ! systemctl daemon-reload || ! systemctl enable --now oxgi-ssh-autokill.timer; then
            rm -f -- "$SSH_AUTOKILL_TIMER" "$SSH_AUTOKILL_SERVICE"
            systemctl daemon-reload
            printf '%sNo pude activar el temporizador de auto kill.%s\n' "$C_RED" "$C_RESET"
            pause
            return
        fi
        printf '%sAuto kill activado: revisará vencimientos cada minuto y borrará la cuenta y su carpeta personal.%s\n' "$C_GREEN" "$C_RESET"
    fi
    pause
}

delete_all_ssh_users() {
    local username confirmation failed=0
    (( EUID == 0 )) || { printf '%sEsta opción requiere root.%s\n' "$C_RED" "$C_RESET"; pause; return; }
    ensure_ssh_users_dir || { pause; return; }
    list_ssh_users
    printf '\nSe borrarán todas las cuentas SSH administradas y sus carpetas personales.\n'
    read -r -p 'Escribe ELIMINAR TODOS para confirmar: ' confirmation || return
    [[ "$confirmation" == 'ELIMINAR TODOS' ]] || { printf 'Cancelado.\n'; pause; return; }
    while IFS= read -r username; do
        delete_ssh_user_account "$username" || failed=1
    done < <(ssh_user_names)
    write_ssh_limits || failed=1
    if (( failed )); then
        printf '%sAlgunas cuentas no se pudieron eliminar; revisa el sistema.%s\n' "$C_RED" "$C_RESET"
    else
        printf '%sSe eliminaron todos los usuarios SSH administrados.%s\n' "$C_GREEN" "$C_RESET"
    fi
    pause
}

show_ssh_users_menu() {
    local choice
    if (( EUID != 0 )); then
        printf '%sAbre el menú como root para administrar usuarios SSH.%s\n' "$C_RED" "$C_RESET"
        pause
        return
    fi
    while true; do
        show_header
        printf '%sAdministrar usuarios SSH%s\n\n' "$C_BOLD" "$C_RESET"
        menu_item 1 'Crear usuario'
        menu_item 2 'Renovar usuario'
        menu_item 3 'Listar usuarios'
        menu_item 4 'Eliminar usuario'
        menu_item 5 'Usuarios en línea'
        if systemctl is-enabled --quiet oxgi-ssh-autokill.timer 2>/dev/null; then
            menu_item 6 'Auto kill: ACTIVADO (desactivar)'
        else
            menu_item 6 'Auto kill: DESACTIVADO (activar)'
        fi
        menu_item 7 'Eliminar todos los usuarios'
        menu_item 0 'Volver' blank
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1) create_ssh_user ;;
            2) renew_ssh_user ;;
            3) ensure_ssh_users_dir && list_ssh_users; pause ;;
            4) delete_ssh_user ;;
            5) show_online_ssh_users ;;
            6) toggle_ssh_autokill ;;
            7) delete_all_ssh_users ;;
            0) return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_v2ray_users_menu() {
    local choice
    while true; do
        show_header
        printf '%sAdministrar usuarios V2Ray/Xray%s\n\n' "$C_BOLD" "$C_RESET"
        menu_item 1 'Crear usuario'
        menu_item 2 'Renovar usuario'
        menu_item 3 'Listar usuarios'
        menu_item 4 'Eliminar usuario'
        menu_item 5 'Usuarios en línea'
        menu_item 6 'Auto kill (eliminar usuarios vencidos)'
        menu_item 7 'Eliminar todos los usuarios'
        menu_item 0 'Volver' blank
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1|2|3|4|5|6|7) not_ready ;;
            0) return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_users_menu() {
    while true; do
        show_header
        printf '%sGestión de usuarios%s\n\n' "$C_BOLD" "$C_RESET"
        menu_item 1 'Usuarios SSH'
        menu_item 2 'Usuarios V2Ray/Xray'
        menu_item 0 'Volver' blank
        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1) show_ssh_users_menu ;;
            2) show_v2ray_users_menu ;;
            0) return ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}

show_services_menu() {
    while true; do
        show_header
        printf '%sServicios%s\n\n' "$C_BOLD" "$C_RESET"
        menu_item 1 'Ver estado de servicios'
        menu_item 2 'Reiniciar un servicio'
        menu_item 3 'Ver registros'
        menu_item 0 'Volver' blank
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
    local system_name ram_total ram_used cpu_cores
    while true; do
        show_header
        system_name="Linux"
        if [[ -r /etc/os-release ]]; then
            # shellcheck disable=SC1091
            source /etc/os-release
            system_name="${PRETTY_NAME:-Linux}"
        fi
        ram_total="$(free -h 2>/dev/null | awk 'NR == 2 {print $2}')"
        ram_used="$(free -h 2>/dev/null | awk 'NR == 2 {print $3}')"
        cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')"
        printf '%sSISTEMA%s  %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$system_name"
        printf '%sMEMORIA RAM%s  Total: %s  En uso: %s     %sPROCESADOR%s  Núcleos: %s\n' \
            "$C_GREEN$C_BOLD" "$C_RESET" "${ram_total:-N/D}" "${ram_used:-N/D}" \
            "$C_GREEN$C_BOLD" "$C_RESET" "$cpu_cores"
        printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$C_BLUE" "$C_RESET"
        printf '%sADMINISTRACIÓN%s\n\n' "$C_GREEN$C_BOLD" "$C_RESET"
        printf '  %s[01]%s  %sAdministrar usuarios%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[02]%s  %sAdministrar servicios%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[03]%s  %sInformación del servidor%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[05]%s  %sCopias de seguridad%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[06]%s  %sActualizar menú de administración%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[07]%s  %sDesinstalar este sistema%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '  %s[08]%s  %sAbrir menú de instalación%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        if [[ -f "$AUTO_MENU_STATE" ]] && grep -Fxq 'enabled' "$AUTO_MENU_STATE"; then
            printf '  %s[09]%s  %sInicio automático al abrir terminal: ACTIVADO (desactivar)%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        else
            printf '  %s[09]%s  %sInicio automático al abrir terminal: DESACTIVADO (activar)%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        fi
        printf '  %s[00]%s  %sSalir%s\n' "$C_RED$C_BOLD" "$C_RESET" "$C_YELLOW$C_BOLD" "$C_RESET"
        printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$C_BLUE" "$C_RESET"

        if (( EUID != 0 )); then
            printf '%sAviso: inicia el menú como root para habilitar tareas administrativas.%s\n\n' "$C_YELLOW" "$C_RESET"
        fi

        choice=""
        IFS= read -r -p 'Selecciona una opción: ' choice || return
        case "$choice" in
            1) show_users_menu ;;
            2) show_services_menu ;;
            3|5) not_ready ;;
            6) update_admin_menu ;;
            7) uninstall_system ;;
            8) open_installer_menu ;;
            9) toggle_auto_menu ;;
            0) printf '%sHasta luego.%s\n' "$C_GREEN" "$C_RESET"; exit 0 ;;
            *) printf '%sOpción inválida.%s\n' "$C_RED" "$C_RESET"; pause ;;
        esac
    done
}
if [[ "${1:-}" == "--expire-ssh-users" ]]; then
    (( EUID == 0 )) || exit 1
    expire_ssh_users
    exit 0
elif [[ "${1:-}" == "--update-system" ]]; then
    (( EUID == 0 )) || exit 1
    update_installed_system
    exit $?
fi

show_main_menu
