#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

STUNNEL_CONF="/etc/stunnel/stunnel.conf"
STUNNEL_CERT="/etc/stunnel/stunnel.pem"

generate_ssl_cert() {
    local cert_file="${1:-$STUNNEL_CERT}"
    openssl req -new -x509 -days 3650 -nodes \
        -subj "/C=US/ST=CA/L=LosAngeles/O=Dis/CN=localhost" \
        -out "$cert_file" \
        -keyout "$cert_file" 2>/dev/null
    chmod 600 "$cert_file"
}

install_stunnel() {
    print_title "INSTALAR STUNNEL"
    check_root

    install_pkg "stunnel4"
    install_pkg "openssl"

    read -rp "  Puerto Stunnel (entrada) [444]: " listen_port
    listen_port="${listen_port:-444}"

    read -rp "  Puerto destino (ej: SSH 22): " dest_port
    dest_port="${dest_port:-22}"

    if ! is_port "$listen_port" || ! is_port "$dest_port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    mkdir -p /etc/stunnel

    if [[ ! -f "$STUNNEL_CERT" ]]; then
        msg_info "Generando certificado SSL..."
        generate_ssl_cert "$STUNNEL_CERT"
        msg_ok "Certificado generado."
    fi

    cat > "$STUNNEL_CONF" << EOF
cert = $STUNNEL_CERT
pid = /var/run/stunnel4.pid
output = /var/log/stunnel4.log
setuid = stunnel4
setgid = stunnel4

[ssh-tunnel]
accept = 0.0.0.0:$listen_port
connect = 127.0.0.1:$dest_port
TIMEOUTclose = 0
EOF

    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null

    allow_port "$listen_port" "tcp"

    systemctl enable stunnel4 &>/dev/null
    systemctl restart stunnel4 &>/dev/null

    if check_service stunnel4; then
        msg_ok "Stunnel instalado: $listen_port -> $dest_port"
    else
        msg_error "Stunnel no pudo iniciarse. Verifique /var/log/stunnel4.log"
    fi
    pause
}

stunnel_add_service() {
    print_title "AGREGAR SERVICIO STUNNEL"
    check_root

    if [[ ! -f "$STUNNEL_CONF" ]]; then
        msg_error "Stunnel no esta instalado. Instalelo primero."
        pause
        return
    fi

    read -rp "  Nombre del servicio [ej: dropbear-ssl]: " svc_name
    read -rp "  Puerto entrada: " listen_port
    read -rp "  Puerto destino: " dest_port

    cat >> "$STUNNEL_CONF" << EOF

[$svc_name]
accept = 0.0.0.0:$listen_port
connect = 127.0.0.1:$dest_port
TIMEOUTclose = 0
EOF

    allow_port "$listen_port" "tcp"

    systemctl restart stunnel4 &>/dev/null
    msg_ok "Servicio '$svc_name' agregado: $listen_port -> $dest_port"
    pause
}

stunnel_status() {
    print_title "ESTADO DE STUNNEL"

    if check_service stunnel4; then
        msg_ok "Stunnel activo."
    else
        msg_error "Stunnel inactivo."
    fi

    echo ""
    echo -e "  ${BOLD}Tuneles configurados:${NC}"
    grep "^accept" "$STUNNEL_CONF" 2>/dev/null | while read -r line; do
        echo -e "  $line"
    done

    echo ""
    echo -e "  ${BOLD}Conexiones:${NC}"
    ss -tnp | grep stunnel | wc -l | xargs echo "  Total:"

    pause
}

stunnel_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION STUNNEL ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar Stunnel (SSH sobre SSL)"
        echo -e "  ${GREEN}2)${NC} Agregar servicio SSL adicional"
        echo -e "  ${GREEN}3)${NC} Ver estado"
        echo -e "  ${GREEN}4)${NC} Regenerar certificado"
        echo -e "  ${GREEN}5)${NC} Ver configuracion"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_stunnel ;;
            2) stunnel_add_service ;;
            3) stunnel_status ;;
            4)
                if confirm_action "Regenerar certificado SSL?"; then
                    generate_ssl_cert "$STUNNEL_CERT"
                    systemctl restart stunnel4 &>/dev/null
                    msg_ok "Certificado regenerado."
                fi
                pause
                ;;
            5)
                print_title "CONFIG STUNNEL"
                [[ -f "$STUNNEL_CONF" ]] && cat "$STUNNEL_CONF" || msg_warn "stunnel.conf no existe."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    stunnel_menu
fi
