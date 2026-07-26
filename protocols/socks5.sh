#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/banners.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/network.sh"

SOCKS_DIR="/opt/script-cgh/socks5"

install_socks5() {
    print_title "INSTALAR PROXY SOCKS5"
    check_root

    install_pkg "python3"

    read -rp "  Puerto Socks5 [1080]: " port
    port="${port:-1080}"

    if ! is_port "$port"; then
        msg_error "Puerto invalido."
        pause
        return 1
    fi

    read -rp "  Usuario (vacio = sin autenticacion): " socks_user
    read -rp "  Password: " socks_pass

    mkdir -p "$SOCKS_DIR"

    cat > "$SOCKS_DIR/socks5.py" << 'PYEOF'
#!/usr/bin/env python3
import socket
import select
import struct
import sys
import threading

SOCKS_VERSION = 5
BUFFER_SIZE = 4096

class Socks5Server:
    def __init__(self, host, port, username=None, password=None):
        self.host = host
        self.port = port
        self.username = username
        self.password = password

    def handle_client(self, client_socket):
        try:
            client_socket.settimeout(30)
            ver = client_socket.recv(1)
            if not ver or ver[0] != SOCKS_VERSION:
                client_socket.close()
                return

            nmethods = client_socket.recv(1)[0]
            methods = client_socket.recv(nmethods)

            if self.username and self.password:
                if 2 not in methods:
                    client_socket.sendall(b'\x05\xff')
                    client_socket.close()
                    return
                client_socket.sendall(b'\x05\x02')
                self.do_auth(client_socket)
            else:
                client_socket.sendall(b'\x05\x00')

            ver, cmd, rsv, atype = struct.unpack('!BBBB', client_socket.recv(4))

            if cmd != 1:
                self.send_reply(client_socket, 7)
                client_socket.close()
                return

            if atype == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif atype == 3:  # Domain
                length = client_socket.recv(1)[0]
                addr = client_socket.recv(length).decode()
            elif atype == 4:  # IPv6
                addr = socket.inet_ntop(socket.AF_INET6, client_socket.recv(16))
            else:
                self.send_reply(client_socket, 8)
                client_socket.close()
                return

            port = struct.unpack('!H', client_socket.recv(2))[0]

            try:
                remote = socket.create_connection((addr, port), timeout=30)
            except Exception:
                self.send_reply(client_socket, 5)
                client_socket.close()
                return

            bind_addr = client_socket.getsockname()
            reply = struct.pack('!BBBBIH', SOCKS_VERSION, 0, 0, 1,
                                struct.unpack('!I', socket.inet_aton(bind_addr[0]))[0],
                                bind_addr[1])
            client_socket.sendall(reply)

            self.transfer(client_socket, remote)
        except Exception:
            pass
        finally:
            try:
                client_socket.close()
            except:
                pass

    def do_auth(self, client_socket):
        ver = client_socket.recv(1)[0]
        ulen = client_socket.recv(1)[0]
        username = client_socket.recv(ulen).decode()
        plen = client_socket.recv(1)[0]
        password = client_socket.recv(plen).decode()

        if username == self.username and password == self.password:
            client_socket.sendall(b'\x01\x00')
        else:
            client_socket.sendall(b'\x01\x01')
            client_socket.close()
            raise Exception("Auth failed")

    def send_reply(self, socket, code):
        reply = struct.pack('!BBBBIH', SOCKS_VERSION, code, 0, 1, 0, 0)
        socket.sendall(reply)

    def transfer(self, client, remote):
        sockets = [client, remote]
        try:
            while True:
                readable, _, _ = select.select(sockets, [], [], 60)
                if not readable:
                    break
                for s in readable:
                    data = s.recv(BUFFER_SIZE)
                    if not data:
                        return
                    if s is client:
                        remote.sendall(data)
                    else:
                        client.sendall(data)
        except Exception:
            pass
        finally:
            for s in sockets:
                try:
                    s.close()
                except:
                    pass

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(50)
        print(f"[SOCKS5] {self.host}:{self.port}")

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
    parser.add_argument('--port', type=int, default=1080)
    parser.add_argument('--user', default=None)
    parser.add_argument('--passwd', default=None)
    args = parser.parse_args()

    server = Socks5Server('0.0.0.0', args.port,
                          args.user if args.user else None,
                          args.passwd if args.passwd else None)
    server.start()
PYEOF

    chmod +x "$SOCKS_DIR/socks5.py"

    # Crear servicio
    local extra_opts=""
    if [[ -n "$socks_user" ]]; then
        extra_opts="--user $socks_user --passwd $socks_pass"
    fi

    cat > /etc/systemd/system/socks5.service << EOF
[Unit]
Description=Socks5 Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SOCKS_DIR/socks5.py --port $port $extra_opts
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service socks5

    allow_port "$port" "tcp"

    msg_ok "Socks5 instalado en puerto $port."
    if [[ -n "$socks_user" ]]; then
        echo -e "  Usuario: ${GREEN}$socks_user${NC}"
    fi
    pause
}

socks5_status() {
    print_title "ESTADO SOCKS5"

    if check_service socks5; then
        msg_ok "Socks5 activo."
    else
        msg_error "Socks5 inactivo."
    fi

    echo ""
    echo -e "  ${BOLD}Conexiones activas:${NC}"
    ss -tnp | grep socks5 | wc -l | xargs echo "  Total:"

    pause
}

socks5_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${YELLOW}--- GESTION SOCKS5 ---${NC}\n"
        echo -e "  ${GREEN}1)${NC} Instalar Socks5"
        echo -e "  ${GREEN}2)${NC} Ver estado"
        echo -e "  ${GREEN}3)${NC} Reiniciar"
        echo -e "  ${GREEN}4)${NC} Detener"
        echo -e "  ${GREEN}0)${NC} Volver"
        echo ""
        read -rp "  $(echo -e ${CYAN}Opcion: ${NC})" opt

        case $opt in
            1) install_socks5 ;;
            2) socks5_status ;;
            3)
                systemctl restart socks5 2>/dev/null
                msg_ok "Socks5 reiniciado."
                pause
                ;;
            4)
                systemctl stop socks5 2>/dev/null
                msg_ok "Socks5 detenido."
                pause
                ;;
            0) return ;;
            *) msg_error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    socks5_menu
fi
