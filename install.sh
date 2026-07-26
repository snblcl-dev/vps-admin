#!/bin/bash

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/script-cgh"
DB_DIR="/etc/script-cgh"
GITHUB_RAW="https://raw.githubusercontent.com"

msg() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

has_command() { command -v "$1" &>/dev/null; }

clear
echo ""
echo -e "${CYAN}=============================================="
echo -e "${BOLD}${GREEN}   PANEL DE ADMINISTRACION VPS"
echo -e "${CYAN}=============================================="
echo -e "${YELLOW}   Instalador v1.0${NC}"
echo -e "${CYAN}=============================================="
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    err "Este instalador debe ejecutarse como root."
    exit 1
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian) ok "$PRETTY_NAME detectado." ;;
        *)
            err "Solo Ubuntu/Debian soportado."
            exit 1
            ;;
    esac
fi

msg "Actualizando repositorios..."
apt-get update -y &>/dev/null

msg "Instalando dependencias basicas..."
apt-get install -y curl wget unzip bc net-tools vnstat python3 \
    openssh-server dropbear stunnel4 openssl nload htop \
    iptables ufw dnsutils nano &>/dev/null

ok "Dependencias instaladas."

# Crear estructura
msg "Creando estructura de directorios..."
mkdir -p "$INSTALL_DIR"/{lib,protocols,users,firewall,db}
mkdir -p "$DB_DIR"/{backups}

# Copiar todos los archivos .sh del directorio actual al INSTALL_DIR
SCRIPT_SOURCE="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_SOURCE/lib/banners.sh" ]]; then
    msg "Copiando archivos locales..."
    cp "$SCRIPT_SOURCE/lib/banners.sh" "$INSTALL_DIR/lib/"
    cp "$SCRIPT_SOURCE/lib/utils.sh" "$INSTALL_DIR/lib/"
    cp "$SCRIPT_SOURCE/lib/network.sh" "$INSTALL_DIR/lib/"
    cp "$SCRIPT_SOURCE/users/crud.sh" "$INSTALL_DIR/users/"
    cp "$SCRIPT_SOURCE/users/limits.sh" "$INSTALL_DIR/users/"
    cp "$SCRIPT_SOURCE/users/monitor.sh" "$INSTALL_DIR/users/"
    cp "$SCRIPT_SOURCE/users/backup.sh" "$INSTALL_DIR/users/"
    cp "$SCRIPT_SOURCE/protocols/ssh.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/dropbear.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/stunnel.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/websocket.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/v2ray.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/badvpn.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/socks5.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/protocols/dns.sh" "$INSTALL_DIR/protocols/"
    cp "$SCRIPT_SOURCE/main.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_SOURCE/config.conf" "$INSTALL_DIR/"
else
    msg "Descargando archivos desde repositorio..."
    FILES=(
        "lib/banners.sh"
        "lib/utils.sh"
        "lib/network.sh"
        "users/crud.sh"
        "users/limits.sh"
        "users/monitor.sh"
        "users/backup.sh"
        "protocols/ssh.sh"
        "protocols/dropbear.sh"
        "protocols/stunnel.sh"
        "protocols/websocket.sh"
        "protocols/v2ray.sh"
        "protocols/badvpn.sh"
        "protocols/socks5.sh"
        "protocols/dns.sh"
        "main.sh"
        "config.conf"
    )
    for file in "${FILES[@]}"; do
        msg "Descargando $file..."
        curl -sL "$GITHUB_RAW/snblcl-dev/vps-admin/master/$file" -o "$INSTALL_DIR/$file" 2>/dev/null || true
    done
fi

# Permisos
msg "Configurando permisos..."
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null
chmod +x "$INSTALL_DIR"/lib/*.sh 2>/dev/null
chmod +x "$INSTALL_DIR"/users/*.sh 2>/dev/null
chmod +x "$INSTALL_DIR"/protocols/*.sh 2>/dev/null

# Crear symlink
msg "Creando comando global..."
ln -sf "$INSTALL_DIR/main.sh" /usr/local/bin/panel 2>/dev/null

# Inicializar base de datos
msg "Inicializando base de datos..."
touch "$DB_DIR/usuarios.db"
chmod 600 "$DB_DIR/usuarios.db" 2>/dev/null

# Configurar vnstat
if has_command vnstat; then
    systemctl enable vnstat &>/dev/null
    systemctl start vnstat &>/dev/null
    vnstat -u -i eth0 &>/dev/null || true
fi

# Instalar servicio limitador
msg "Instalando monitor de limites..."
cat > /opt/script-cgh/limit_monitor.sh << 'LMTEOF'
#!/bin/bash
USERS_DB="/etc/script-cgh/usuarios.db"
[[ ! -f "$USERS_DB" ]] && exit 0
while IFS=: read -r user pass expiry max_conn traffic created status; do
    [[ "$status" == "bloqueado" ]] && continue
    conn_count=$(ss -tnp 2>/dev/null | grep -c "uid=$(id -u "$user" 2>/dev/null)" 2>/dev/null || echo 0)
    if [[ "$conn_count" -gt "$max_conn" ]] && [[ "$max_conn" =~ ^[0-9]+$ ]]; then
        excess=$((conn_count - max_conn))
        oldest_pids=$(ss -tnp 2>/dev/null | grep "uid=$(id -u "$user" 2>/dev/null)" | grep -oP 'pid=\K[0-9]+' | head -n "$excess" 2>/dev/null)
        for pid in $oldest_pids; do
            kill "$pid" 2>/dev/null
        done
    fi
done < "$USERS_DB"
LMTEOF
chmod +x /opt/script-cgh/limit_monitor.sh

cat > /etc/systemd/system/limit-ssh.service << 'LIMEOF'
[Unit]
Description=Monitor de Limites SSH
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /opt/script-cgh/limit_monitor.sh; sleep 30; done'
Restart=always

[Install]
WantedBy=multi-user.target
LIMEOF

systemctl daemon-reload 2>/dev/null
systemctl enable limit-ssh &>/dev/null 2>&1 || true
systemctl start limit-ssh &>/dev/null 2>&1 || true

echo ""
echo -e "${CYAN}=============================================="
echo -e "${BOLD}${GREEN}   INSTALACION COMPLETADA${NC}"
echo -e "${CYAN}=============================================="
echo ""
echo -e "  ${BOLD}Para ejecutar el panel:${NC}"
echo -e "  ${GREEN}panel${NC}"
echo -e "  o"
echo -e "  ${GREEN}bash $INSTALL_DIR/main.sh${NC}"
echo ""
echo -e "  Directorio: ${YELLOW}$INSTALL_DIR${NC}"
echo -e "  DB usuarios: ${YELLOW}$DB_DIR/usuarios.db${NC}"
echo ""
echo -e "${CYAN}=============================================="
echo ""
