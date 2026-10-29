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
undo_torbrowser() {
    step "Откат: Tor Browser"
    apt_purge torbrowser-launcher
    ok "torbrowser-launcher удалён. (Скачанный браузер и закладки оставлены — убери вручную: rm -rf ~/.local/share/torbrowser ~/.cache/torbrowser ~/.config/torbrowser)"
}
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
# Откат кастомизации
# ----------------------------------------------------------------------------
undo_gnome() {
    step "Откат: окружение GNOME"
    if [[ "$(state_get gnome.preinstalled)" != no ]]; then
        warn "GNOME стоял до скрипта (или шаг не запускался) — не удаляю."
        state_del gnome.preinstalled gnome.dm
        return 0
    fi
    local dm
    dm="$(state_get gnome.dm)"
    apt_purge kali-desktop-gnome gdm3
    # экран входа — как был до установки GNOME
    if [[ -n "$dm" ]]; then
        echo "$dm" | sudo tee /etc/X11/default-display-manager >/dev/null
        sudo systemctl enable --force "$(basename "$dm")" 2>/dev/null || true
    fi
    state_del gnome.preinstalled gnome.dm
    ok "GNOME удалён, экран входа возвращён. (Настройки GNOME в ~/.config/dconf оставлены.)"
}

undo_gnomeext() {
    step "Откат: расширения GNOME"
    local pkgs=()
    read -ra pkgs <<<"$(state_get gnomeext.pkgs)"
    if have gsettings && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        state_has gnomeext.enabled \
            && gsettings set org.gnome.shell enabled-extensions "$(state_get gnomeext.enabled)" 2>/dev/null
        [[ -n "$(state_get gnomeext.disable_user)" ]] \
            && gsettings set org.gnome.shell disable-user-extensions "$(state_get gnomeext.disable_user)" 2>/dev/null
    fi
    [[ ${#pkgs[@]} -gt 0 ]] && apt_purge "${pkgs[@]}"
    state_del gnomeext.pkgs gnomeext.enabled gnomeext.disable_user
    ok "Расширения, поставленные скриптом, удалены; список включённых возвращён."
}

undo_hyprland() {
    step "Откат: Hyprland"
    local pkgs=() d b
    # конфиги ~/.config — как были до установки
    for b in "${STATE_DIR}/hyprland-backup/"*; do
        [[ -e "$b" ]] || continue
        d="$(basename "$b")"
        if [[ "$d" == *.absent ]]; then
            rm -rf "${HOME:?}/.config/${d%.absent}"
        else
            rm -rf "${HOME:?}/.config/$d"
            cp -a "$b" "$HOME/.config/$d"
        fi
    done
    rm -rf "${STATE_DIR}/hyprland-backup"
    rm -f "$HOME/.local/share/rofi/themes/"*.rasi 2>/dev/null
    if state_has hyprland.awww; then
        sudo rm -f /usr/local/bin/awww /usr/local/bin/awww-daemon /usr/local/bin/swww /usr/local/bin/swww-daemon
    fi
    state_has hyprland.wallust && sudo rm -f /usr/local/bin/wallust
    state_has hyprland.font && ! state_has xtheme.font && rm -rf "$HOME/.local/share/fonts/JetBrainsMonoNerd" && fc-cache -f >/dev/null
    state_has hyprland.walls && rm -rf "$(state_get hyprland.walls)"
    read -ra pkgs <<<"$(state_get hyprland.pkgs)"
    [[ ${#pkgs[@]} -gt 0 ]] && apt_purge "${pkgs[@]}"
    state_del hyprland.pkgs hyprland.awww hyprland.wallust hyprland.font hyprland.walls
    ok "Hyprland удалён, конфиги ~/.config возвращены как были."
}

# Удалить пакеты, которые поставил шаг (список в state-ключе)
apt_purge_tracked() {
    local pkgs=()
    read -ra pkgs <<<"$(state_get "$1")"
    [[ ${#pkgs[@]} -gt 0 ]] && apt_purge "${pkgs[@]}"
    state_del "$1"
}

undo_xtheme() {
    step "Откат: XFCE — тема, иконки, курсор, шрифты"
    local p t
    for p in /Net/ThemeName /Net/IconThemeName /Gtk/CursorThemeName /Gtk/FontName /Gtk/MonospaceFontName; do
        xfconf_restore xsettings "$p"
    done
    xfconf_restore xfwm4 /general/theme
    xfconf_restore xfwm4 /general/title_font
    if state_has xtheme.folders; then
        curl -fsSL -o "${DOWNLOAD_DIR}/papirus-folders" \
            https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders \
            && sudo bash "${DOWNLOAD_DIR}/papirus-folders" -D --theme Papirus-Dark >/dev/null
        state_del xtheme.folders
    fi
    while read -r t; do [[ -n "$t" ]] && rm -rf "${HOME}/.themes/${t:?}"*; done < <(state_get xtheme.themes)
    state_del xtheme.themes
    # шрифт общий с Hyprland — удаляем, только если Hyprland его не ставил
    if state_has xtheme.font && ! state_has hyprland.font; then
        rm -rf "$HOME/.local/share/fonts/JetBrainsMonoNerd" && fc-cache -f >/dev/null
    fi
    state_del xtheme.font
    apt_purge_tracked xtheme.pkgs
    ok "Оформление XFCE возвращено как было."
}

undo_xpanel() {
    step "Откат: XFCE — панель"
    # xfconfd держит конфиг в памяти — останавливаем панель и демон, затем возвращаем файл
    xfce4-panel --quit 2>/dev/null; pkill -x xfconfd 2>/dev/null; sleep 1
    state_restore_file "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" xpanel.xml
    (xfce4-panel >/dev/null 2>&1 &)
    apt_purge_tracked xpanel.pkgs   # docklike от старых версий шага
    ok "Панель возвращена как была."
}

undo_xpicom() {
    step "Откат: XFCE — Picom"
    pkill -x picom 2>/dev/null
    rm -f "$HOME/.config/autostart/kali-setup-picom.desktop"
    state_restore_file "$HOME/.config/picom/picom.conf" xpicom.conf
    xfconf_restore xfwm4 /general/use_compositing
    apt_purge_tracked xpicom.pkgs
    ok "Picom убран, встроенный композитор xfwm4 возвращён."
}

undo_xextras() {
    step "Откат: XFCE — Rofi, Conky, обои"
    local p w
    xfconf_restore xfce4-keyboard-shortcuts "/commands/custom/<Super>d"
    xfconf_restore xfce4-keyboard-shortcuts "/commands/custom/<Super>n"
    # ~/notes.txt — твои заметки, не удаляем
    state_del xextras.notes
    rm -f "$HOME/.local/share/rofi/themes/kali-setup.rasi"
    pkill -f 'conky.*kali-setup.conf' 2>/dev/null
    rm -f "$HOME/.config/autostart/kali-setup-conky.desktop" "$HOME/.config/conky/kali-setup.conf" \
          "$HOME/.config/conky/kali-setup.lua" "$HOME/.config/conky/kali-setup-colors.lua"
    for p in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$'); do
        xfconf_restore xfce4-desktop "$p"
    done
    while read -r w; do [[ -n "$w" ]] && rm -f "$w"; done < <(state_get xextras.walls)
    state_del xextras.walls
    apt_purge_tracked xextras.pkgs
    ok "Rofi-хоткей, Conky и обои возвращены как было."
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
        torbrowser) undo_torbrowser ;;
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
        gnome)     undo_gnome ;;
        gnomeext)  undo_gnomeext ;;
        hyprland)  undo_hyprland ;;
        xtheme)    undo_xtheme ;;
        xpanel)    undo_xpanel ;;
        xpicom)    undo_xpicom ;;
        xextras)   undo_xextras ;;
        *) err "Нечего откатывать: $1"; return 1 ;;
    esac
}
