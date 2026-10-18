APP_NAME="OXGI - SCRIPT"
SCRIPT_VERSION="0.3.8"

# Shared OXGI VPS logo and terminal palette.
OXGI_LOGO="OXGI - VPS"
OXGI_LOGO_LINE_1='  ___  __  __  ____ ___       __   __ ____  ____'
OXGI_LOGO_LINE_2=' / _ \ \ \/ / / ___|_ _|       \ \ / /|  _ \|  ___|'
OXGI_LOGO_LINE_3='| | | | \  / | |  _ | |   ___   \ V / | |_) |___ \'
OXGI_LOGO_LINE_4='| |_| | /  \ | |_| || |  |___|   | |  |  __/ ___) |'
OXGI_LOGO_LINE_5=' \___/ /_/\_\ \____|___|          |_|  |_|   |____/'
OXGI_COLOR_RESET=$'\033[0m'
OXGI_COLOR_BOLD=$'\033[1m'
OXGI_COLOR_LINE=$'\033[38;5;63m'
OXGI_COLOR_BRAND_BG=$'\033[41m'
OXGI_COLOR_BRAND_FG=$'\033[97m'
OXGI_COLOR_GREEN=$'\033[38;5;46m'
OXGI_COLOR_RED=$'\033[38;5;196m'
OXGI_COLOR_YELLOW=$'\033[38;5;226m'
OXGI_COLOR_CYAN=$'\033[38;5;51m'
OXGI_COLOR_BLUE=$'\033[38;5;63m'
OXGI_COLOR_WHITE=$'\033[38;5;255m'

oxgi_print_logo() {
    local green="$OXGI_COLOR_GREEN" white="$OXGI_COLOR_WHITE" red="$OXGI_COLOR_RED"
    local yellow="$OXGI_COLOR_YELLOW" bold="$OXGI_COLOR_BOLD" reset="$OXGI_COLOR_RESET"

    if [[ ! -t 1 ]]; then
        green=""
        white=""
        red=""
        yellow=""
        bold=""
        reset=""
    fi

    printf '%s%s%s\n' "$green" "$OXGI_LOGO_LINE_1" "$reset"
    printf '%s%s%s\n' "$white" "$OXGI_LOGO_LINE_2" "$reset"
    printf '%s%s%s\n' "$white" "$OXGI_LOGO_LINE_3" "$reset"
    printf '%s%s%s\n' "$red" "$OXGI_LOGO_LINE_4" "$reset"
    printf '%s%s%s\n' "$red" "$OXGI_LOGO_LINE_5" "$reset"
    printf '%s%s%s%s\n' "$yellow" "$bold" '                 V2 - VPN' "$reset"
}
