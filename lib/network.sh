#!/bin/bash

# Escanear puertos abiertos
list_open_ports() {
    ss -tuln | awk 'NR>1 {print $1, $5}' | sed 's/.*://' | sort -n | uniq | while read proto port; do
        local process
        process=$(ss -tlnp | grep ":$port " | grep -oP '(?<=")[^"]+(?=")' | head -1)
        echo "$port $proto ${process:-desconocido}"
    done
}

# Verificar conectividad
check_connectivity() {
    ping -c1 -W2 8.8.8.8 &>/dev/null && return 0 || return 1
}

# Obtener gateway
get_gateway() {
    ip route | grep default | awk '{print $3}' | head -1
}

# Obtener interfaz principal
get_main_iface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# Permitir puerto en firewall
allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    if has_command ufw && ufw status | grep -q "active"; then
        ufw allow "$port/$proto" &>/dev/null
        ufw reload &>/dev/null
    fi
    iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    iptables -I OUTPUT -p "$proto" --sport "$port" -j ACCEPT 2>/dev/null
}

# Bloquear puerto en firewall
block_port() {
    local port="$1"
    local proto="${2:-tcp}"
    if has_command ufw && ufw status | grep -q "active"; then
        ufw deny "$port/$proto" &>/dev/null
        ufw reload &>/dev/null
    fi
    iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p "$proto" --sport "$port" -j ACCEPT 2>/dev/null
}

# Limpiar reglas iptables huerfanas
clean_orphan_rules() {
    msg_info "Limpiando reglas huerfanas..."
    local network=0
    ip -6 addr show scope global &>/dev/null && network=1 || network=0

    for type in INPUT OUTPUT; do
        local result
        if [[ $network -eq 1 ]]; then
            result=$(ip6tables -nvL "$type" --line-number 2>/dev/null | grep ':' | awk '{printf "%s %s\n",$1,$NF}' | sed 's/dpt://g;s/spt://g' | sort -n -k1 -r)
        else
            result=$(iptables -nvL "$type" --line-number 2>/dev/null | grep ':' | awk -F ':' '{print $2"  "$1}' | awk '{print $2" "$1}' | sort -n -k1 -r)
        fi

        echo "$result" | while read -r line; do
            local line_array=($line)
            if [[ ${line_array[1]} && -z $(ss -tunlp | grep -w "${line_array[1]}") ]]; then
                [[ $network -eq 1 ]] && ip6tables -D "$type" "${line_array[0]}" 2>/dev/null || iptables -D "$type" "${line_array[0]}" 2>/dev/null
            fi
        done
    done
    msg_ok "Reglas huerfanas limpiadas."
}

# Verificar puerto en firewall
check_firewall() {
    local port="$1"
    iptables -L INPUT -n | grep -q "dpt:$port "
}

# Activar forwarding IP
enable_ip_forward() {
    sysctl -w net.ipv4.ip_forward=1 &>/dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 &>/dev/null
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
}

# Deshabilitar IPv6 (opcional)
disable_ipv6() {
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 &>/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 &>/dev/null
    echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
}

# Tuning kernel para VPN
tune_kernel() {
    local conf="/etc/sysctl.conf"
    local settings=(
        "net.core.rmem_max=16777216"
        "net.core.wmem_max=16777216"
        "net.ipv4.tcp_rmem=4096 87380 16777216"
        "net.ipv4.tcp_wmem=4096 65536 16777216"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_mtu_probing=1"
    )
    for setting in "${settings[@]}"; do
        if ! grep -q "^${setting%%=*}" "$conf"; then
            echo "$setting" >> "$conf"
        fi
    done
    sysctl -p &>/dev/null
}
