#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

BADVPN_DIR="/opt/script-cgh/badvpn"

install_badvpn() {
    print_title "INSTALAR BADVPN-UDPGW"
    check_root

    local arch
    arch=$(uname -m)

    read -rp "  Puerto BadVPN [7300]: " port
    port="${port:-7300}"

    if ! is_port "$port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    mkdir -p "$BADVPN_DIR"

    # Intentar instalar via apt
    if apt-cache show badvpn &>/dev/null 2>&1; then
        msg_info "Instalando badvpn via apt..."
        apt-get install -y badvpn &>/dev/null

        if has_command badvpn-udpgw; then
            install_badvpn_service "$port"
            return
        fi
    fi

    # Compilar desde fuente
    msg_info "Compilando BadVPN desde fuente..."

    install_pkg "cmake"
    install_pkg "build-essential"
    install_pkg "libnss3-dev"
    install_pkg "libssl-dev"

    local src_dir="/tmp/badvpn_build"
    rm -rf "$src_dir"
    mkdir -p "$src_dir"

    msg_info "Descargando fuente..."
    curl -sL "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/badvpn/badvpn-1.999.128.tar.bz2" -o "$src_dir/badvpn.tar.bz2"

    if [[ ! -f "$src_dir/badvpn.tar.bz2" ]]; then
        msg_error "No se pudo descargar el fuente de BadVPN."
        pause
        return 1
    fi

    cd "$src_dir" || return 1
    tar -xjf badvpn.tar.bz2 &>/dev/null
    cd badvpn-1.999.128 2>/dev/null || cd badvpn-* 2>/dev/null || return 1

    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 -DBUILD_TUN2SOCKS=0 . &>/dev/null
    make -j"$(nproc)" &>/dev/null

    cp udpgw/badvpn-udpgw "$BADVPN_DIR/" 2>/dev/null

    cd /tmp || return
    rm -rf "$src_dir"

    if [[ ! -f "$BADVPN_DIR/badvpn-udpgw" ]]; then
        msg_error "No se pudo compilar BadVPN."
        pause
        return 1
    fi

    install_badvpn_service "$port"
}

install_badvpn_service() {
    local port="$1"

    cat > /etc/systemd/system/badvpn-udpgw.service << EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
ExecStart=$BADVPN_DIR/badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 1000 --max-connections-for-client 10
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service badvpn-udpgw

    allow_port "$port" "udp"

    msg_ok "BadVPN-UDPGW instalado en puerto $port."
    pause
}

badvpn_status() {
    print_title "ESTADO DE BADVPN"

    if check_service badvpn-udpgw; then
        msg_ok "BadVPN activo."
    else
        msg_error "BadVPN inactivo."
    fi

    echo ""
    ss -ulnp | grep udpgw | while read -r line; do
        echo -e "  $line"
    done

    pause
}

badvpn_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION BADVPN ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar BadVPN-UDPGW"
        echo -e "  ${GREEN}2)${NC} Ver estado"
        echo -e "  ${GREEN}3)${NC} Reiniciar"
        echo -e "  ${GREEN}4)${NC} Detener"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_badvpn ;;
            2) badvpn_status ;;
            3)
                systemctl restart badvpn-udpgw 2>/dev/null
                msg_ok "BadVPN reiniciado."
                pause
                ;;
            4)
                systemctl stop badvpn-udpgw 2>/dev/null
                msg_ok "BadVPN detenido."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    badvpn_menu
fi
