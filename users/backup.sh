#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

backup_users() {
    print_title "BACKUP DE USUARIOS"
    check_root
    ensure_db_dir

    local backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    msg_info "Creando backup..."

    local temp_dir
    temp_dir=$(mktemp -d)

    cp "$USERS_DB" "$temp_dir/usuarios.db" 2>/dev/null

    if [[ -f /etc/passwd ]]; then
        while IFS=: read -r user _ _ _ _ _ _; do
            if grep -q "^$user:" "$USERS_DB" 2>/dev/null; then
                grep "^$user:" /etc/shadow >> "$temp_dir/shadow_backup" 2>/dev/null
            fi
        done < "$USERS_DB"
    fi

    tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
    rm -rf "$temp_dir"

    if [[ -f "$backup_file" ]]; then
        local size
        size=$(du -h "$backup_file" | cut -f1)
        msg_ok "Backup creado: $backup_file ($size)"
    else
        msg_error "Error al crear backup."
    fi

    pause
}

restore_backup() {
    print_title "RESTAURAR BACKUP"
    check_root

    local backups=()
    if [[ -d "$BACKUP_DIR" ]]; then
        while IFS= read -r -d '' file; do
            backups+=("$file")
        done < <(find "$BACKUP_DIR" -name "backup_*.tar.gz" -print0 | sort -rz)
    fi

    if [[ ${#backups[@]} -eq 0 ]]; then
        msg_warn "No se encontraron backups en $BACKUP_DIR."
        pause
        return
    fi

    echo ""
    local i=1
    for bk in "${backups[@]}"; do
        local name size
        name=$(basename "$bk")
        size=$(du -h "$bk" | cut -f1)
        echo -e "  ${GREEN}$i)${NC} $name ($size)"
        ((i++))
    done
    echo ""

    read -rp "  Selecciona backup a restaurar [1-${#backups[@]}]: " choice

    if ! is_number "$choice" || ((choice < 1 || choice > ${#backups[@]})); then
        msg_error "Opcion invalida."
        pause
        return
    fi

    local selected="${backups[$((choice - 1))]}"

    if ! confirm_action "Restaurar backup $(basename "$selected")? Se sobreescribiran los datos actuales."; then
        return
    fi

    local temp_dir
    temp_dir=$(mktemp -d)

    tar -xzf "$selected" -C "$temp_dir" 2>/dev/null

    if [[ -f "$temp_dir/usuarios.db" ]]; then
        cp "$temp_dir/usuarios.db" "$USERS_DB"
        msg_ok "Base de datos de usuarios restaurada."
    fi

    if [[ -f "$temp_dir/shadow_backup" ]]; then
        while IFS=: read -r user pass rest; do
            if grep -q "^$user:" /etc/passwd 2>/dev/null; then
                usermod -p "$pass" "$user" 2>/dev/null
            else
                useradd -M -s /bin/false -p "$pass" "$user" 2>/dev/null
            fi
        done < "$temp_dir/shadow_backup"
        msg_ok "Passwords restaurados."
    fi

    rm -rf "$temp_dir"
    msg_ok "Backup restaurado exitosamente."
    pause
}

auto_backup_setup() {
    print_title "CONFIGURAR BACKUP AUTOMATICO"

    local cron_line="0 4 * * * /bin/bash /opt/script-cgh/users/backup.sh --auto > /dev/null 2>&1"

    if confirm_action "Programar backup diario a las 4:00 AM?"; then
        (crontab -l 2>/dev/null | grep -v "backup.sh"; echo "$cron_line") | crontab -
        msg_ok "Backup automatico configurado."
    fi
    pause
}

backup_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- BACKUP Y RESTAURACION ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Crear backup ahora"
        echo -e "  ${GREEN}2)${NC} Restaurar backup"
        echo -e "  ${GREEN}3)${NC} Configurar backup automatico"
        echo -e "  ${GREEN}4)${NC} Ver backups disponibles"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) backup_users ;;
            2) restore_backup ;;
            3) auto_backup_setup ;;
            4)
                print_title "BACKUPS DISPONIBLES"
                if [[ -d "$BACKUP_DIR" ]]; then
                    find "$BACKUP_DIR" -name "backup_*.tar.gz" -printf "%f (%s bytes)\n" | sort -r | while read -r line; do
                        echo -e "  ${CYAN}$line${NC}"
                    done
                else
                    msg_warn "No hay backups."
                fi
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$1" == "--auto" ]]; then
        ensure_db_dir
        BACKUP_DIR="/etc/script-cgh/backups"
        USERS_DB="/etc/script-cgh/usuarios.db"
        backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        temp_dir=$(mktemp -d)
        cp "$USERS_DB" "$temp_dir/usuarios.db" 2>/dev/null
        tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
        rm -rf "$temp_dir"
        find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +30 -delete 2>/dev/null
    else
        backup_menu
    fi
fi
