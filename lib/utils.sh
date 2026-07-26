#!/bin/bash

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Este script debe ejecutarse como root."
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    else
        msg_error "No se pudo detectar el sistema operativo."
        exit 1
    fi

    case "$OS_NAME" in
        ubuntu|debian)
            if [[ "$OS_VERSION" < "22.04" ]] && [[ "$OS_NAME" == "ubuntu" ]]; then
                msg_warn "Ubuntu $OS_VERSION detectado. Se recomienda 22.04+."
            fi
            ;;
        *)
            msg_error "SO no soportado: $OS_NAME"
            exit 1
            ;;
    esac
}

# Obtener IP publica
get_public_ip() {
    local ip
    ip=$(curl -s4 icanhazip.com 2>/dev/null || \
         curl -s4 ipinfo.io/ip 2>/dev/null || \
         curl -s4 ifconfig.me 2>/dev/null)
    echo "$ip"
}

# Obtener IP local
get_local_ip() {
    local ip
    ip=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
    echo "${ip:-127.0.0.1}"
}

is_ipv4() {
    local ip="$1"
    local IFS='.'
    local parts=($ip)
    [[ ${#parts[@]} -eq 4 ]] || return 1
    for part in "${parts[@]}"; do
        [[ $part =~ ^[0-9]+$ ]] || return 1
        ((part >= 0 && part <= 255)) || return 1
    done
    return 0
}

is_port() {
    local port="$1"
    [[ $port =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_date() {
    local date_str="$1"
    date -d "$date_str" "+%Y-%m-%d" &>/dev/null
}

is_username() {
    local user="$1"
    [[ "$user" =~ ^[a-zA-Z][a-zA-Z0-9_-]{2,31}$ ]]
}

random_str() {
    local length="${1:-8}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

random_pass() {
    local length="${1:-12}"
    tr -dc 'a-zA-Z0-9!@#$%&*' < /dev/urandom | head -c "$length"
}

random_port() {
    shuf -i 10000-65535 -n 1
}

# Fecha de expiracion
calc_expiry() {
    local days="$1"
    date -d "+$days days" "+%Y-%m-%d"
}

is_expired() {
    local expiry_date="$1"
    local now
    now=$(date "+%Y-%m-%d")
    [[ "$expiry_date" < "$now" ]]
}

days_remaining() {
    local expiry_date="$1"
    local now ep exp

    ep=$(date -d "$expiry_date" "+%s" 2>/dev/null) || return 0
    now=$(date "+%s")
    diff=$(( (ep - now) / 86400 ))
    echo "$diff"
}

check_pkg() {
    dpkg -l "$1" &>/dev/null
}

install_pkg() {
    local pkg="$1"
    if ! check_pkg "$pkg"; then
        msg_info "Instalando $pkg..."
        apt-get install -y "$pkg" &>/dev/null
        if check_pkg "$pkg"; then
            msg_ok "$pkg instalado."
        else
            msg_error "No se pudo instalar $pkg."
            return 1
        fi
    fi
}

check_service() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

enable_service() {
    systemctl enable "$1" &>/dev/null
    systemctl restart "$1" &>/dev/null
    if check_service "$1"; then
        msg_ok "Servicio $1 activo."
    else
        msg_error "Servicio $1 no pudo iniciarse."
    fi
}

# Puerto en uso
port_in_use() {
    ss -tuln | grep -q ":$1 "
}

# PID del proceso escuchando en un puerto
pid_on_port() {
    ss -tlnp | grep ":$1 " | grep -oP 'pid=\K[0-9]+' | head -1
}

# Bytes a formato humano
human_bytes() {
    local bytes="$1"
    if ((bytes >= 1073741824)); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    elif ((bytes >= 1048576)); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    elif ((bytes >= 1024)); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    else
        echo "${bytes} B"
    fi
}

# Trafico del usuario por NetHogs o iptables
get_user_traffic() {
    local user="$1"
    local traffic=0
    if command -v vnstat &>/dev/null; then
        traffic=$(vnstat --oneline -i eth0 2>/dev/null | cut -d';' -f13)
    fi
    echo "${traffic:-0}"
}

# Procesos del usuario
user_processes() {
    local user="$1"
    ps -u "$user" --no-headers 2>/dev/null | wc -l
}

# Conexiones activas de un usuario
user_connections_count() {
    local user="$1"
    ss -tnp | grep "uid=$(id -u "$user" 2>/dev/null)" 2>/dev/null | wc -l
}

# Verificar si un comando existe
has_command() {
    command -v "$1" &>/dev/null
}

# Archivo de base de datos de usuarios
USERS_DB="/etc/script-cgh/usuarios.db"
BACKUP_DIR="/etc/script-cgh/backups"
INSTALL_DIR="/opt/script-cgh"

ensure_db_dir() {
    mkdir -p "$(dirname "$USERS_DB")"
    mkdir -p "$BACKUP_DIR"
    touch "$USERS_DB" 2>/dev/null
}
