#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

set_user_limit() {
    print_title "CONFIGURAR LIMITE DE CONEXIONES"
    check_root

    if [[ ! -s "$USERS_DB" ]]; then
        msg_warn "No hay usuarios registrados."
        pause
        return
    fi

    list_users_brief
    echo ""
    read -rp "  Usuario: " username

    if ! grep -q "^$username:" "$USERS_DB"; then
        msg_error "Usuario no encontrado."
        pause
        return 1
    fi

    local old_data old_max
    old_data=$(grep "^$username:" "$USERS_DB")
    old_max=$(echo "$old_data" | cut -d: -f4)

    echo ""
    msg_info "Limite actual: $old_max conexiones"
    echo ""

    local new_max
    read -rp "  Nuevo limite de conexiones: " new_max

    if ! is_number "$new_max" || [[ "$new_max" -lt 1 ]]; then
        msg_error "Numero invalido."
        pause
        return 1
    fi

    local new_data
    new_data=$(echo "$old_data" | awk -F: -v n="$new_max" 'BEGIN{OFS=":"}{$4=n;print}')
    sed -i "/^$username:/c\\$new_data" "$USERS_DB"

    msg_ok "Limite actualizado: $new_max conexiones para $username."
    pause
}

set_global_limit() {
    print_title "LIMITE GLOBAL DE CONEXIONES"
    check_root

    echo ""
    echo -e "  Limite actual: ${YELLOW}${MAX_CONNECTIONS_PER_USER:-2}${NC}"
    echo ""

    local new_global
    read -rp "  Nuevo limite global: " new_global

    if ! is_number "$new_global" || [[ "$new_global" -lt 1 ]]; then
        msg_error "Numero invalido."
        pause
        return 1
    fi

    MAX_CONNECTIONS_PER_USER=$new_global

    # Aplicar a todos los usuarios existentes
    while IFS=: read -r user pass expiry max_conn traffic created status; do
        local new_data
        new_data=$(echo "$user:$pass:$expiry:$new_global:$traffic:$created:$status")
        sed -i "/^$user:/c\\$new_data" "$USERS_DB"
    done < "$USERS_DB"

    msg_ok "Limite global actualizado a $new_global conexiones."
    pause
}

install_limit_service() {
    print_title "INSTALAR MONITOR DE LIMITES"
    check_root

    install_pkg "bc"

    local service_file="/etc/systemd/system/limit-ssh.service"
    local script_file="/opt/script-cgh/limit_monitor.sh"

    cat > "$script_file" << 'LIMEOF'
#!/bin/bash
USERS_DB="/etc/script-cgh/usuarios.db"
[[ ! -f "$USERS_DB" ]] && exit 0

while IFS=: read -r user pass expiry max_conn traffic created status; do
    [[ "$status" == "bloqueado" ]] && continue

    conn_count=$(ss -tnp | grep -c "uid=$(id -u "$user" 2>/dev/null)" 2>/dev/null)
    conn_count="${conn_count:-0}"

    if [[ "$conn_count" -gt "$max_conn" ]]; then
        excess=$((conn_count - max_conn))
        oldest_pids=$(ss -tnp | grep "uid=$(id -u "$user" 2>/dev/null)" | head -n "$excess" | grep -oP 'pid=\K[0-9]+' | head -n "$excess" 2>/dev/null)
        for pid in $oldest_pids; do
            kill "$pid" 2>/dev/null
        done
    fi
done < "$USERS_DB"
LIMEOF

    chmod +x "$script_file"

    cat > "$service_file" << EOF
[Unit]
Description=Monitor de Limites SSH
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $script_file
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable limit-ssh &>/dev/null
    systemctl start limit-ssh &>/dev/null

    msg_ok "Monitor de limites instalado y ejecutandose."
    pause
}

install_kill_script() {
    print_title "INSTALAR SCRIPT DE DESCONEXION"
    check_root

    local kill_script="/opt/script-cgh/kill_user.sh"
    cat > "$kill_script" << 'KILLEOF'
#!/bin/bash
# Uso: kill_user.sh <usuario>
USER="$1"
if [[ -z "$USER" ]]; then
    echo "Uso: $0 <usuario>"
    exit 1
fi

echo "Desconectando todas las sesiones de $USER..."
pkill -u "$USER" 2>/dev/null

pids=$(ss -tnp | grep "uid=$(id -u "$USER" 2>/dev/null)" 2>/dev/null | grep -oP 'pid=\K[0-9]+')
for pid in $pids; do
    kill -9 "$pid" 2>/dev/null
done

echo "Usuario $USER desconectado."
KILLEOF

    chmod +x "$kill_script"
    ln -sf "$kill_script" /usr/local/bin/killuser 2>/dev/null

    msg_ok "Script instalado. Uso: killuser <nombre>"
    pause
}

limits_menu() {
    while true; do
        ensure_db_dir
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION DE LIMITES ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Limite por usuario"
        echo -e "  ${GREEN}2)${NC} Limite global"
        echo -e "  ${GREEN}3)${NC} Instalar monitor automatico"
        echo -e "  ${GREEN}4)${NC} Instalar script killuser"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) set_user_limit ;;
            2) set_global_limit ;;
            3) install_limit_service ;;
            4) install_kill_script ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    limits_menu
fi
