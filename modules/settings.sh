#!/usr/bin/env bash
# modules/settings.sh — настройка системы (время, клавиатура, блокировка экрана).

# Выбор часового пояса: регион -> город (меню с поиском, lib/ui.sh). Результат — в stdout.
# Без меню берётся переменная TZ_ZONE, например: TZ_ZONE=Europe/Moscow ./setup.sh time
pick_timezone() {
    if [[ -n "${TZ_ZONE:-}" ]]; then echo "$TZ_ZONE"; return 0; fi
    [[ -t 0 ]] && { ui_gum || have whiptail; } || return 1
    local all regions=() r args=() z zones=() region city
    all="$(timedatectl list-timezones 2>/dev/null)" || return 1
    # только основные регионы, без устаревших псевдонимов (GB, US, Zulu…)
    while read -r r; do regions+=("$r"); done < <(cut -d/ -f1 <<<"$all" | sort -u \
        | grep -xE 'Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific|UTC')
    for r in "${regions[@]}"; do args+=("$r" ""); done
    region=$(ui_menu "Часовой пояс" "Выбери регион" "${args[@]}") || return 1
    while read -r z; do zones+=("$z"); done < <(grep -E "^${region}(/|$)" <<<"$all")
    [[ ${#zones[@]} -eq 1 ]] && { echo "${zones[0]}"; return 0; }
    args=()
    for z in "${zones[@]}"; do args+=("${z#"${region}"/}" "$(TZ="$z" date '+%H:%M  (UTC%:z)')"); done
    city=$(ui_menu "Часовой пояс: ${region}" "Выбери город" "${args[@]}") || return 1
    echo "${region}/${city}"
}

do_set_time() {
    step "Настройка: часовой пояс, синхронизация, секунды в часах"
    local tz p
    state_set_once time.tz  "$(timedatectl show -p Timezone --value 2>/dev/null)"
    state_set_once time.ntp "$(timedatectl show -p NTP --value 2>/dev/null)"
    # 1) Часовой пояс
    if tz="$(pick_timezone)" && [[ -n "$tz" ]]; then
        sudo timedatectl set-timezone "$tz" && ok "Часовой пояс: $tz"
    else
        warn "Часовой пояс не выбран — оставляю как есть ($(timedatectl show -p Timezone --value 2>/dev/null))."
    fi
    # 2) Синхронизация по NTP
    pkg_installed systemd-timesyncd || sudo apt install -y systemd-timesyncd 2>/dev/null || true
    if sudo timedatectl set-ntp true; then
        ok "Синхронизация времени (NTP) включена"
    else
        warn "Не удалось включить синхронизацию времени"
    fi
    # 3) Секунды в часах на панели XFCE
    if ! have_xfce; then
        warn "Не XFCE — секунды в часах не настраиваю."
        return 0
    fi
    for p in $(xfce_clock_plugins); do
        xfconf_set xfce4-panel "${p}/digital-time-format" string "%_H:%M:%S"
        # старые версии плагина хранят формат в digital-format
        xfconf-query -c xfce4-panel -p "${p}/digital-format" >/dev/null 2>&1 \
            && xfconf_set xfce4-panel "${p}/digital-format" string "%_H:%M:%S"
    done
    if [[ -n "$(xfce_clock_plugins)" ]]; then
        ok "Часы на панели показывают секунды"
    else
        warn "На панели нет часов — секунды некуда добавить."
    fi
}

do_set_keyboard() {
    step "Настройка: вторая раскладка Russian, переключение Win+Space"
    if ! have_xfce; then
        warn "Не XFCE — раскладку не настраиваю."
        return 0
    fi
    # Первая раскладка — та, что уже стоит (обычно us)
    local first
    first="$(xfconf-query -c keyboard-layout -p /Default/XkbLayout 2>/dev/null | cut -d, -f1)"
    [[ -z "$first" || "$first" == ru ]] && first=us
    xfconf_set keyboard-layout /Default/XkbDisable       bool   false
    xfconf_set keyboard-layout /Default/XkbLayout        string "${first},ru"
    xfconf_set keyboard-layout /Default/XkbVariant       string ","
    xfconf_set keyboard-layout /Default/XkbOptions/Group string "grp:win_space_toggle"
    ok "Раскладки: ${first} + ru, переключение — Win+Space"
}

do_set_nolock() {
    step "Настройка: не блокировать и не гасить экран по таймеру"
    if ! have_xfce; then
        warn "Не XFCE — блокировку не настраиваю."
        return 0
    fi
    # Заставка/блокировка не включается сама после простоя (ручная блокировка остаётся)
    xfconf_set xfce4-screensaver /saver/idle-activation/enabled bool false
    xfconf_set xfce4-screensaver /lock/saver-activation/enabled bool false
    # Экран не гаснет и не уходит в DPMS
    xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-enabled     bool false
    xfconf_set xfce4-power-manager /xfce4-power-manager/blank-on-ac      int  0
    xfconf_set xfce4-power-manager /xfce4-power-manager/blank-on-battery int  0
    have xset && [[ -n "${DISPLAY:-}" ]] && xset s off -dpms 2>/dev/null || true
    ok "Блокировка и гашение экрана по времени: никогда"
}

# Для ноутбука: ускорение 5.9, все галочки General, клик 1/2/3 пальцами, прокрутка двумя пальцами
do_set_touchpad() {
    step "Настройка: тачпад ноутбука"
    if ! have_xfce; then
        warn "Не XFCE — тачпад не настраиваю."
        return 0
    fi
    local pads d
    pads="$(xfce_touchpads)"
    if [[ -z "$pads" && -n "$(virt_type)" ]]; then
        warn "Виртуальная машина ($(virt_type)) — тачпад настраивается на хосте, пропускаю."
        return 0
    elif [[ -z "$pads" ]]; then
        warn "Тачпад не найден (не ноутбук?) — пропускаю."
        return 0
    fi
    for d in $pads; do
        xfconf_set pointers "/${d}/Acceleration" double 5.9
        # General: отключать во время набора текста, тап = клик
        xfconf_set pointers "/${d}/Properties/libinput_Disable_While_Typing_Enabled" int 1
        xfconf_set pointers "/${d}/Properties/libinput_Tapping_Enabled" int 1
        # Click method: 1/2/3 пальца (clickfinger), а не зоны кнопок
        xfconf_set_array pointers "/${d}/Properties/libinput_Click_Method_Enabled" int 0 1
        # Scroll method: two-finger
        xfconf_set_array pointers "/${d}/Properties/libinput_Scroll_Method_Enabled" int 1 0 0
        ok "Тачпад ${d}: ускорение 5.9, тап, клик пальцами, прокрутка двумя пальцами"
    done
    state_set_once touchpad.devices "$pads"
}
