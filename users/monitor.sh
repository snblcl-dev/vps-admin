#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

monitor_realtime() {
    print_title "MONITOR EN TIEMPO REAL"

    local refresh="${1:-2}"
    msg_info "Actualizando cada ${refresh}s. Ctrl+C para salir."
    echo ""
    separator
    printf "  ${BOLD}%-12s %-8s %s${NC}\n" "Usuario" "Conn" "Estado"
    separator

    while true; do
        local output=""
        if [[ -s "$USERS_DB" ]]; then
            while IFS=: read -r user pass expiry max_conn traffic created status; do
                local conn_count
                conn_count=$(user_connections_count "$user")

                local state="ACTIVO"
                if is_expired "$expiry"; then state="EXPIRADO"; fi
                if [[ "$status" == "bloqueado" ]]; then state="BLOQUEADO"; fi

                local color="$GREEN"
                [[ "$state" != "ACTIVO" ]] && color="$RED"
                [[ "$conn_count" -gt "$max_conn" ]] && color="$YELLOW"

                output+=$(printf "  ${color}%-12s %-8s %s${NC}\n" "$user" "$conn_count/$max_conn" "$state")
            done < "$USERS_DB"
        fi

        if [[ -z "$output" ]]; then
            output="  ${GRAY}Sin usuarios registrados${NC}"
        fi

        clear
        print_title "MONITOR EN TIEMPO REAL"
        echo ""
        separator
        printf "  ${BOLD}%-12s %-8s %s${NC}\n" "Usuario" "Conn" "Estado"
        separator
        echo -e "$output"
        separator
        echo -e "  ${GRAY}Ctrl+C para salir${NC}"
        sleep "$refresh"
    done
}

show_system_status() {
    print_title "ESTADO DEL SISTEMA"

    # Sistema
    echo -e "  ${BOLD}${YELLOW}--- SISTEMA ---${NC}"
    echo -e "  Hostname:  $(hostname)"
    echo -e "  SO:        $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo -e "  Kernel:    $(uname -r)"
    echo -e "  Uptime:    $(uptime -p | sed 's/up //')"
    echo -e "  Load:      $(uptime | awk -F'load average:' '{print $NF}')"
    echo ""

    # CPU
    echo -e "  ${BOLD}${YELLOW}--- CPU ---${NC}"
    echo -e "  Modelo:    $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
    echo -e "  Nucleos:   $(nproc)"
    echo -e "  Uso:       $(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4"%"}')"
    echo ""

    # Memoria
    echo -e "  ${BOLD}${YELLOW}--- MEMORIA ---${NC}"
    local mem_total mem_used mem_percent
    read -r mem_total mem_used mem_percent <<< $(free -m | awk '/Mem:/ {print $2, $3, $3/$2*100}')
    echo -e "  Total:     ${mem_total} MB"
    echo -e "  Usada:     ${mem_used} MB (${mem_percent}%)"
    echo ""

    # Disco
    echo -e "  ${BOLD}${YELLOW}--- DISCO ---${NC}"
    df -h / | awk 'NR==2 {print "  Total: "$2" | Usado: "$3" ("$5") | Libre: "$4}'
    echo ""

    # Red
    echo -e "  ${BOLD}${YELLOW}--- RED ---${NC}"
    echo -e "  IP Publica: $(get_public_ip)"
    echo -e "  IP Local:   $(get_local_ip)"
    echo -e "  Interfaz:   $(get_main_iface)"
    echo ""

    # Servicios
    echo -e "  ${BOLD}${YELLOW}--- SERVICIOS ---${NC}"
    local services=("ssh" "dropbear" "stunnel4" "v2ray" "xray" "badvpn-udpgw")
    for svc in "${services[@]}"; do
        local state="$RED detenido ${NC}"
        if check_service "$svc" 2>/dev/null; then
            state="${GREEN}activo   ${NC}"
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            state="${YELLOW}fallo    ${NC}"
        fi
        printf "  %-15s %b\n" "$svc" "$state"
    done
    echo ""

    # Usuarios
    echo -e "  ${BOLD}${YELLOW}--- USUARIOS ---${NC}"
    if [[ -s "$USERS_DB" ]]; then
        local total=0 active=0 expired=0 blocked=0
        while IFS=: read -r user pass expiry max_conn traffic created status; do
            ((total++))
            if is_expired "$expiry"; then ((expired++)); fi
            if [[ "$status" == "bloqueado" ]]; then ((blocked++)); fi
        done < "$USERS_DB"
        ((active = total - expired - blocked))
        echo -e "  Total: $total | Activos: ${GREEN}$active${NC} | Expirados: ${RED}$expired${NC} | Bloqueados: ${YELLOW}$blocked${NC}"
    else
        echo -e "  ${GRAY}Sin usuarios${NC}"
    fi

    # Puertos abiertos
    echo ""
    echo -e "  ${BOLD}${YELLOW}--- PUERTOS ABIERTOS ---${NC}"
    list_open_ports | head -20 | while read -r line; do
        echo -e "  $line"
    done

    pause
}

traffic_stats() {
    print_title "ESTADISTICAS DE TRAFICO"
    check_root

    if ! has_command vnstat; then
        msg_info "Instalando vnstat..."
        apt-get install -y vnstat &>/dev/null
        systemctl enable vnstat &>/dev/null
        systemctl start vnstat &>/dev/null
    fi

    sleep 2

    separator
    echo -e "  ${BOLD}Trafico de red (vnstat):${NC}"
    separator
    vnstat -m 2>/dev/null || vnstat 2>/dev/null
    separator

    echo ""
    echo -e "  ${BOLD}Trafico por usuario:${NC}"
    separator
    printf "  ${BOLD}%-12s %-12s %-10s${NC}\n" "Usuario" "Trafico" "Conn"
    separator

    if [[ -s "$USERS_DB" ]]; then
        while IFS=: read -r user pass expiry max_conn traffic created status; do
            local conn_count
            conn_count=$(user_connections_count "$user")
            printf "  %-12s %-12s %-10s\n" "$user" "$(human_bytes "$traffic")" "$conn_count"
        done < "$USERS_DB"
    fi
    separator

    pause
}

monitor_menu() {
    while true; do
        ensure_db_dir
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- MONITOREO Y ESTADISTICAS ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Monitor en tiempo real"
        echo -e "  ${GREEN}2)${NC} Estado del sistema"
        echo -e "  ${GREEN}3)${NC} Estadisticas de trafico"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) monitor_realtime ;;
            2) show_system_status ;;
            3) traffic_stats ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    monitor_menu
fi
