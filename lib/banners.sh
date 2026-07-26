#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

BOLD='\033[1m'
BLINK='\033[5m'

# Fondo
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'

print_banner() {
    clear
    echo -e "${CYAN}=============================================="
    echo -e "${BOLD}${WHITE}         PANEL DE ADMINISTRACION VPS"
    echo -e "${CYAN}=============================================="
    echo -e "${GREEN}   Version: ${YELLOW}1.0${NC}"
    echo -e "${GREEN}   SO:      ${YELLOW}Ubuntu 22.04+${NC}"
    echo -e "${CYAN}=============================================="
    echo ""
}

print_title() {
    local title="$1"
    clear
    echo -e "${CYAN}=============================================="
    echo -e "${BOLD}${WHITE}  $title"
    echo -e "${CYAN}=============================================="
    echo ""
}

msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

msg_neutral() {
    echo -e "${BOLD}  $1${NC}"
}

separator() {
    echo -e "${GRAY}----------------------------------------------${NC}"
}

pause() {
    echo ""
    read -rp "$(echo -e ${YELLOW}Presiona ENTER para continuar...${NC})"
}

show_menu() {
    local title="$1"
    shift
    print_title "$title"
    for item in "$@"; do
        echo -e "  ${GREEN}$item${NC}"
    done
    separator
    echo ""
    read -rp "  $(echo -e ${CYAN}Selecciona una opcion [0-$(($#-1))]: ${NC})" option
    echo ""
}

confirm_action() {
    local msg="${1:-Estas seguro de continuar?}"
    echo ""
    read -rp "$(echo -e ${YELLOW}$msg [s/N]: ${NC})" confirm
    case "$confirm" in
        [Ss]*) return 0 ;;
        *) return 1 ;;
    esac
}
