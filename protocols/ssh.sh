#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

SSHD_CONFIG="/etc/ssh/sshd_config"

install_ssh() {
    print_title "INSTALAR / RECONFIGURAR SSH"
    check_root

    install_pkg "openssh-server"

    read -rp "  Puerto SSH [22]: " ssh_port
    ssh_port="${ssh_port:-22}"

    if ! is_port "$ssh_port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    if port_in_use "$ssh_port" && ! pid_on_port "$ssh_port" | xargs -I{} readlink -f /proc/{}/exe 2>/dev/null | grep -q sshd; then
        msg_warn "El puerto $ssh_port esta en uso por otro servicio."
        if ! confirm_action "Usar de todas formas?"; then
            return 1
        fi
    fi

    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null

    cat > "$SSHD_CONFIG" << EOF
Port $ssh_port
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 120
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:100
Banner /etc/ssh/banner
EOF

    cat > /etc/ssh/banner << 'SSHBANNER'
=============================================
         ACCESO RESTRINGIDO
    Todas las conexiones son monitoreadas
=============================================
SSHBANNER

    allow_port "$ssh_port" "tcp"
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

    if check_service sshd || check_service ssh; then
        msg_ok "SSH configurado en puerto $ssh_port."
    else
        msg_error "Error al reiniciar SSH."
    fi
    pause
}

ssh_status() {
    print_title "ESTADO DE SSH"

    if check_service sshd || check_service ssh; then
        msg_ok "SSH esta activo."
    else
        msg_error "SSH no esta activo."
    fi

    echo ""
    echo -e "  ${BOLD}Configuracion actual:${NC}"
    grep -E "^Port |^PermitRootLogin |^PasswordAuthentication " "$SSHD_CONFIG" 2>/dev/null | while read -r line; do
        echo -e "  $line"
    done

    echo ""
    echo -e "  ${BOLD}Conexiones activas:${NC}"
    ss -tnp | grep sshd | wc -l | xargs echo "  Total:"

    pause
}

ssh_toggle_root() {
    print_title "PERMITIR/PROHIBIR ROOT LOGIN"
    check_root

    local current
    current=$(grep "^PermitRootLogin" "$SSHD_CONFIG" | awk '{print $2}')
    echo -e "  Configuracion actual: ${YELLOW}$current${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Permitir root login"
    echo -e "  ${GREEN}2)${NC} Prohibir root login"
    echo ""
    read -rp "  Opcion: " opt

    case $opt in
        1) sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG" ;;
        2) sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG" ;;
        *) msg_error "Opcion invalida."; pause; return ;;
    esac

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    msg_ok "Configuracion actualizada."
    pause
}

ssh_banner_edit() {
    print_title "EDITAR BANNER SSH"
    msg_info "Editando /etc/ssh/banner..."
    if has_command nano; then
        nano /etc/ssh/banner
    elif has_command vim; then
        vim /etc/ssh/banner
    else
        install_pkg "nano"
        nano /etc/ssh/banner
    fi
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    msg_ok "Banner actualizado."
    pause
}

ssh_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION SSH ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar/Reconfigurar SSH"
        echo -e "  ${GREEN}2)${NC} Ver estado SSH"
        echo -e "  ${GREEN}3)${NC} Cambiar puerto SSH"
        echo -e "  ${GREEN}4)${NC} Configurar root login"
        echo -e "  ${GREEN}5)${NC} Editar banner SSH"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_ssh ;;
            2) ssh_status ;;
            3)
                read -rp "  Nuevo puerto: " new_port
                if is_port "$new_port"; then
                    sed -i "s/^Port .*/Port $new_port/" "$SSHD_CONFIG" 2>/dev/null
                    echo "Port $new_port" >> "$SSHD_CONFIG"
                    allow_port "$new_port" "tcp"
                    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
                    msg_ok "Puerto SSH cambiado a $new_port."
                else
                    msg_error "Puerto invalido."
                fi
                pause
                ;;
            4) ssh_toggle_root ;;
            5) ssh_banner_edit ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ssh_menu
fi
