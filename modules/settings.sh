#!/usr/bin/env bash
# modules/settings.sh — настройка системы (время, клавиатура, блокировка экрана).

# Выбор часового пояса: регион -> город (whiptail). Результат — в stdout.
# Без меню берётся переменная TZ_ZONE, например: TZ_ZONE=Europe/Moscow ./setup.sh time
pick_timezone() {
    if [[ -n "${TZ_ZONE:-}" ]]; then echo "$TZ_ZONE"; return 0; fi
    have whiptail && [[ -t 0 ]] || return 1
    local all regions=() r args=() z zones=() region city
    all="$(timedatectl list-timezones 2>/dev/null)" || return 1
    # только основные регионы, без устаревших псевдонимов (GB, US, Zulu…)
    while read -r r; do regions+=("$r"); done < <(cut -d/ -f1 <<<"$all" | sort -u \
        | grep -xE 'Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific|UTC')
    for r in "${regions[@]}"; do args+=("$r" ""); done
    region=$(whiptail --title "Часовой пояс" --menu "Выбери регион:" \
        22 78 14 "${args[@]}" 3>&1 1>&2 2>&3) || return 1
    while read -r z; do zones+=("$z"); done < <(grep -E "^${region}(/|$)" <<<"$all")
    [[ ${#zones[@]} -eq 1 ]] && { echo "${zones[0]}"; return 0; }
    args=()
    for z in "${zones[@]}"; do args+=("${z#"${region}"/}" "$(TZ="$z" date '+%H:%M  (UTC%:z)')"); done
    city=$(whiptail --title "Часовой пояс: ${region}" --menu "Выбери город:" \
        22 78 14 "${args[@]}" 3>&1 1>&2 2>&3) || return 1
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
