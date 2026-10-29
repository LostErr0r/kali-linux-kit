#!/usr/bin/env bash
# modules/custom.sh — кастомизация: группы GNOME, Hyprland, XFCE.
# Каждый шаг — функция do_custom_<ключ>, ключ добавляется в CUSTOM_STEPS/CUSTOM_DESC
# и run_step в setup.sh, откат — в modules/uninstall.sh.

# Расширения GNOME Shell (все из репозитория Kali)
GNOME_EXT_PKGS=(
    gnome-shell-extension-dashtodock        # док снизу
    gnome-shell-extension-appindicator      # значки в трее
    gnome-shell-extension-blur-my-shell     # размытие панели и обзора
    gnome-shell-extension-user-theme        # свои темы для Shell
    gnome-shell-extension-just-perfection   # тонкая настройка интерфейса
    gnome-shell-extension-caffeine          # не засыпать по кнопке
    gnome-shell-extension-system-monitor    # CPU/RAM/сеть на панели
    gnome-shell-extension-freon             # температура датчиков
    gnome-shell-extension-manager           # приложение «Extension Manager»
)

# UUID расширений, которые ставит пакет (по metadata.json в его файлах)
gnome_ext_uuids() {
    local p
    for p in "$@"; do
        dpkg -L "$p" 2>/dev/null \
            | grep -E '^/usr/share/gnome-shell/extensions/[^/]+/metadata\.json$' \
            | awk -F/ '{print $(NF-1)}'
    done
}

do_custom_gnome() {
    step "Кастомизация: окружение GNOME (kali-desktop-gnome)"
    if pkg_installed kali-desktop-gnome; then
        state_set_once gnome.preinstalled yes
        ok "GNOME уже установлен. Пропускаю."
        return
    fi
    state_set_once gnome.preinstalled no
    # Экран входа оставляем прежним (LightDM): gdm3 при установке спрашивает, какой DM главный
    local dm_before
    dm_before="$(cat /etc/X11/default-display-manager 2>/dev/null)"
    state_set_once gnome.dm "$dm_before"
    echo "gdm3 shared/default-x-display-manager select lightdm" | sudo debconf-set-selections
    echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y kali-desktop-gnome; then
        warn "Не удалось поставить kali-desktop-gnome"
        return 1
    fi
    if [[ -n "$dm_before" && "$(cat /etc/X11/default-display-manager 2>/dev/null)" != "$dm_before" ]]; then
        echo "$dm_before" | sudo tee /etc/X11/default-display-manager >/dev/null
        sudo systemctl enable --force "$(basename "$dm_before")" 2>/dev/null || true
    fi
    ok "GNOME установлен. Выйди из сессии и на экране входа выбери сессию «GNOME»."
}

do_custom_gnomeext() {
    step "Кастомизация: расширения GNOME"
    local p new=() uuids=() u cur list
    for p in "${GNOME_EXT_PKGS[@]}"; do pkg_installed "$p" || new+=("$p"); done
    # запоминаем только то, что поставили мы — откат не тронет уже стоявшее
    state_set_once gnomeext.pkgs "${new[*]}"
    if [[ ${#new[@]} -gt 0 ]]; then
        sudo apt install -y "${new[@]}" || { warn "Не удалось поставить расширения"; return 1; }
    fi
    pkg_installed lm-sensors || sudo apt install -y lm-sensors 2>/dev/null || true   # для Freon
    # Включаем расширения в настройках пользователя (сработает при следующем входе в GNOME)
    if ! have gsettings || [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        warn "Нет gsettings/сессии D-Bus — включи расширения вручную в «Extension Manager»."
        return 0
    fi
    cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || {
        warn "Схема org.gnome.shell не найдена — сначала поставь шаг gnome."
        return 0
    }
    state_set_once gnomeext.enabled "$cur"
    state_set_once gnomeext.disable_user "$(gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)"
    while read -r u; do [[ -n "$u" ]] && uuids+=("$u"); done < <(gnome_ext_uuids "${GNOME_EXT_PKGS[@]}")
    # дописываем к уже включённым, без дублей
    list="$cur"
    [[ "$list" == "@as []" ]] && list="[]"
    for u in "${uuids[@]}"; do
        [[ "$list" == *"'$u'"* ]] && continue
        if [[ "$list" == "[]" ]]; then list="['$u']"; else list="${list%]}, '$u']"; fi
    done
    gsettings set org.gnome.shell enabled-extensions "$list"
    gsettings set org.gnome.shell disable-user-extensions false
    ok "Расширения поставлены и включены (${#uuids[@]} шт.). Настройка — в приложении «Extension Manager»."
}

# ----------------------------------------------------------------------------
# Hyprland в стиле JaKooLit: пакеты из Kali + дотфайлы JaKooLit/Hyprland-Dots
# ----------------------------------------------------------------------------
HYPR_DOTS_REPO="https://github.com/JaKooLit/Hyprland-Dots"
HYPR_AWWW_REPO="https://codeberg.org/LGFae/awww"    # обои (бывший swww)
HYPR_CONFIGS=(hypr waybar rofi swaync wlogout kitty quickshell wallust btop cava fastfetch swappy Kvantum qt5ct qt6ct)
HYPR_PKGS=(
    hyprland hyprlock hypridle hyprsunset hyprpolkitagent xdg-desktop-portal-hyprland
    qml6-module-org-hyprland-style quickshell
    waybar rofi sway-notification-center wlogout kitty
    cliphist grim slurp swappy wl-clipboard
    jq bc yad imagemagick libnotify-bin python3-requests inxi
    pamixer pavucontrol playerctl brightnessctl network-manager-applet mate-polkit
    nwg-look nwg-displays qt5ct qt6ct qt-style-kvantum qt-style-kvantum-themes
    btop cava fastfetch mpv gvfs xdg-user-dirs
    bibata-cursor-theme papirus-icon-theme
    fonts-jetbrains-mono fonts-firacode fonts-font-awesome fonts-noto-color-emoji
    # для сборки awww и wallust
    cargo git build-essential pkgconf liblz4-dev libwayland-dev libwayland-bin wayland-protocols
)

# Есть ли 3D-ускорение (в VM без него Hyprland тормозит или не стартует)
gpu_accel_ok() {
    have glxinfo || return 0
    ! glxinfo -B 2>/dev/null | grep -qiE 'Accelerated: no|llvmpipe|softpipe'
}

do_custom_hyprland() {
    step "Кастомизация: Hyprland (стиль JaKooLit)"
    if ! gpu_accel_ok; then
        warn "Нет 3D-ускорения (рендер llvmpipe). В VMware: Settings → Display → «Accelerate 3D graphics»."
        warn "Без этого Hyprland будет тормозить или не запустится. Ставлю дальше."
    fi
    local p new=() tmp="${DOWNLOAD_DIR}/hypr" pics d
    pics="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"

    # 1) Пакеты (запоминаем только новые — откат не тронет уже стоявшее)
    for p in "${HYPR_PKGS[@]}"; do pkg_installed "$p" || new+=("$p"); done
    state_set_once hyprland.pkgs "${new[*]}"
    if [[ ${#new[@]} -gt 0 ]]; then
        sudo apt install -y "${new[@]}" || { warn "Не удалось поставить пакеты Hyprland"; return 1; }
    fi

    # 2) awww (обои) и wallust (цвета под обои) — их нет в репозитории, собираем
    mkdir -p "$tmp"
    if ! have awww; then
        log "Собираю awww (несколько минут)..."
        if git clone -q --depth=1 "$HYPR_AWWW_REPO" "$tmp/awww" \
            && (cd "$tmp/awww" && cargo build --release); then
            sudo install -m 755 "$tmp/awww/target/release/awww" "$tmp/awww/target/release/awww-daemon" /usr/local/bin/
            state_set_once hyprland.awww yes
        else
            warn "awww не собрался — обои не будут меняться."
        fi
    fi
    # дотфайлы вызывают старые имена swww/swww-daemon
    for p in swww swww-daemon; do
        [[ -x /usr/local/bin/a${p#s} && ! -e /usr/local/bin/$p ]] && sudo ln -s "a${p#s}" "/usr/local/bin/$p"
    done
    if ! have wallust; then
        log "Собираю wallust (несколько минут)..."
        if cargo install --locked --root "$tmp/wallust" wallust; then
            sudo install -m 755 "$tmp/wallust/bin/wallust" /usr/local/bin/wallust
            state_set_once hyprland.wallust yes
        else
            warn "wallust не собрался — цвета не будут подстраиваться под обои."
        fi
    fi

    # 3) Шрифт JetBrainsMono Nerd (иконки в Waybar)
    install_nerd_font && state_set_once hyprland.font yes

    # 4) Дотфайлы: бэкап текущих ~/.config/<папка>, затем копия из репозитория
    if ! git clone -q --depth=1 "$HYPR_DOTS_REPO" "$tmp/dots"; then
        warn "Не скачались дотфайлы JaKooLit"
        return 1
    fi
    mkdir -p "${STATE_DIR}/hyprland-backup" "$HOME/.config"
    for d in "${HYPR_CONFIGS[@]}"; do
        [[ -d "$tmp/dots/config/$d" ]] || continue
        if ! state_has "hyprland-backup/$d" && ! state_has "hyprland-backup/$d.absent"; then
            if [[ -e "$HOME/.config/$d" ]]; then cp -a "$HOME/.config/$d" "${STATE_DIR}/hyprland-backup/$d"
            else : > "${STATE_DIR}/hyprland-backup/$d.absent"; fi
        fi
        rm -rf "${HOME:?}/.config/$d"
        cp -a "$tmp/dots/config/$d" "$HOME/.config/$d"
    done
    chmod +x "$HOME/.config/hypr/scripts/"* "$HOME/.config/hypr/UserScripts/"* "$HOME/.config/hypr/initial-boot.sh" 2>/dev/null
    # Waybar: конфиг по умолчанию (десктоп)
    ln -sfn "$HOME/.config/waybar/configs/[TOP] Default" "$HOME/.config/waybar/config"
    ln -sfn "$HOME/.config/waybar/style/[Extra] Neon Circuit.css" "$HOME/.config/waybar/style.css"
    # Rofi ищет темы в ~/.local/share/rofi/themes
    mkdir -p "$HOME/.local/share/rofi/themes"
    ln -snf "$HOME/.config/rofi/themes/"* "$HOME/.local/share/rofi/themes/" 2>/dev/null
    # Обои
    if [[ ! -d "$pics/wallpapers" ]]; then
        mkdir -p "$pics" && cp -r "$tmp/dots/wallpapers" "$pics/wallpapers" && state_set_once hyprland.walls "$pics/wallpapers"
    fi
    # Раскладка us + ru, переключение Alt+Shift (Win+Space в Hyprland — плавающее окно)
    sed -i -e 's/^\(\s*kb_layout\s*=\).*/\1 us,ru/' -e 's/^\(\s*kb_options\s*=\).*/\1 grp:alt_shift_toggle/' \
        "$HOME/.config/hypr/configs/SystemSettings.conf"

    ok "Hyprland установлен. Выйди из сессии и на экране входа выбери «Hyprland»."
    ok "Подсказка по клавишам — SUPER+H. Терминал — SUPER+Enter, меню — SUPER+D, раскладка — Alt+Shift."
}

# ----------------------------------------------------------------------------
# XFCE: палитры (тема, иконки, рамки окон, цвета Rofi/Conky/обоев)
# ----------------------------------------------------------------------------
XFCE_PALETTES=(catppuccin nordic orchis dracula)
declare -A PAL_DESC=(
    [catppuccin]="Catppuccin Mocha — пастельная тёмная"
    [nordic]="Nordic — холодная сине-серая"
    [orchis]="Orchis — в стиле macOS / Material"
    [dracula]="Dracula — тёмная фиолетовая"
)
declare -A PAL_GTK=(          # имя темы GTK и xfwm4
    [catppuccin]="catppuccin-mocha-mauve-standard+default" [nordic]="Nordic"
    [orchis]="Orchis-Dark" [dracula]="Dracula"
)
declare -A PAL_URL=(          # откуда брать тему (orchis — из репозитория Kali)
    [catppuccin]="https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-mauve-standard%2Bdefault.zip"
    [nordic]="https://github.com/EliverLara/Nordic/releases/download/v2.2.0/Nordic.tar.xz"
    [dracula]="https://github.com/dracula/gtk/releases/download/v4.0.0/Dracula.tar.xz"
)
declare -A PAL_FOLDER=( [catppuccin]=violet [nordic]=nordic [orchis]=blue [dracula]=violet )   # цвет папок Papirus
declare -A PAL_BG=(  [catppuccin]="#1e1e2e" [nordic]="#2e3440" [orchis]="#212121" [dracula]="#282a36" )
declare -A PAL_FG=(  [catppuccin]="#cdd6f4" [nordic]="#d8dee9" [orchis]="#eeeeee" [dracula]="#f8f8f2" )
declare -A PAL_ACC=( [catppuccin]="#cba6f7" [nordic]="#88c0d0" [orchis]="#1a73e8" [dracula]="#bd93f9" )

XFCE_PALETTE=""
# Палитра выбирается один раз за запуск. Без меню: PALETTE=nordic ./setup.sh xtheme
xfce_palette() {
    [[ -n "$XFCE_PALETTE" ]] && return 0
    local last
    last="$(cat "${STATE_DIR}/xfce.palette" 2>/dev/null)"
    XFCE_PALETTE="${PALETTE:-}"
    if [[ -z "$XFCE_PALETTE" && -t 0 ]]; then
        XFCE_PALETTE=$(ui_radiolist "Палитра XFCE" "Выбери палитру оформления" \
            XFCE_PALETTES PAL_DESC "${last:-catppuccin}") || XFCE_PALETTE=""
    fi
    [[ -n "${PAL_DESC[${XFCE_PALETTE:-x}]:-}" ]] || XFCE_PALETTE="${last:-catppuccin}"
    mkdir -p "$STATE_DIR"; echo "$XFCE_PALETTE" > "${STATE_DIR}/xfce.palette"
    log "Палитра: ${PAL_DESC[$XFCE_PALETTE]}"
}

# Поставить пакеты, запомнив новые в state-ключ <key> (для отката)
apt_install_tracked() {
    local key="$1" p new=(); shift
    for p in "$@"; do pkg_installed "$p" || new+=("$p"); done
    state_set_once "$key" "${new[*]}"
    [[ ${#new[@]} -eq 0 ]] || sudo apt install -y "${new[@]}"
}

# JetBrainsMono Nerd Font в ~/.local/share/fonts (общий для Hyprland и XFCE)
install_nerd_font() {
    [[ -d "$HOME/.local/share/fonts/JetBrainsMonoNerd" ]] && return 1
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerd"
    curl -fsSL --retry 3 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
        | tar -xJ -C "$HOME/.local/share/fonts/JetBrainsMonoNerd" && fc-cache -f >/dev/null
}

do_custom_xtheme() {
    step "XFCE: тема, иконки, курсор, шрифты"
    have_xfce || { warn "Не XFCE — пропускаю."; return 0; }
    xfce_palette
    local pal="$XFCE_PALETTE" theme="${PAL_GTK[$XFCE_PALETTE]}" f="${DOWNLOAD_DIR}/theme"
    apt_install_tracked xtheme.pkgs papirus-icon-theme bibata-cursor-theme fonts-inter fonts-jetbrains-mono \
        $([[ "$pal" == orchis ]] && echo orchis-gtk-theme)
    # Тема GTK + рамки окон — в ~/.themes
    if [[ -n "${PAL_URL[$pal]:-}" && ! -d "$HOME/.themes/$theme" ]]; then
        mkdir -p "$HOME/.themes" "$f"
        if curl -fL --retry 3 -o "$f/a" "${PAL_URL[$pal]}"; then
            if [[ "${PAL_URL[$pal]}" == *.zip ]]; then unzip -q -o "$f/a" -d "$HOME/.themes"
            else tar -xJf "$f/a" -C "$HOME/.themes"; fi
            echo "$theme" >> "${STATE_DIR}/xtheme.themes"
        else
            warn "Не скачалась тема $theme"; return 1
        fi
    fi
    install_nerd_font && state_set_once xtheme.font yes
    xfconf_set xsettings /Net/ThemeName           string "$theme"
    xfconf_set xsettings /Net/IconThemeName       string "Papirus-Dark"
    xfconf_set xsettings /Gtk/CursorThemeName     string "Bibata-Modern-Ice"
    xfconf_set xsettings /Gtk/FontName            string "Inter 10"
    xfconf_set xsettings /Gtk/MonospaceFontName   string "JetBrainsMono Nerd Font 10"
    xfconf_set xfwm4     /general/theme           string "$theme"
    xfconf_set xfwm4     /general/title_font      string "Inter Bold 10"
    # Цвет папок Papirus под палитру
    if curl -fsSL -o "${DOWNLOAD_DIR}/papirus-folders" \
        https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders; then
        sudo bash "${DOWNLOAD_DIR}/papirus-folders" -C "${PAL_FOLDER[$pal]}" --theme Papirus-Dark >/dev/null \
            && state_set_once xtheme.folders yes
    fi
    ok "Оформление: ${PAL_DESC[$pal]}, иконки Papirus-Dark, курсор Bibata, шрифты Inter + JetBrainsMono Nerd"
}

# Часы — между двумя растягивающимися разделителями (по центру свободного места),
# значок уведомлений убирается с панели (сами уведомления работают)
xfce_panel_center_clock() {
    local ids=() i t clock="" notif="" sep="" new order=() args=()
    while read -r i; do [[ "$i" =~ ^[0-9]+$ ]] && ids+=("$i"); done \
        < <(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null)
    for i in "${ids[@]}"; do
        t="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$i" 2>/dev/null)"
        case "$t" in
            clock) clock=$i ;;
            notification-plugin) notif=$i ;;
            separator) [[ -z "$sep" && "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$i/expand" 2>/dev/null)" == true ]] && sep=$i ;;
        esac
    done
    [[ -n "$clock" && -n "$sep" ]] || { warn "Не нашёл часы или разделитель на панели — часы не двигаю."; return 0; }
    # часы уже стоят сразу за разделителем (повторный запуск) — только убираем уведомления
    local centered=0
    for i in "${!ids[@]}"; do
        [[ "${ids[i]}" == "$clock" && $i -gt 0 && "${ids[i-1]}" == "$sep" ]] && centered=1
    done
    [[ $centered -eq 1 && -z "$notif" ]] && return 0
    if [[ $centered -eq 0 ]]; then
        new=$(( $(xfconf-query -c xfce4-panel -l | grep -oP '^/plugins/plugin-\K[0-9]+' | sort -n | tail -1) + 1 ))
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$new"        -n -t string -s separator
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$new/expand" -n -t bool   -s true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$new/style"  -n -t uint   -s 0
    fi
    for i in "${ids[@]}"; do
        [[ "$i" == "$notif" ]] && continue
        [[ $centered -eq 0 && "$i" == "$clock" ]] && continue
        order+=("$i")
        [[ $centered -eq 0 && "$i" == "$sep" ]] && order+=("$clock" "$new")
    done
    for i in "${order[@]}"; do args+=(-t int -s "$i"); done
    xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${args[@]}" --force-array
}

do_custom_xpanel() {
    step "XFCE: верхняя панель побольше и полупрозрачная"
    have_xfce || { warn "Не XFCE — пропускаю."; return 0; }
    # Снимок всей конфигурации панели — откат вернёт её целиком
    state_backup_file "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" xpanel.xml
    # Высота 36 px, полупрозрачная (прозрачность работает с композитором)
    xfconf-query -c xfce4-panel -p /panels/panel-1/size -s 36 2>/dev/null
    xfconf-query -c xfce4-panel -p /panels/panel-1/leave-opacity -n -t int -s 85 2>/dev/null \
        || xfconf-query -c xfce4-panel -p /panels/panel-1/leave-opacity -s 85
    xfce_panel_center_clock
    xfce4-panel -r >/dev/null 2>&1 &
    ok "Верхняя панель: высота 36 px, полупрозрачная, часы по центру, без значка уведомлений."
}

do_custom_xpicom() {
    step "XFCE: Picom — скругления, тени, размытие, анимации"
    have_xfce || { warn "Не XFCE — пропускаю."; return 0; }
    apt_install_tracked xpicom.pkgs picom
    local backend=glx blur="dual_kawase"
    if ! gpu_accel_ok; then
        warn "Нет 3D-ускорения — ставлю лёгкий режим без размытия (backend xrender)."
        backend=xrender; blur="none"
    fi
    local conf="$HOME/.config/picom/picom.conf"
    state_backup_file "$conf" xpicom.conf
    mkdir -p "$(dirname "$conf")"
    cat > "$conf" <<PICOM
# kali-setup: picom для XFCE
backend = "${backend}";
vsync = true;
corner-radius = 10;
rounded-corners-exclude = [ "window_type = 'dock'", "window_type = 'desktop'", "class_g = 'xfce4-panel'" ];
shadow = true;
shadow-radius = 14;
shadow-opacity = 0.45;
shadow-offset-x = -10;
shadow-offset-y = -10;
shadow-exclude = [ "window_type = 'dock'", "window_type = 'desktop'", "class_g = 'xfce4-panel'", "_GTK_FRAME_EXTENTS@" ];
fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
blur-method = "${blur}";
blur-strength = 5;
blur-background-exclude = [ "window_type = 'desktop'", "_GTK_FRAME_EXTENTS@" ];
PICOM
    # Встроенный композитор xfwm4 выключаем — вместо него picom
    xfconf_set xfwm4 /general/use_compositing bool false
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/kali-setup-picom.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Picom (kali-setup)
Exec=picom -b
X-GNOME-Autostart-enabled=true
DESK
    pkill -x picom 2>/dev/null; [[ -n "${DISPLAY:-}" ]] && picom -b 2>/dev/null
    ok "Picom включён (backend ${backend}), запускается при входе."
}

do_custom_xextras() {
    step "XFCE: Rofi (SUPER+D), Conky, обои"
    have_xfce || { warn "Не XFCE — пропускаю."; return 0; }
    xfce_palette
    local pal="$XFCE_PALETTE" bg="${PAL_BG[$XFCE_PALETTE]}" fg="${PAL_FG[$XFCE_PALETTE]}" acc="${PAL_ACC[$XFCE_PALETTE]}"
    apt_install_tracked xextras.pkgs rofi conky-all imagemagick fonts-inter mousepad
    # Rofi: своя тема в отдельном файле (конфиги Hyprland в ~/.config/rofi не трогаем)
    mkdir -p "$HOME/.local/share/rofi/themes"
    cat > "$HOME/.local/share/rofi/themes/kali-setup.rasi" <<RASI
* { bg: ${bg}e6; fg: ${fg}; acc: ${acc}; background-color: transparent; text-color: @fg; font: "Inter 12"; }
window { width: 640px; border: 2px; border-color: @acc; border-radius: 14px; background-color: @bg; padding: 18px; }
inputbar { children: [prompt, entry]; spacing: 10px; padding: 10px; border-radius: 10px; background-color: ${acc}33; }
prompt { text-color: @acc; }
listview { lines: 8; columns: 1; spacing: 4px; margin: 12px 0 0 0; }
element { padding: 8px 10px; border-radius: 8px; spacing: 10px; }
element selected { background-color: @acc; text-color: @bg; }
element-icon { size: 28px; }
element-text { text-color: inherit; vertical-align: 0.5; }
RASI
    xfconf_set xfce4-keyboard-shortcuts "/commands/custom/<Super>d" string \
        "rofi -show drun -show-icons -theme kali-setup"
    # Conky: виджет на Lua/Cairo (часы, кольца CPU/RAM/диск, сеть, VPN, заметки)
    mkdir -p "$HOME/.config/conky" "$HOME/.config/autostart"
    cp -f "${SCRIPT_DIR}/assets/conky/kali-setup.lua" "$HOME/.config/conky/kali-setup.lua"
    printf "return { bg = '%s', fg = '%s', acc = '%s' }\n" "$bg" "$fg" "$acc" \
        > "$HOME/.config/conky/kali-setup-colors.lua"
    cat > "$HOME/.config/conky/kali-setup.conf" <<'CONKY'
conky.config = {
    alignment = 'top_right', gap_x = 30, gap_y = 60,
    own_window = true, own_window_type = 'desktop', own_window_transparent = true,
    own_window_argb_visual = true,   -- conky пишет «removed», но без него фон не прозрачный
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    double_buffer = true, update_interval = 1,
    minimum_width = 320, minimum_height = 640, maximum_width = 320,
    lua_load = '~/.config/conky/kali-setup.lua', lua_draw_hook_post = 'main',
};
conky.text = [[ ]];
CONKY
    # Заметки для виджета: ~/notes.txt (не перезаписываем), правка — SUPER+N
    if [[ ! -f "$HOME/notes.txt" ]]; then
        printf '%s\n' '# Сегодня' 'Win+N — открыть редактор заметок' 'Пиши сюда — виджет покажет сразу' 'x так помечается сделанное' > "$HOME/notes.txt"
        state_set_once xextras.notes created
    fi
    xfconf_set xfce4-keyboard-shortcuts "/commands/custom/<Super>n" string "mousepad $HOME/notes.txt"
    cat > "$HOME/.config/autostart/kali-setup-conky.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Conky (kali-setup)
Exec=sh -c "sleep 3; conky -d -c $HOME/.config/conky/kali-setup.conf"
X-GNOME-Autostart-enabled=true
DESK
    pkill -f 'conky.*kali-setup.conf' 2>/dev/null
    [[ -n "${DISPLAY:-}" ]] && conky -d -c "$HOME/.config/conky/kali-setup.conf" >/dev/null 2>&1
    # Обои: градиент в цветах палитры
    local pics wall im p
    pics="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    wall="$pics/wallpapers/kali-setup-${pal}.png"
    im="$(command -v magick || command -v convert)"
    if [[ -n "$im" && ! -f "$wall" ]]; then
        mkdir -p "$(dirname "$wall")"
        # два мягких свечения цвета акцента (screen с чёрным краем — без резких границ)
        "$im" -size 2560x1440 xc:"$bg" \
            \( -size 2400x2400 radial-gradient:"${acc}"-black -evaluate multiply 0.5 \) \
            -gravity southeast -geometry -900-1000 -compose screen -composite \
            \( -size 1600x1600 radial-gradient:"${acc}"-black -evaluate multiply 0.18 \) \
            -gravity northwest -geometry -600-700 -compose screen -composite "$wall" 2>/dev/null \
            && echo "$wall" >> "${STATE_DIR}/xextras.walls"
    fi
    if [[ -f "$wall" ]]; then
        for p in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$'); do
            xfconf_set xfce4-desktop "$p" string "$wall"
        done
    fi
    ok "Rofi — SUPER+D, Conky на рабочем столе, заметки — SUPER+N (~/notes.txt), обои: $wall"
}

