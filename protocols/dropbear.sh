#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

DROPBEAR_CONFIG="/etc/default/dropbear"

install_dropbear() {
    print_title "INSTALAR DROPBEAR"
    check_root

    install_pkg "dropbear"

    read -rp "  Puerto Dropbear [442]: " port
    port="${port:-442}"

    if ! is_port "$port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    cat > "$DROPBEAR_CONFIG" << EOF
NO_START=0
DROPBEAR_PORT=$port
DROPBEAR_EXTRA_ARGS="-p $port"
DROPBEAR_BANNER="/etc/dropbear/banner"
DROPBEAR_RSAKEY="/etc/dropbear/dropbear_rsa_host_key"
DROPBEAR_DSSKEY="/etc/dropbear/dropbear_dss_host_key"
DROPBEAR_ECDSAKEY="/etc/dropbear/dropbear_ecdsa_host_key"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    mkdir -p /etc/dropbear

    cat > /etc/dropbear/banner << 'DBBANNER'
=============================================
         ACCESO RESTRINGIDO - DROPBEAR
=============================================
DBBANNER

    allow_port "$port" "tcp"

    systemctl enable dropbear &>/dev/null
    systemctl restart dropbear &>/dev/null

    if check_service dropbear; then
        msg_ok "Dropbear instalado en puerto $port."
    else
        msg_error "Dropbear no pudo iniciarse."
        msg_info "Intentando manualmente..."
        dropbear -p "$port" -b /etc/dropbear/banner &>/dev/null &
    fi
    pause
}

dropbear_status() {
    print_title "ESTADO DE DROPBEAR"

    if check_service dropbear; then
        msg_ok "Dropbear activo."
    elif pgrep dropbear &>/dev/null; then
        msg_ok "Dropbear activo (proceso manual)."
    else
        msg_error "Dropbear no esta activo."
    fi

    echo ""
    echo -e "  ${BOLD}Puerto:${NC}"
    if pgrep dropbear &>/dev/null; then
        ss -tlnp | grep dropbear | awk '{print "  "$4}' | sed 's/.*://' | sort -u
    fi

    echo ""
    echo -e "  ${BOLD}Conexiones activas:${NC}"
    ss -tnp | grep dropbear | wc -l | xargs echo "  Total:"

    pause
}

dropbear_multi_port() {
    print_title "DROPBEAR MULTI-PUERTO"
    check_root

    read -rp "  Puertos adicionales (separados por espacio, ej: 443 80): " -a ports

    local port1 port2
    if [[ ${#ports[@]} -ge 1 ]]; then port1="${ports[0]}"; fi
    if [[ ${#ports[@]} -ge 2 ]]; then port2="${ports[1]}"; fi

    local p1="${port1:-0}" p2="${port2:-0}"

    if [[ "$p1" -gt 0 ]]; then allow_port "$p1" "tcp"; fi
    if [[ "$p2" -gt 0 ]]; then allow_port "$p2" "tcp"; fi

    sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"-p $p1 -p $p2\"/" "$DROPBEAR_CONFIG" 2>/dev/null

    pkill dropbear 2>/dev/null
    sleep 1
    dropbear -p "$p1" -p "$p2" -b /etc/dropbear/banner &>/dev/null &

    msg_ok "Dropbear configurado en puertos $p1, $p2."
    pause
}

dropbear_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION DROPBEAR ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar Dropbear"
        echo -e "  ${GREEN}2)${NC} Ver estado"
        echo -e "  ${GREEN}3)${NC} Configurar multi-puerto"
        echo -e "  ${GREEN}4)${NC} Detener Dropbear"
        echo -e "  ${GREEN}5)${NC} Reiniciar Dropbear"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_dropbear ;;
            2) dropbear_status ;;
            3) dropbear_multi_port ;;
            4)
                pkill dropbear 2>/dev/null
                systemctl stop dropbear 2>/dev/null
                msg_ok "Dropbear detenido."
                pause
                ;;
            5)
                systemctl restart dropbear 2>/dev/null || dropbear -b /etc/dropbear/banner &>/dev/null &
                msg_ok "Dropbear reiniciado."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    dropbear_menu
fi
