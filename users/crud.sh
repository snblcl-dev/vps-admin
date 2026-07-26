#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

create_user() {
    print_title "CREAR USUARIO"
    check_root

    msg_neutral "== NUEVO USUARIO SSH =="
    echo ""
    read -rp "  Nombre de usuario: " username

    if [[ -z "$username" ]]; then
        msg_error "Nombre de usuario requerido."
        pause
        return 1
    fi

    if ! is_username "$username"; then
        msg_error "Nombre invalido. Use letras, numeros, guiones (3-32 chars)."
        pause
        return 1
    fi

    if grep -q "^$username:" "$USERS_DB" 2>/dev/null; then
        msg_error "El usuario '$username' ya existe."
        pause
        return 1
    fi

    if id "$username" &>/dev/null; then
        msg_error "El usuario del sistema '$username' ya existe."
        pause
        return 1
    fi

    local password
    read -rp "  Password (dejar vacio para generar): " password
    if [[ -z "$password" ]]; then
        password=$(random_pass 12)
        msg_info "Password generado: $password"
    fi

    local days
    read -rp "  Dias de validez [30]: " days
    days="${days:-30}"
    if ! is_number "$days"; then
        msg_error "Numero de dias invalido."
        pause
        return 1
    fi

    local expiry_date
    expiry_date=$(calc_expiry "$days")

    local max_conn
    read -rp "  Maximo de conexiones simultaneas [2]: " max_conn
    max_conn="${max_conn:-2}"
    if ! is_number "$max_conn"; then
        msg_error "Numero de conexiones invalido."
        pause
        return 1
    fi

    separator
    echo -e "  ${BOLD}Resumen:${NC}"
    echo -e "  Usuario:    ${GREEN}$username${NC}"
    echo -e "  Password:   ${GREEN}$password${NC}"
    echo -e "  Expira:     ${YELLOW}$expiry_date${NC}"
    echo -e "  Max Conn:   ${CYAN}$max_conn${NC}"
    separator

    if ! confirm_action "Crear usuario?"; then
        msg_info "Operacion cancelada."
        return 0
    fi

    # Crear usuario del sistema
    useradd -M -s /bin/false "$username" 2>/dev/null
    echo "$username:$password" | chpasswd

    # Guardar en la base de datos
    echo "$username:$password:$expiry_date:$max_conn:0:$(date +%Y-%m-%d):activo" >> "$USERS_DB"

    msg_ok "Usuario '$username' creado exitosamente."
    echo ""
    echo -e "  ${BOLD}Datos de conexion:${NC}"
    echo -e "  IP:      ${CYAN}$(get_public_ip)${NC}"
    echo -e "  Usuario: ${GREEN}$username${NC}"
    echo -e "  Clave:   ${GREEN}$password${NC}"
    echo -e "  Expira:  ${YELLOW}$expiry_date${NC}"
    echo ""
    pause
}

delete_user() {
    print_title "ELIMINAR USUARIO"
    check_root

    list_users_brief

    echo ""
    read -rp "  Nombre de usuario a eliminar: " username

    if [[ -z "$username" ]]; then
        msg_error "Debe especificar un usuario."
        pause
        return 1
    fi

    if ! grep -q "^$username:" "$USERS_DB" 2>/dev/null; then
        msg_error "Usuario '$username' no encontrado."
        pause
        return 1
    fi

    local user_data
    user_data=$(grep "^$username:" "$USERS_DB")

    echo -e "\n  ${RED}${BOLD}ATENCION: Se eliminara el usuario '$username'${NC}\n"

    if ! confirm_action "Continuar?"; then
        msg_info "Operacion cancelada."
        return 0
    fi

    # Matar procesos del usuario
    pkill -u "$username" 2>/dev/null

    # Eliminar usuario del sistema
    userdel -r "$username" 2>/dev/null

    # Eliminar de la base de datos
    sed -i "/^$username:/d" "$USERS_DB"

    msg_ok "Usuario '$username' eliminado."
    pause
}

renew_user() {
    print_title "RENOVAR USUARIO"
    check_root

    list_users_brief

    echo ""
    read -rp "  Nombre de usuario a renovar: " username

    if ! grep -q "^$username:" "$USERS_DB" 2>/dev/null; then
        msg_error "Usuario no encontrado."
        pause
        return 1
    fi

    local days
    read -rp "  Dias adicionales [30]: " days
    days="${days:-30}"

    local old_data new_data expiry_date
    old_data=$(grep "^$username:" "$USERS_DB")
    expiry_date=$(calc_expiry "$days")
    new_data=$(echo "$old_data" | awk -F: -v e="$expiry_date" -v s="$(date +%Y-%m-%d)" 'BEGIN{OFS=":"}{$3=e;$6=s;print}')

    sed -i "/^$username:/c\\$new_data" "$USERS_DB"

    msg_ok "Usuario '$username' renovado hasta $expiry_date."
    pause
}

change_password() {
    print_title "CAMBIAR PASSWORD"
    check_root

    list_users_brief

    echo ""
    read -rp "  Nombre de usuario: " username

    if ! grep -q "^$username:" "$USERS_DB" 2>/dev/null; then
        msg_error "Usuario no encontrado."
        pause
        return 1
    fi

    local new_pass
    read -rp "  Nuevo password (vacío = generar): " new_pass
    if [[ -z "$new_pass" ]]; then
        new_pass=$(random_pass 12)
    fi

    echo "$username:$new_pass" | chpasswd 2>/dev/null

    local old_data new_data
    old_data=$(grep "^$username:" "$USERS_DB")
    new_data=$(echo "$old_data" | awk -F: -v p="$new_pass" 'BEGIN{OFS=":"}{$2=p;print}')

    sed -i "/^$username:/c\\$new_data" "$USERS_DB"

    msg_ok "Password cambiado: $new_pass"
    pause
}

list_users_brief() {
    local db="$USERS_DB"
    if [[ ! -s "$db" ]]; then
        msg_warn "No hay usuarios registrados."
        return
    fi

    echo ""
    printf "  ${BOLD}%-15s %-12s %-15s %s${NC}\n" "Usuario" "Expira" "Estado" "Conn"
    separator
    while IFS=: read -r user pass expiry max_conn traffic created status; do
        local state="activo"
        local state_color="$GREEN"
        if is_expired "$expiry"; then
            state="expirado"
            state_color="$RED"
        fi
        if [[ "$status" == "bloqueado" ]]; then
            state="bloqueado"
            state_color="$YELLOW"
        fi
        printf "  %-15s %-12s ${state_color}%-15s${NC} %s\n" "$user" "$expiry" "$state" "$max_conn"
    done < "$db"
    separator
}

list_users_detail() {
    print_title "LISTA DE USUARIOS (DETALLE)"
    if [[ ! -s "$USERS_DB" ]]; then
        msg_warn "No hay usuarios registrados."
        pause
        return
    fi

    while IFS=: read -r user pass expiry max_conn traffic created status; do
        local state="ACTIVO"
        local state_color="$GREEN"
        local days_left
        days_left=$(days_remaining "$expiry")
        if [[ "$days_left" -lt 0 ]]; then
            state="EXPIRADO"
            state_color="$RED"
        fi
        if [[ "$status" == "bloqueado" ]]; then
            state="BLOQUEADO"
            state_color="$YELLOW"
        fi

        local conn_count
        conn_count=$(user_connections_count "$user")

        echo -e "  ${BOLD}${CYAN}$user${NC}"
        echo -e "    Password: ${GREEN}$pass${NC}"
        echo -e "    Expira:   ${YELLOW}$expiry${NC} (${days_left} dias)"
        echo -e "    Estado:   ${state_color}$state${NC}"
        echo -e "    Max Conn: $max_conn | Activas: $conn_count"
        echo -e "    Trafico:  $(human_bytes "$traffic")"
        echo -e "    Creado:   $created"
        separator
    done < "$USERS_DB"
    pause
}

block_user() {
    print_title "BLOQUEAR USUARIO"
    list_users_brief
    echo ""
    read -rp "  Usuario a bloquear: " username

    if ! grep -q "^$username:" "$USERS_DB"; then
        msg_error "Usuario no encontrado."
        pause
        return 1
    fi

    pkill -u "$username" 2>/dev/null
    passwd -l "$username" &>/dev/null
    sed -i "/^$username:/s/:activo/:bloqueado/" "$USERS_DB" 2>/dev/null
    sed -i "/^$username:/s/:expirado/:bloqueado/" "$USERS_DB" 2>/dev/null

    msg_ok "Usuario '$username' bloqueado."
    pause
}

unblock_user() {
    print_title "DESBLOQUEAR USUARIO"
    list_users_brief
    echo ""
    read -rp "  Usuario a desbloquear: " username

    if ! grep -q "^$username:" "$USERS_DB"; then
        msg_error "Usuario no encontrado."
        pause
        return 1
    fi

    passwd -u "$username" &>/dev/null
    sed -i "/^$username:/s/:bloqueado/:activo/" "$USERS_DB" 2>/dev/null

    msg_ok "Usuario '$username' desbloqueado."
    pause
}

purge_expired() {
    print_title "LIMPIAR USUARIOS EXPIRADOS"
    check_root

    local expired_list=()
    while IFS=: read -r user expiry; do
        if is_expired "$expiry"; then
            expired_list+=("$user")
        fi
    done < "$USERS_DB"

    if [[ ${#expired_list[@]} -eq 0 ]]; then
        msg_info "No hay usuarios expirados."
        pause
        return
    fi

    echo ""
    for user in "${expired_list[@]}"; do
        echo -e "  ${RED}$user${NC}"
    done
    echo ""

    if confirm_action "Eliminar ${#expired_list[@]} usuarios expirados?"; then
        for user in "${expired_list[@]}"; do
            pkill -u "$user" 2>/dev/null
            userdel -r "$user" 2>/dev/null
            sed -i "/^$user:/d" "$USERS_DB"
        done
        msg_ok "Usuarios expirados eliminados."
    fi
    pause
}

users_menu() {
    while true; do
        ensure_db_dir
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION DE USUARIOS ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Crear usuario"
        echo -e "  ${GREEN}2)${NC} Listar usuarios (resumen)"
        echo -e "  ${GREEN}3)${NC} Listar usuarios (detalle)"
        echo -e "  ${GREEN}4)${NC} Renovar usuario"
        echo -e "  ${GREEN}5)${NC} Cambiar password"
        echo -e "  ${GREEN}6)${NC} Bloquear usuario"
        echo -e "  ${GREEN}7)${NC} Desbloquear usuario"
        echo -e "  ${GREEN}8)${NC} Eliminar usuario"
        echo -e "  ${GREEN}9)${NC} Limpiar expirados"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) create_user ;;
            2) print_title "USUARIOS"; list_users_brief; pause ;;
            3) list_users_detail ;;
            4) renew_user ;;
            5) change_password ;;
            6) block_user ;;
            7) unblock_user ;;
            8) delete_user ;;
            9) purge_expired ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ensure_db_dir
    users_menu
fi
