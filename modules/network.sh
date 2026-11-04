#!/usr/bin/env bash
# modules/network.sh — сеть: TCP BBR и буферы, Wi-Fi без энергосбережения, быстрый DNS с DNS-over-TLS.

NET_SYSCTL_FILE="/etc/sysctl.d/90-kali-setup-net.conf"
NET_BBR_MODULE_FILE="/etc/modules-load.d/kali-setup-bbr.conf"
NET_WIFI_FILE="/etc/NetworkManager/conf.d/90-kali-setup-wifi-powersave.conf"
NET_DNS_FILE="/etc/systemd/resolved.conf.d/90-kali-setup-dns.conf"

# Что меняет шаг bbr (ключ sysctl = значение)
NET_SYSCTL=(
    "net.core.default_qdisc=fq"
    "net.ipv4.tcp_congestion_control=bbr"
    "net.core.rmem_max=16777216"
    "net.core.wmem_max=16777216"
    "net.ipv4.tcp_rmem=4096 131072 16777216"
    "net.ipv4.tcp_wmem=4096 65536 16777216"
    "net.ipv4.tcp_fastopen=3"
    "net.ipv4.tcp_mtu_probing=1"
)

do_net_bbr() {
    step "Сеть: TCP BBR, большие буферы, TCP Fast Open"
    local kv k
    # исходные значения — для отката (до нашего файла)
    for kv in "${NET_SYSCTL[@]}"; do
        k="${kv%%=*}"
        state_set_once "net.sysctl.${k}" "$(sysctl -n "$k" 2>/dev/null)"
    done
    # модуль BBR грузим сейчас и при каждой загрузке
    sudo modprobe tcp_bbr 2>/dev/null || true
    echo tcp_bbr | sudo tee "$NET_BBR_MODULE_FILE" >/dev/null
    {
        echo "# kali-setup: сеть (BBR, буферы TCP). Откат: ./setup.sh undo bbr"
        for kv in "${NET_SYSCTL[@]}"; do echo "${kv%%=*} = ${kv#*=}"; done
    } | sudo tee "$NET_SYSCTL_FILE" >/dev/null
    sudo sysctl -q -p "$NET_SYSCTL_FILE" || warn "Часть параметров не применилась — смотри: sudo sysctl -p $NET_SYSCTL_FILE"
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == bbr ]]; then
        ok "TCP BBR включён, буферы до 16 МБ, TCP Fast Open для входящих и исходящих"
    else
        warn "BBR не включился (ядро без tcp_bbr?) — остальные параметры применены."
    fi
}

# Беспроводные интерфейсы (wlan0, wlp2s0…)
net_wifi_ifaces() {
    local d
    for d in /sys/class/net/*; do [[ -d "$d/wireless" ]] && basename "$d"; done
}

do_net_wifipower() {
    step "Сеть: Wi-Fi без энергосбережения (стабильный пинг)"
    if ! have nmcli; then
        warn "Нет NetworkManager — не настраиваю."
        return 0
    fi
    # В виртуалке сеть — виртуальная Ethernet-карта, Wi-Fi есть только у хоста.
    # Исключение — USB Wi-Fi-адаптер, проброшенный в VM: тогда он виден как беспроводной.
    if [[ -n "$(virt_type)" && -z "$(net_wifi_ifaces)" ]]; then
        warn "Виртуальная машина ($(virt_type)) без Wi-Fi-адаптера — пропускаю. Энергосбережение Wi-Fi настраивается на хосте."
        return 0
    fi
    # 2 = выключено; действует при каждом подключении к Wi-Fi
    printf '%s\n' "# kali-setup: Wi-Fi без энергосбережения. Откат: ./setup.sh undo wifipower" \
        "[connection]" "wifi.powersave = 2" | sudo tee "$NET_WIFI_FILE" >/dev/null
    sudo systemctl reload NetworkManager 2>/dev/null || true
    # для текущего подключения — сразу, без переподключения
    local i
    if have iw; then
        for i in $(net_wifi_ifaces); do sudo iw dev "$i" set power_save off 2>/dev/null || true; done
    fi
    if [[ -n "$(net_wifi_ifaces)" ]]; then
        ok "Энергосбережение Wi-Fi выключено: $(net_wifi_ifaces | tr '\n' ' ')"
    else
        ok "Энергосбережение Wi-Fi выключено (адаптера сейчас нет — сработает при подключении)."
    fi
}

# Выбор DNS-провайдера. Результат — ключ в stdout. Без меню — переменная DNS_PROVIDER (cloudflare|quad9|google).
pick_dns() {
    if [[ -n "${DNS_PROVIDER:-}" ]]; then echo "$DNS_PROVIDER"; return 0; fi
    { [[ -t 0 ]] && { ui_gum || have whiptail; }; } || { echo cloudflare; return 0; }
    ui_menu "DNS" "Чей DNS использовать?" \
        cloudflare "1.1.1.1 — самый быстрый" \
        quad9      "9.9.9.9 — блокирует вредоносные домены" \
        google     "8.8.8.8 — стабильный" || echo cloudflare
}

do_net_dns() {
    step "Сеть: быстрый DNS + DNS-over-TLS (systemd-resolved)"
    local p servers fallback
    p="$(pick_dns)"
    case "$p" in
        quad9)  servers="9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net"
                fallback="1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google" ;;
        google) servers="8.8.8.8#dns.google 8.8.4.4#dns.google"
                fallback="1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net" ;;
        *)      p=cloudflare
                servers="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com"
                fallback="9.9.9.9#dns.quad9.net 8.8.8.8#dns.google" ;;
    esac
    if ! pkg_installed systemd-resolved; then
        state_set_once net.resolved.installed yes
        sudo apt install -y systemd-resolved || { warn "Не удалось поставить systemd-resolved"; return 1; }
    fi
    sudo systemctl enable --now systemd-resolved 2>/dev/null || true
    # opportunistic: шифруем, когда сервер умеет; в сетях, где 853 закрыт, DNS не ломается.
    # Domains=~. не ставим — DNS из DHCP (внутренние домены, AD на стендах) продолжает работать.
    sudo mkdir -p "$(dirname "$NET_DNS_FILE")"
    printf '%s\n' "# kali-setup: DNS ${p}. Откат: ./setup.sh undo dns" "[Resolve]" \
        "DNS=${servers}" "FallbackDNS=${fallback}" "DNSOverTLS=opportunistic" "Cache=yes" \
        | sudo tee "$NET_DNS_FILE" >/dev/null
    sudo systemctl restart systemd-resolved
    [[ "$(readlink /etc/resolv.conf)" == *systemd/resolve/* ]] \
        || warn "/etc/resolv.conf не указывает на systemd-resolved — система может его обходить."
    ok "DNS: ${p}, DNS-over-TLS (по возможности), кэш. Проверка: resolvectl status"
}
