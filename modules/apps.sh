#!/usr/bin/env bash
# modules/apps.sh — установка приложений.

do_discord() {
    step "4. Discord (официальный .deb)"
    if pkg_installed discord; then
        ok "Discord уже установлен (v$(dpkg-query -W -f='${Version}' discord 2>/dev/null)). Пропускаю."
        return
    fi
    local deb="${DOWNLOAD_DIR}/discord.deb"
    if curl -fL --retry 3 -o "$deb" "https://discord.com/api/download?platform=linux&format=deb"; then
        install_deb "$deb" && ok "Discord установлен"
    else
        warn "Не скачался Discord .deb"
    fi
}

do_telegram() {
    step "Telegram (telegram-desktop из репозитория Kali)"
    if pkg_installed telegram-desktop; then
        ok "Telegram уже установлен (v$(dpkg-query -W -f='${Version}' telegram-desktop 2>/dev/null)). Пропускаю."
        return
    fi
    if sudo apt install -y telegram-desktop; then
        ok "Telegram установлен"
    else
        warn "Не удалось поставить telegram-desktop"
    fi
}

do_keepassxc() {
    step "KeePassXC (менеджер паролей из репозитория Kali)"
    if pkg_installed keepassxc; then
        ok "KeePassXC уже установлен (v$(dpkg-query -W -f='${Version}' keepassxc 2>/dev/null)). Пропускаю."
        return
    fi
    if sudo apt install -y keepassxc; then
        ok "KeePassXC установлен"
    else
        warn "Не удалось поставить keepassxc"
    fi
}

do_obsidian() {
    step "5. Obsidian (последний .deb с GitHub)"
    if pkg_installed obsidian; then
        ok "Obsidian уже установлен (v$(dpkg-query -W -f='${Version}' obsidian 2>/dev/null)). Пропускаю."
        return
    fi
    local deb="${DOWNLOAD_DIR}/obsidian.deb"
    if gh_latest_asset "obsidianmd/obsidian-releases" 'amd64\.deb$' "$deb"; then
        install_deb "$deb" && ok "Obsidian установлен"
    else
        warn "Не удалось получить Obsidian .deb"
    fi
}

do_happ() {
    step "6. Happ (последний .deb с GitHub)"
    if pkg_installed happ; then
        ok "Happ уже установлен (v$(dpkg-query -W -f='${Version}' happ 2>/dev/null)). Пропускаю."
        return
    fi
    local deb="${DOWNLOAD_DIR}/happ.deb"
    # Берём x64 .deb из релизов happ-desktop
    if gh_latest_asset "Happ-proxy/happ-desktop" 'linux.*(x64|amd64).*\.deb$|\.deb$' "$deb"; then
        install_deb "$deb" && ok "Happ установлен"
    else
        warn "Не удалось получить Happ .deb — проверь https://www.happ.su вручную"
    fi
}

do_amnezia() {
    step "7. AmneziaVPN (автоматическая установка)"
    # GUI-зависимости для Debian 13/Kali.
    sudo apt install -y libxcb-xinerama0 libxcb-cursor0 iptables 2>/dev/null || true
    # КЛЮЧЕВОЙ момент: без systemd-resolved AmneziaWG/WireGuard подключается,
    # но DNS внутри туннеля не работает ("Подключено", а сайты не грузятся).
    # Ставим и включаем его заранее — иначе VPN будет бесполезен.
    sudo apt install -y systemd-resolved 2>/dev/null || true
    sudo systemctl enable --now systemd-resolved 2>/dev/null || true

    # Уже установлен? — пропускаем (идемпотентность).
    if [[ -x /opt/AmneziaVPN/bin/AmneziaVPN ]]; then
        ok "AmneziaVPN уже установлен (/opt/AmneziaVPN). Пропускаю установку."
        return
    fi

    local dest="${HOME}/amneziavpn-installer"
    mkdir -p "$dest"
    local run="${dest}/AmneziaVPN_linux_x64.run"
    if ! gh_latest_asset "amnezia-vpn/amnezia-client" 'linux_x64\.run$' "$run"; then
        warn "Не удалось скачать AmneziaVPN. Скачай вручную: https://github.com/amnezia-vpn/amnezia-client/releases/latest"
        return
    fi
    chmod +x "$run"
    # Полностью тихая (headless) установка через Qt Installer Framework.
    # Ставит в /opt/AmneziaVPN, создаёт и включает systemd-сервис AmneziaVPN.service.
    log "Ставлю AmneziaVPN в автоматическом режиме..."
    if sudo "$run" install --accept-licenses --accept-messages --default-answer --confirm-command -t /opt/AmneziaVPN; then
        ok "AmneziaVPN установлен. Запуск: AmneziaVPN (или из меню приложений)"
    else
        warn "Авто-установка не удалась — запусти установщик вручную из графической сессии: $run"
    fi
}

do_docker() {
    step "10. Docker (docker.io + docker-compose из репозитория Kali)"
    # Примечание: в Debian/Kali НЕТ пакета docker-compose-v2 (это имя из офиц.
    # репозитория Docker). Здесь Compose v2 лежит в пакете docker-compose (версия 2.x).
    if have docker && pkg_installed docker.io; then
        ok "Docker уже установлен ($(docker --version 2>/dev/null)). Пропускаю установку."
    else
        if sudo apt install -y docker.io docker-compose; then
            ok "Docker установлен"
        else
            warn "Не удалось поставить docker.io из репозитория Kali."
            return 1
        fi
    fi
    # Служба демона: включаем и запускаем
    sudo systemctl enable --now docker 2>/dev/null || warn "Не удалось включить службу docker"
    # Текущего пользователя — в группу docker, чтобы работать без sudo
    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
        sudo usermod -aG docker "$USER"
        warn "Добавил $USER в группу docker. Перелогинься (или 'newgrp docker'), чтобы docker работал без sudo."
    fi
    docker --version 2>/dev/null | tee -a "$LOG_FILE"
}
