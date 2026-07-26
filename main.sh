#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/banners.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/network.sh"

check_root

ensure_db_dir

main_menu() {
    while true; do
        print_banner
        echo ""
        echo -e "  ${BOLD}${YELLOW}--- MENU PRINCIPAL ---${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} ${BOLD}GESTION DE USUARIOS${NC}"
        echo -e "     Crear, listar, renovar, eliminar usuarios"
        echo ""
        echo -e "  ${GREEN}2)${NC} ${BOLD}PROTOCOLOS${NC}"
        echo -e "     SSH, Dropbear, Stunnel, WebSocket, V2Ray, BadVPN, Socks5, DNS"
        echo ""
        echo -e "  ${GREEN}3)${NC} ${BOLD}MONITOREO Y ESTADISTICAS${NC}"
        echo -e "     Estado del sistema, trafico, conexiones en tiempo real"
        echo ""
        echo -e "  ${GREEN}4)${NC} ${BOLD}LIMITES Y CONTROL${NC}"
        echo -e "     Limites de conexion, monitor automatico"
        echo ""
        echo -e "  ${GREEN}5)${NC} ${BOLD}BACKUP${NC}"
        echo -e "     Respaldar y restaurar usuarios"
        echo ""
        echo -e "  ${GREEN}6)${NC} ${BOLD}HERRAMIENTAS${NC}"
        echo -e "     Firewall, tuning, velocidad, limpieza"
        echo ""
        separator
        echo ""
        read -rp "  $(echo -e ${CYAN}Selecciona una opcion [0-6]: ${NC})" option
        echo ""

        case $option in
            1)
                bash "$SCRIPT_DIR/users/crud.sh"
                ;;
            2)
                protocols_menu
                ;;
            3)
                bash "$SCRIPT_DIR/users/monitor.sh"
                ;;
            4)
                bash "$SCRIPT_DIR/users/limits.sh"
                ;;
            5)
                bash "$SCRIPT_DIR/users/backup.sh"
                ;;
            6)
                tools_menu
                ;;
            0)
                clear
                echo -e "${GREEN}Gracias por usar el Panel de Administracion VPS.${NC}"
                exit 0
                ;;
            *)
                msg_error "Opcion invalida."
                sleep 1
                ;;
        esac
    done
}

protocols_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- PROTOCOLOS ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} SSH"
        echo -e "  ${GREEN}2)${NC} Dropbear"
        echo -e "  ${GREEN}3)${NC} Stunnel (SSL/TLS)"
        echo -e "  ${GREEN}4)${NC} WebSocket"
        echo -e "  ${GREEN}5)${NC} V2Ray / XRay"
        echo -e "  ${GREEN}6)${NC} BadVPN-UDPGW"
        echo -e "  ${GREEN}7)${NC} Socks5 Proxy"
        echo -e "  ${GREEN}8)${NC} SlowDNS / FastDNS"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) bash "$SCRIPT_DIR/protocols/ssh.sh" ;;
            2) bash "$SCRIPT_DIR/protocols/dropbear.sh" ;;
            3) bash "$SCRIPT_DIR/protocols/stunnel.sh" ;;
            4) bash "$SCRIPT_DIR/protocols/websocket.sh" ;;
            5) bash "$SCRIPT_DIR/protocols/v2ray.sh" ;;
            6) bash "$SCRIPT_DIR/protocols/badvpn.sh" ;;
            7) bash "$SCRIPT_DIR/protocols/socks5.sh" ;;
            8) bash "$SCRIPT_DIR/protocols/dns.sh" ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

tools_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- HERRAMIENTAS ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Limpiar reglas iptables huerfanas"
        echo -e "  ${GREEN}2)${NC} Activar IP forwarding + tuning kernel"
        echo -e "  ${GREEN}3)${NC} Test de velocidad (speedtest)"
        echo -e "  ${GREEN}4)${NC} Ver puertos en uso"
        echo -e "  ${GREEN}5)${NC} Ver procesos por usuario"
        echo -e "  ${GREEN}6)${NC} Reiniciar todos los servicios"
        echo -e "  ${GREEN}7)${NC} Actualizar sistema"
        echo -e "  ${GREEN}8)${NC} Cambiar zona horaria"
        echo -e "  ${GREEN}9)${NC} Gestion de firewall (UFW / iptables)"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1)
                print_title "LIMPIEZA IPTABLES"
                clean_orphan_rules
                pause
                ;;
            2)
                print_title "TUNING DEL SISTEMA"
                enable_ip_forward
                tune_kernel
                msg_ok "Kernel optimizado y forwarding activado."
                pause
                ;;
            3)
                print_title "TEST DE VELOCIDAD"
                if ! has_command speedtest-cli; then
                    msg_info "Instalando speedtest-cli..."
                    apt-get install -y speedtest-cli &>/dev/null || {
                        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash &>/dev/null
                        apt-get install -y speedtest &>/dev/null
                    }
                fi
                echo ""
                speedtest-cli --simple 2>/dev/null || speedtest 2>/dev/null || msg_error "No se pudo ejecutar speedtest."
                pause
                ;;
            4)
                print_title "PUERTOS EN USO"
                list_open_ports
                pause
                ;;
            5)
                print_title "PROCESOS POR USUARIO"
                printf "  ${BOLD}%-12s %-10s %s${NC}\n" "Usuario" "Procesos" "Conexiones"
                separator
                while IFS=: read -r user pass expiry max_conn traffic created status; do
                    local procs conns
                    procs=$(user_processes "$user")
                    conns=$(user_connections_count "$user")
                    printf "  %-12s %-10s %s\n" "$user" "$procs" "$conns"
                done < "$USERS_DB" 2>/dev/null
                separator
                pause
                ;;
            6)
                print_title "REINICIANDO SERVICIOS"
                local services=("ssh" "sshd" "dropbear" "stunnel4" "ws-proxy" "xray" "badvpn-udpgw" "socks5" "slowdns" "fastdns")
                for svc in "${services[@]}"; do
                    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                        msg_info "Reiniciando $svc..."
                        systemctl restart "$svc" 2>/dev/null && msg_ok "$svc" || msg_warn "$svc fallo"
                    fi
                done
                pause
                ;;
            7)
                print_title "ACTUALIZANDO SISTEMA"
                apt-get update -y && apt-get upgrade -y
                msg_ok "Sistema actualizado."
                pause
                ;;
            8)
                print_title "CAMBIAR ZONA HORARIA"
                timedatectl list-timezones | grep -i America
                echo ""
                read -rp "  Zona horaria (ej: America/Mexico_City): " tz
                [[ -n "$tz" ]] && timedatectl set-timezone "$tz" 2>/dev/null
                msg_ok "Zona horaria: $(timedatectl show --property=Timezone --value)"
                pause
                ;;
            9)
                bash "$SCRIPT_DIR/firewall/iptables.sh"
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

main_menu
