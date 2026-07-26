#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

WS_DIR="/opt/script-cgh/websocket"
WS_PORT=80

install_websocket() {
    print_title "INSTALAR WEBSOCKET PAYLOAD"
    check_root

    install_pkg "python3"
    install_pkg "netcat-openbsd"

    mkdir -p "$WS_DIR"

    # Script Python para tunel WebSocket
    cat > "$WS_DIR/ws_proxy.py" << 'WSEOF'
#!/usr/bin/env python3
import socket
import threading
import sys
import time
import struct
import hashlib
import base64

class WSProxy:
    def __init__(self, listen_port, target_host, target_port, payload_enabled=False):
        self.listen_port = listen_port
        self.target_host = target_host
        self.target_port = target_port
        self.payload_enabled = payload_enabled
        self.payload = ""

    def create_ws_frame(self, data):
        length = len(data)
        header = bytearray()
        header.append(0x82)

        if length < 126:
            header.append(length)
        elif length < 65536:
            header.append(126)
            header.extend(struct.pack('>H', length))
        else:
            header.append(127)
            header.extend(struct.pack('>Q', length))

        return bytes(header) + data

    def parse_ws_frame(self, data):
        if len(data) < 2:
            return None, data

        fin_and_opcode = data[0]
        masked = (data[1] & 0x80) != 0
        length = data[1] & 0x7f
        pos = 2

        if length == 126:
            if len(data) < 4:
                return None, data
            length = struct.unpack('>H', data[2:4])[0]
            pos = 4
        elif length == 127:
            if len(data) < 10:
                return None, data
            length = struct.unpack('>Q', data[2:10])[0]
            pos = 10

        mask = data[pos:pos+4] if masked else None
        if masked:
            pos += 4

        if len(data) < pos + length:
            return None, data

        payload = bytearray(data[pos:pos+length])
        if masked:
            for i in range(len(payload)):
                payload[i] ^= mask[i % 4]

        remaining = data[pos+length:]
        opcode = fin_and_opcode & 0x0f

        if opcode == 0x8:  # close
            return (b'\xff', bytes(payload)), remaining
        return (bytes(payload), remaining)

    def do_handshake(self, client_socket):
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = client_socket.recv(4096)
            if not chunk:
                return False
            data += chunk

        headers = data.decode(errors='ignore')
        key = ""
        for line in headers.split("\r\n"):
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
                break

        if not key:
            return False

        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
        )
        client_socket.send(response.encode())

        if self.payload_enabled and self.payload:
            time.sleep(0.1)
            frame = self.create_ws_frame(self.payload.encode())
            client_socket.send(frame)

        return True

    def tunnel(self, client_socket, target_socket, direction):
        try:
            buffer = b""
            first = True
            while True:
                if first and direction == "in" and self.payload:
                    first = False
                    to_send = b"GET / HTTP/1.1\r\nHost: " + self.target_host.encode() + b"\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
                    if not self.payload:
                        to_send = b""
                    else:
                        target_socket.send(to_send)
                        time.sleep(0.1)
                        continue

                data = client_socket.recv(8192)
                if not data:
                    break

                buffer += data

                if direction == "out":
                    frame, buffer = self.parse_ws_frame(buffer)
                    while frame is not None:
                        if frame == b'\xff':
                            target_socket.shutdown(socket.SHUT_WR)
                            return
                        target_socket.send(frame)
                        frame, buffer = self.parse_ws_frame(buffer)
                else:
                    frames = self.create_ws_frame(buffer)
                    target_socket.send(frames)
                    buffer = b""

        except Exception:
            pass
        finally:
            try:
                client_socket.close()
            except:
                pass
            try:
                target_socket.close()
            except:
                pass

    def handle_client(self, client_socket):
        if not self.do_handshake(client_socket):
            client_socket.close()
            return

        try:
            target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_socket.connect((self.target_host, self.target_port))
        except Exception:
            client_socket.close()
            return

        t1 = threading.Thread(target=self.tunnel, args=(client_socket, target_socket, "out"))
        t2 = threading.Thread(target=self.tunnel, args=(target_socket, client_socket, "in"))
        t1.daemon = True
        t2.daemon = True
        t1.start()
        t2.start()
        t1.join(timeout=300)
        t2.join(timeout=300)

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('0.0.0.0', self.listen_port))
        server.listen(100)
        print(f"[WS Proxy] Escuchando en 0.0.0.0:{self.listen_port} -> {self.target_host}:{self.target_port}")

        while True:
            try:
                client_socket, addr = server.accept()
                t = threading.Thread(target=self.handle_client, args=(client_socket,))
                t.daemon = True
                t.start()
            except KeyboardInterrupt:
                break
            except Exception:
                continue

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='WebSocket Proxy Tunnel')
    parser.add_argument('--port', type=int, default=80, help='Puerto de escucha')
    parser.add_argument('--target-host', default='127.0.0.1', help='Host destino')
    parser.add_argument('--target-port', type=int, default=22, help='Puerto destino')
    parser.add_argument('--payload', action='store_true', help='Activar payload')
    parser.add_argument('--payload-text', default='', help='Texto del payload')

    args = parser.parse_args()
    proxy = WSProxy(args.port, args.target_host, args.target_port, args.payload)
    if args.payload_text:
        proxy.payload = args.payload_text
    proxy.start()
WSEOF

    chmod +x "$WS_DIR/ws_proxy.py"

    read -rp "  Puerto WebSocket [80]: " ws_port
    ws_port="${ws_port:-80}"

    read -rp "  Puerto destino (ej SSH=22, Dropbear=442) [22]: " target_port
    target_port="${target_port:-22}"

    if ! is_port "$ws_port" || ! is_port "$target_port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    # Crear servicio systemd
    cat > /etc/systemd/system/ws-proxy.service << EOF
[Unit]
Description=WebSocket Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $WS_DIR/ws_proxy.py --port $ws_port --target-host 127.0.0.1 --target-port $target_port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service "ws-proxy"

    WS_PORT=$ws_port
    allow_port "$ws_port" "tcp"

    msg_ok "WebSocket instalado: puerto $ws_port -> $target_port"
    pause
}

ws_status() {
    print_title "ESTADO WEBSOCKET"

    if check_service ws-proxy; then
        msg_ok "WebSocket activo."
    else
        msg_error "WebSocket inactivo."
    fi

    echo ""
    ss -tlnp | grep -E "python|ws" | while read -r line; do
        echo -e "  $line"
    done

    pause
}

ws_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION WEBSOCKET ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar WebSocket"
        echo -e "  ${GREEN}2)${NC} Ver estado"
        echo -e "  ${GREEN}3)${NC} Reiniciar servicio"
        echo -e "  ${GREEN}4)${NC} Detener servicio"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_websocket ;;
            2) ws_status ;;
            3)
                systemctl restart ws-proxy 2>/dev/null
                msg_ok "WebSocket reiniciado."
                pause
                ;;
            4)
                systemctl stop ws-proxy 2>/dev/null
                msg_ok "WebSocket detenido."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ws_menu
fi
