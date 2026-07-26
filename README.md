# Panel de Administracion VPS

Script modular para gestionar usuarios y protocolos de tunel/VPN en Ubuntu 22.04+.

## Protocolos soportados

- **SSH** — servidor OpenSSH (puerto, banner, root login)
- **Dropbear** — servidor SSH ligero, multi-puerto
- **Stunnel** — tunel SSL/TLS con certificados auto-generados
- **WebSocket** — proxy WS (RFC 6455, Python)
- **V2Ray / XRay** — VMess + VLESS + WebSocket
- **BadVPN** — UDP Gateway (compila desde fuente)
- **Socks5** — proxy SOCKS5 RFC 1928 con auth opcional
- **SlowDNS / FastDNS** — tuneles DNS (UDP y TCP)

## Instalacion

```bash
apt update -y && apt upgrade -y && wget -q https://raw.githubusercontent.com/snblcl-dev/vps-admin/master/install.sh && chmod +x install.sh && ./install.sh
```

## Uso

```bash
panel
```

o

```bash
bash /opt/script-cgh/main.sh
```

## Estructura

```
/opt/script-cgh/
├── main.sh              # Menu principal
├── install.sh           # Instalador
├── config.conf          # Configuracion
├── lib/                  # Librerias (UI, utils, red)
├── protocols/            # Modulos de protocolos
├── users/                # Gestion de usuarios
├── firewall/             # Reglas de firewall
└── db/                   # Base de datos
```

Usuarios guardados en: `/etc/script-cgh/usuarios.db`

## Requisitos

- Ubuntu 22.04+ (o Debian 11+)
- Ejecutar como root
