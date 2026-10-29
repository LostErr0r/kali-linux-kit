#!/usr/bin/env bash
# modules/uninstall.sh — откат: удалить приложения / вернуть настройки назад.
# Каждая функция откатывает ОДИН пункт. Диспетчер — run_undo.

# ----------------------------------------------------------------------------
# Откат приложений
# ----------------------------------------------------------------------------
undo_claude() {
    step "Откат: Claude Desktop"
    sudo apt purge -y claude-desktop 2>/dev/null || true
    sudo rm -f /etc/apt/sources.list.d/claude-desktop.list \
               /usr/share/keyrings/claude-desktop-archive-keyring.asc
    sudo apt autoremove -y 2>/dev/null || true
    ok "Claude Desktop удалён (пакет + репозиторий + ключ)."
}

undo_discord()  { step "Откат: Discord";  apt_purge discord;  ok "Discord удалён."; }
undo_telegram() { step "Откат: Telegram"; apt_purge telegram-desktop; ok "Telegram удалён."; }
undo_keepassxc() { step "Откат: KeePassXC"; apt_purge keepassxc; ok "KeePassXC удалён."; }
undo_obsidian() { step "Откат: Obsidian"; apt_purge obsidian; ok "Obsidian удалён."; }
undo_happ()     { step "Откат: Happ";     apt_purge happ;     ok "Happ удалён."; }

undo_hexstrike() {
    step "Откат: HexStrike AI"
    pkg_installed hexstrike-ai && apt_purge hexstrike-ai
    [[ -d "$HEXSTRIKE_DIR" ]] && rm -rf "$HEXSTRIKE_DIR"
    ok "HexStrike удалён."
}

undo_docker() {
    step "Откат: Docker"
    sudo systemctl disable --now docker 2>/dev/null || true
    apt_purge docker.io docker-compose
    ok "Docker удалён. (Пользователь оставлен в группе docker — убери вручную при желании: sudo gpasswd -d \$USER docker)"
}

undo_deepseek() {
    step "Откат: DeepSeek Harness (dsh)"
    sudo npm uninstall -g @deepseek-ai/dsh 2>/dev/null || warn "npm не смог удалить dsh (возможно, уже удалён)."
    ok "DeepSeek Harness удалён. (Node.js оставлен — убери вручную: sudo apt purge nodejs)"
}

undo_graphify() {
    step "Откат: Graphify"
    pipx uninstall graphifyy 2>/dev/null || pip uninstall -y graphifyy 2>/dev/null || true
    # снять регистрацию скила у ассистента, если команда это умеет
    have graphify && graphify uninstall 2>/dev/null || true
    ok "Graphify CLI удалён. (Папка проекта skills/graphify не трогается.)"
}

undo_amnezia() {
    step "Откат: AmneziaVPN"
    sudo systemctl disable --now AmneziaVPN.service 2>/dev/null || true
    if [[ -x /opt/AmneziaVPN/maintenancetool ]]; then
        sudo /opt/AmneziaVPN/maintenancetool purge --confirm-command 2>/dev/null \
            || sudo /opt/AmneziaVPN/maintenancetool --confirm-command purge 2>/dev/null || true
    fi
    sudo rm -rf /opt/AmneziaVPN \
                /etc/systemd/system/AmneziaVPN.service \
                /etc/systemd/system/multi-user.target.wants/AmneziaVPN.service
    sudo systemctl daemon-reload 2>/dev/null || true
    rm -rf "${HOME}/amneziavpn-installer"
    ok "AmneziaVPN удалён. (systemd-resolved оставлен — он полезен и сам по себе)"
}

# ----------------------------------------------------------------------------
# Откат настройки системы
# ----------------------------------------------------------------------------
undo_time() {
    step "Откат: время и часовой пояс"
    if state_has time.tz; then
        sudo timedatectl set-timezone "$(state_get time.tz)" 2>/dev/null \
            || sudo timedatectl set-timezone UTC
    fi
    state_has time.ntp && sudo timedatectl set-ntp "$(state_get time.ntp)" 2>/dev/null || true
    local p
    for p in $(xfce_clock_plugins); do
        xfconf_restore xfce4-panel "${p}/digital-time-format"
        xfconf_restore xfce4-panel "${p}/digital-format"
    done
    state_del time.tz time.ntp
    ok "Часовой пояс, синхронизация и формат часов возвращены."
}

undo_keyboard() {
    step "Откат: раскладка клавиатуры"
    local p
    for p in /Default/XkbDisable /Default/XkbLayout /Default/XkbVariant /Default/XkbOptions/Group; do
        xfconf_restore keyboard-layout "$p"
    done
    ok "Раскладки и переключение возвращены как были."
}

undo_nolock() {
    step "Откат: блокировка экрана"
    local p
    for p in /saver/idle-activation/enabled /lock/saver-activation/enabled; do
        xfconf_restore xfce4-screensaver "$p"
    done
    for p in dpms-enabled blank-on-ac blank-on-battery; do
        xfconf_restore xfce4-power-manager "/xfce4-power-manager/$p"
    done
    ok "Блокировка и гашение экрана по таймеру возвращены."
}

# ----------------------------------------------------------------------------
# Диспетчер отката одного пункта по ключу
# ----------------------------------------------------------------------------
run_undo() {
    case "$1" in
        claude)    undo_claude ;;
        discord)   undo_discord ;;
        telegram)  undo_telegram ;;
        keepassxc) undo_keepassxc ;;
        obsidian)  undo_obsidian ;;
        happ)      undo_happ ;;
        amnezia)   undo_amnezia ;;
        hexstrike) undo_hexstrike ;;
        docker)    undo_docker ;;
        deepseek)  undo_deepseek ;;
        graphify)  undo_graphify ;;
        time)      undo_time ;;
        keyboard)  undo_keyboard ;;
        nolock)    undo_nolock ;;
        *) err "Нечего откатывать: $1"; return 1 ;;
    esac
}
