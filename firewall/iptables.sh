#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

install_ufw() {
    print_title "CONFIGURAR FIREWALL UFW"
    check_root

    install_pkg "ufw"

    msg_info "Configurando reglas basicas..."
    ufw --force reset &>/dev/null

    ufw default deny incoming &>/dev/null
    ufw default allow outgoing &>/dev/null

    # Puertos comunes
    ufw allow 22/tcp &>/dev/null
    ufw allow 80/tcp &>/dev/null
    ufw allow 443/tcp &>/dev/null
    ufw allow 8080/tcp &>/dev/null

    read -rp "  Puerto SSH adicional (opcional): " extra_ssh
    [[ -n "$extra_ssh" ]] && ufw allow "$extra_ssh/tcp" &>/dev/null

    read -rp "  Puerto Dropbear (opcional): " extra_db
    [[ -n "$extra_db" ]] && ufw allow "$extra_db/tcp" &>/dev/null

    if confirm_action "Activar UFW ahora?"; then
        ufw --force enable &>/dev/null
        msg_ok "UFW activado."
    fi

    ufw status verbose
    pause
}

show_iptables() {
    print_title "REGLAS IPTABLES ACTUALES"
    echo -e "  ${BOLD}${YELLOW}INPUT:${NC}"
    iptables -L INPUT -n --line-numbers 2>/dev/null | head -30
    echo ""
    echo -e "  ${BOLD}${YELLOW}OUTPUT:${NC}"
    iptables -L OUTPUT -n --line-numbers 2>/dev/null | head -20
    echo ""
    echo -e "  ${BOLD}${YELLOW}FORWARD:${NC}"
    iptables -L FORWARD -n --line-numbers 2>/dev/null | head -10
    pause
}

add_port_rule() {
    print_title "AGREGAR REGLA DE PUERTO"
    read -rp "  Puerto: " port
    read -rp "  Protocolo (tcp/udp) [tcp]: " proto
    proto="${proto:-tcp}"

    if ! is_port "$port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    allow_port "$port" "$proto"
    msg_ok "Puerto $port/$proto permitido."
    pause
}

remove_port_rule() {
    print_title "ELIMINAR REGLA DE PUERTO"
    read -rp "  Puerto: " port
    read -rp "  Protocolo (tcp/udp) [tcp]: " proto
    proto="${proto:-tcp}"

    if ! is_port "$port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    block_port "$port" "$proto"
    msg_ok "Reglas del puerto $port/$proto eliminadas."
    pause
}

flush_iptables() {
    print_title "LIMPIAR TODAS LAS REGLAS IPTABLES"

    if ! confirm_action "${RED}ATENCION:${NC} Esto eliminara TODAS las reglas de iptables. Continuar?"; then
        return
    fi

    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    msg_ok "IPTables limpiado completamente."
    pause
}

save_iptables() {
    print_title "GUARDAR REGLAS IPTABLES"
    install_pkg "iptables-persistent"

    local save_path="/etc/iptables/rules.v4"
    mkdir -p "$(dirname "$save_path")"

    iptables-save > "$save_path"

    msg_ok "Reglas guardadas en $save_path."
    pause
}

firewall_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION DE FIREWALL ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar/Configurar UFW"
        echo -e "  ${GREEN}2)${NC} Ver reglas iptables"
        echo -e "  ${GREEN}3)${NC} Permitir puerto"
        echo -e "  ${GREEN}4)${NC} Bloquear puerto"
        echo -e "  ${GREEN}5)${NC} Limpiar reglas huerfanas"
        echo -e "  ${GREEN}6)${NC} Guardar reglas actuales"
        echo -e "  ${GREEN}7)${NC} Limpiar TODO (reset)"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_ufw ;;
            2) show_iptables ;;
            3) add_port_rule ;;
            4) remove_port_rule ;;
            5)
                print_title "LIMPIEZA HUERFANAS"
                clean_orphan_rules
                pause
                ;;
            6) save_iptables ;;
            7) flush_iptables ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    firewall_menu
fi
