#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

DNS_DIR="/opt/script-cgh/dns"

install_slowdns() {
    print_title "INSTALAR SLOWDNS"
    check_root

    install_pkg "python3"
    install_pkg "dnsutils"

    mkdir -p "$DNS_DIR"

    cat > "$DNS_DIR/slowdns.py" << 'DNSEOF'
#!/usr/bin/env python3
import socket
import struct
import threading
import sys
import base64
import random

class SlowDNSServer:
    def __init__(self, listen_port=53, target_host='127.0.0.1', target_port=22):
        self.listen_port = listen_port
        self.target_host = target_host
        self.target_port = target_port
        self.domains = {}

    def parse_dns_query(self, data):
        if len(data) < 12:
            return None
        trans_id = data[:2]
        flags = struct.unpack('>H', data[2:4])[0]
        questions = struct.unpack('>H', data[4:6])[0]

        if questions == 0:
            return None

        pos = 12
        domain = ''
        while pos < len(data):
            length = data[pos]
            if length == 0:
                pos += 1
                break
            if pos + length + 1 > len(data):
                return None
            if domain:
                domain += '.'
            domain += data[pos+1:pos+1+length].decode('ascii', errors='ignore')
            pos += length + 1

        qtype = struct.unpack('>H', data[pos:pos+2])[0]
        return {'id': trans_id, 'domain': domain, 'type': qtype, 'data': data}

    def craft_response(self, query_id, payload, dns_type=16):
        response = bytearray()
        response.extend(query_id)
        response.extend(struct.pack('>H', 0x8180))
        response.extend(struct.pack('>H', 1))
        response.extend(struct.pack('>H', 1))
        response.extend(struct.pack('>H', 0))
        response.extend(struct.pack('>H', 0))
        response.extend(b'\x00')

        response.extend(struct.pack('>H', 1))
        response.extend(struct.pack('>H', dns_type))
        response.extend(struct.pack('>H', 1))

        response.extend(struct.pack('>H', len(payload)))
        response.extend(payload)

        return bytes(response)

    def handle_client(self, data, addr, server_socket):
        try:
            query = self.parse_dns_query(data)
            if not query:
                return

            domain = query['domain']
            subdomain = domain.split('.')[0] if '.' in domain else domain

            decoded = ''
            try:
                if subdomain.endswith('=='):
                    padding = 4 - (len(subdomain) % 4)
                    decoded_data = base64.b64decode(subdomain + '=' * padding).decode(errors='ignore')
                    decoded = decoded_data.split('\x00')[0]
            except Exception:
                try:
                    decoded = bytes.fromhex(subdomain).decode(errors='ignore')
                except Exception:
                    pass

            if decoded and not decoded.startswith('.'):
                self.domains[domain] = decoded

            response_text = self.domains.get(domain, 'ok')

            response_bytes = base64.b64encode(response_text.encode()).decode().rstrip('=')

            response = self.craft_response(query['id'], response_bytes.encode())
            server_socket.sendto(response, addr)
        except Exception:
            pass

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('0.0.0.0', self.listen_port))
        print(f"[SlowDNS] UDP 0.0.0.0:{self.listen_port}")

        while True:
            try:
                data, addr = server.recvfrom(65535)
                t = threading.Thread(target=self.handle_client, args=(data, addr, server))
                t.daemon = True
                t.start()
            except KeyboardInterrupt:
                break
            except Exception:
                continue

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=53)
    args = parser.parse_args()
    server = SlowDNSServer(listen_port=args.port)
    server.start()
DNSEOF

    chmod +x "$DNS_DIR/slowdns.py"

    read -rp "  Puerto DNS [53]: " dns_port
    dns_port="${dns_port:-53}"

    if [[ "$dns_port" -lt 1024 && $EUID -ne 0 ]]; then
        msg_warn "Puerto <1024 requiere root."
    fi

    cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=SlowDNS Tunnel Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DNS_DIR/slowdns.py --port $dns_port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service slowdns

    allow_port "$dns_port" "udp"

    msg_ok "SlowDNS instalado en puerto UDP $dns_port."
    pause
}

install_fastdns() {
    print_title "INSTALAR FASTDNS"
    check_root

    install_pkg "python3"

    read -rp "  Puerto FastDNS [5300]: " port
    port="${port:-5300}"

    mkdir -p "$DNS_DIR"

    cat > "$DNS_DIR/fastdns.py" << 'FDNEOF'
#!/usr/bin/env python3
import socket
import struct
import threading
import base64

class FastDNSServer:
    def __init__(self, listen_port=5300, target_host='127.0.0.1', target_port=22):
        self.listen_port = listen_port
        self.target_host = target_host
        self.target_port = target_port

    def handle_client(self, client_socket):
        try:
            client_socket.settimeout(60)

            remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote.connect((self.target_host, self.target_port))

            def forward(src, dst, encode=False):
                while True:
                    try:
                        data = src.recv(8192)
                        if not data:
                            break
                        if encode:
                            encoded = base64.b64encode(data) + b'\n'
                            dst.sendall(encoded)
                        else:
                            try:
                                decoded = base64.b64decode(data.strip())
                                dst.sendall(decoded)
                            except Exception:
                                dst.sendall(data)
                    except Exception:
                        break
                try:
                    src.close()
                except:
                    pass
                try:
                    dst.close()
                except:
                    pass

            t1 = threading.Thread(target=forward, args=(client_socket, remote, False))
            t2 = threading.Thread(target=forward, args=(remote, client_socket, True))
            t1.daemon = True
            t2.daemon = True
            t1.start()
            t2.start()
            t1.join(timeout=300)
            t2.join(timeout=300)
        except Exception:
            pass
        finally:
            try:
                client_socket.close()
            except:
                pass

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('0.0.0.0', self.listen_port))
        server.listen(100)
        print(f"[FastDNS] 0.0.0.0:{self.listen_port}")

        while True:
            try:
                client, addr = server.accept()
                t = threading.Thread(target=self.handle_client, args=(client,))
                t.daemon = True
                t.start()
            except KeyboardInterrupt:
                break
            except Exception:
                continue

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=5300)
    parser.add_argument('--target-host', default='127.0.0.1')
    parser.add_argument('--target-port', type=int, default=22)
    args = parser.parse_args()
    server = FastDNSServer(args.port, args.target_host, args.target_port)
    server.start()
FDNEOF

    chmod +x "$DNS_DIR/fastdns.py"

    read -rp "  Puerto destino (ej SSH=22) [22]: " target_port
    target_port="${target_port:-22}"

    cat > /etc/systemd/system/fastdns.service << EOF
[Unit]
Description=FastDNS Tunnel Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DNS_DIR/fastdns.py --port $port --target-port $target_port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service fastdns

    allow_port "$port" "tcp"

    msg_ok "FastDNS instalado en puerto $port -> $target_port."
    pause
}

dns_status() {
    print_title "ESTADO DNS TUNNELS"

    echo -e "  ${BOLD}SlowDNS:${NC}"
    if check_service slowdns; then
        msg_ok "Activo"
    else
        msg_error "Inactivo"
    fi

    echo -e "  ${BOLD}FastDNS:${NC}"
    if check_service fastdns; then
        msg_ok "Activo"
    else
        msg_error "Inactivo"
    fi

    echo ""
    echo -e "  ${BOLD}Puertos DNS:${NC}"
    ss -ulnp | grep -E "dns|python" | while read -r line; do
        echo -e "  $line"
    done

    pause
}

dns_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION DNS TUNNELS ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar SlowDNS (UDP)"
        echo -e "  ${GREEN}2)${NC} Instalar FastDNS (TCP)"
        echo -e "  ${GREEN}3)${NC} Ver estado"
        echo -e "  ${GREEN}4)${NC} Reiniciar SlowDNS"
        echo -e "  ${GREEN}5)${NC} Reiniciar FastDNS"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_slowdns ;;
            2) install_fastdns ;;
            3) dns_status ;;
            4)
                systemctl restart slowdns 2>/dev/null
                msg_ok "SlowDNS reiniciado."
                pause
                ;;
            5)
                systemctl restart fastdns 2>/dev/null
                msg_ok "FastDNS reiniciado."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    dns_menu
fi
