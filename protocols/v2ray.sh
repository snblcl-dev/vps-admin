#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"

install_xray() {
    print_title "INSTALAR XRAY (VLESS + VMESS)"
    check_root

    install_pkg "curl"
    install_pkg "unzip"

    msg_info "Descargando Xray..."
    local arch
    case $(uname -m) in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *) msg_error "Arquitectura no soportada."; pause; return 1 ;;
    esac

    local xray_zip="/tmp/xray.zip"
    curl -sL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip" -o "$xray_zip"

    if [[ ! -f "$xray_zip" ]] || [[ $(stat -c%s "$xray_zip") -lt 1000 ]]; then
        msg_error "No se pudo descargar Xray."
        pause
        return 1
    fi

    mkdir -p "$XRAY_DIR"
    unzip -o "$xray_zip" -d /tmp/xray_tmp &>/dev/null
    cp /tmp/xray_tmp/xray "$XRAY_BIN" 2>/dev/null
    chmod +x "$XRAY_BIN"
    rm -rf /tmp/xray_tmp "$xray_zip"

    # Generar UUID
    local uuid
    if [[ -f "$XRAY_BIN" ]]; then
        uuid=$("$XRAY_BIN" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    else
        uuid=$(cat /proc/sys/kernel/random/uuid)
    fi

    read -rp "  Puerto principal [8080]: " v2_port
    v2_port="${v2_port:-8080}"

    read -rp "  UUID (dejar vacio para auto-generar): " custom_uuid
    uuid="${custom_uuid:-$uuid}"

    local short_id
    read -rp "  Short ID (opcional): " short_id

    local conn_mode="tcp"
    if confirm_action "Usar WebSocket (ws) en lugar de TCP?"; then
        conn_mode="ws"
    fi

    # Generar config
    local stream_settings
    if [[ "$conn_mode" == "ws" ]]; then
        stream_settings=$(cat << WSEOF
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/xray"
      }
    },
WSEOF
)
    else
        stream_settings='"streamSettings": {"network": "tcp"},'
    fi

    cat > "$XRAY_CONFIG" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $v2_port,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      $stream_settings
      "tag": "vmess-in"
    },
    {
      "port": $((v2_port + 1)),
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      $stream_settings
      "tag": "vless-in"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    # Crear servicio
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=$XRAY_BIN -config $XRAY_CONFIG
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service xray

    allow_port "$v2_port" "tcp"
    allow_port "$((v2_port + 1))" "tcp"

    echo ""
    msg_ok "Xray instalado exitosamente."
    separator
    echo -e "  ${BOLD}${YELLOW}DATOS DE CONEXION:${NC}"
    echo -e "  IP:      ${CYAN}$(get_public_ip)${NC}"
    echo -e "  Puerto VMess:  ${GREEN}$v2_port${NC}"
    echo -e "  Puerto VLESS:  ${GREEN}$((v2_port + 1))${NC}"
    echo -e "  UUID:    ${GREEN}$uuid${NC}"
    echo -e "  Network: ${GREEN}$conn_mode${NC}"
    if [[ "$conn_mode" == "ws" ]]; then
        echo -e "  Path WS: ${GREEN}/xray${NC}"
    fi
    if [[ -n "$short_id" ]]; then
        echo -e "  Short ID: ${GREEN}$short_id${NC}"
    fi
    separator
    pause
}

v2ray_add_user() {
    print_title "AGREGAR USUARIO V2RAY"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        msg_error "Xray no esta instalado."
        pause
        return
    fi

    local new_uuid
    read -rp "  UUID (vacio = auto-generar): " new_uuid
    if [[ -z "$new_uuid" ]]; then
        new_uuid=$("$XRAY_BIN" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    fi

    msg_info "Editando manualmente $XRAY_CONFIG"
    msg_info "Agrega el UUID '$new_uuid' a la lista 'clients'."

    if has_command nano; then
        nano "$XRAY_CONFIG"
    else
        install_pkg "nano"
        nano "$XRAY_CONFIG"
    fi

    systemctl restart xray &>/dev/null
    msg_ok "Configuracion actualizada. Nuevo UUID: $new_uuid"
    pause
}

v2ray_status() {
    print_title "ESTADO DE XRAY"

    if check_service xray; then
        msg_ok "Xray activo."
    else
        msg_error "Xray inactivo."
    fi

    echo ""
    echo -e "  ${BOLD}Puertos configurados:${NC}"
    grep '"port"' "$XRAY_CONFIG" 2>/dev/null | head -5 | while read -r line; do
        echo -e "  $line"
    done

    echo ""
    echo -e "  ${BOLD}Protocolos:${NC}"
    grep '"protocol"' "$XRAY_CONFIG" 2>/dev/null | head -5 | while read -r line; do
        echo -e "  $line"
    done

    pause
}

v2ray_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION V2RAY / XRAY ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar Xray (VMess + VLESS)"
        echo -e "  ${GREEN}2)${NC} Agregar usuario/ID"
        echo -e "  ${GREEN}3)${NC} Ver estado"
        echo -e "  ${GREEN}4)${NC} Editar configuracion"
        echo -e "  ${GREEN}5)${NC} Ver logs"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_xray ;;
            2) v2ray_add_user ;;
            3) v2ray_status ;;
            4)
                print_title "EDITAR CONFIGURACION"
                [[ -f "$XRAY_CONFIG" ]] && nano "$XRAY_CONFIG" || msg_error "Config no encontrada."
                systemctl restart xray &>/dev/null
                pause
                ;;
            5)
                print_title "LOGS DE XRAY"
                journalctl -u xray --no-pager -n 40
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    v2ray_menu
fi
