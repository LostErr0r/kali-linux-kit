#!/usr/bin/env bash
#
# setup.sh — настройка рабочей Kali Linux (в т.ч. на флэшке).
#
# Модули:
#   lib/common.sh        — переменные и помощники
#   lib/ui.sh            — меню мастера (gum, запасной вариант — whiptail)
#   modules/system.sh    — обновление системы, базовые пакеты
#   modules/apps.sh      — приложения
#   modules/ai.sh        — AI: Claude Desktop, DeepSeek Harness, Graphify, HexStrike AI
#   modules/settings.sh  — настройка системы (время, клавиатура, блокировка экрана)
#   modules/custom.sh    — кастомизация: GNOME, Hyprland, XFCE (подпункты)
#   modules/uninstall.sh — откат (удалить/вернуть назад)
#   skills/graphify/     — исходники и скил Graphify (копия в репозитории)
#
# Запуск:
#   ./setup.sh                      — интерактивный мастер (меню)
#   ./setup.sh claude amnezia       — поставить только эти шаги, без меню
#   ./setup.sh undo amnezia prompt  — откатить только эти шаги
#
# ВАЖНО: запускай от ОБЫЧНОГО пользователя (kali), НЕ от root.
#
set -uo pipefail

# ----------------------------------------------------------------------------
# Подключение модулей
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ui.sh"
for _m in system apps ai settings custom uninstall; do
    source "${SCRIPT_DIR}/modules/${_m}.sh"
done
unset _m

# ----------------------------------------------------------------------------
# Данные для меню
# ----------------------------------------------------------------------------
# Меню: *_DESC — короткое название (оно же в сводке), *_HINT — пояснение серым рядом
CATEGORIES=(update apps ai settings custom revert)
declare -A CAT_DESC=(
    [update]="Обновление системы"
    [apps]="Приложения"
    [ai]="AI-инструменты"
    [settings]="Настройка системы"
    [custom]="Кастомизация"
    [revert]="Откат"
    [exit]="✕ Выйти"
)
declare -A CAT_HINT=(
    [update]="полный апгрейд: apt full-upgrade + чистка"
    [apps]="Discord, Telegram, KeePassXC, Tor, VPN, Docker"
    [ai]="Claude Desktop, DeepSeek, Graphify, HexStrike"
    [settings]="часовой пояс, раскладка RU, блокировка экрана"
    [custom]="внешний вид: GNOME, Hyprland или XFCE"
    [revert]="удалить поставленное, вернуть настройки"
    [exit]="закрыть скрипт, ничего не меняя"
)
# Первый экран мастера: этапы + выход
MAIN_MENU=("${CATEGORIES[@]}" exit)

# base ставится автоматически как зависимость перед приложениями
APP_STEPS=(discord telegram keepassxc torbrowser obsidian happ amnezia docker)
declare -A APP_DESC=(
    [discord]="Discord"
    [telegram]="Telegram"
    [keepassxc]="KeePassXC"
    [torbrowser]="Tor Browser"
    [obsidian]="Obsidian"
    [happ]="Happ"
    [amnezia]="AmneziaVPN"
    [docker]="Docker"
)
declare -A APP_HINT=(
    [discord]="голосовой чат и сообщества"
    [telegram]="мессенджер"
    [keepassxc]="менеджер паролей, база хранится у тебя"
    [torbrowser]="анонимный браузер через сеть Tor"
    [obsidian]="заметки в Markdown, база знаний"
    [happ]="прокси-клиент"
    [amnezia]="VPN-клиент с маскировкой трафика"
    [docker]="контейнеры + docker-compose"
)

# AI: модели и инструменты (отдельная категория меню)
AI_STEPS=(claude deepseek graphify hexstrike)
declare -A AI_DESC=(
    [claude]="Claude Desktop"
    [deepseek]="DeepSeek Harness"
    [graphify]="Graphify"
    [hexstrike]="HexStrike AI"
)
declare -A AI_HINT=(
    [claude]="приложение Claude от Anthropic"
    [deepseek]="консольный агент DeepSeek, команда dsh"
    [graphify]="граф кодовой базы, скил /graphify"
    [hexstrike]="MCP-сервер с инструментами пентеста для AI"
)

SETTINGS_STEPS=(time keyboard nolock)
declare -A SETTINGS_DESC=(
    [time]="Часовой пояс"
    [keyboard]="Раскладка"
    [nolock]="Блокировка экрана"
)
declare -A SETTINGS_HINT=(
    [time]="город, синхронизация NTP, секунды в часах"
    [keyboard]="вторая раскладка RU, переключение Win+Space"
    [nolock]="экран не гаснет и не блокируется сам"
)

# Кастомизация: сначала выбирается окружение (группа), затем его подпункты
CUSTOM_GROUPS=(gnome hyprland xfce)
declare -A CUSTOM_GROUP_DESC=(
    [gnome]="GNOME"
    [hyprland]="Hyprland"
    [xfce]="XFCE"
)
declare -A CUSTOM_GROUP_HINT=(
    [gnome]="GNOME рядом с XFCE + расширения"
    [hyprland]="тайлинговый менеджер окон в стиле JaKooLit"
    [xfce]="украсить текущий рабочий стол"
)
GNOME_STEPS=(gnome gnomeext)
HYPR_STEPS=(hyprland)
XFCE_STEPS=(xtheme xpanel xpicom xextras)
declare -A CUSTOM_DESC=(
    [gnome]="Окружение GNOME"
    [gnomeext]="Расширения GNOME"
    [hyprland]="Hyprland"
    [xtheme]="Тема оформления"
    [xpanel]="Верхняя панель"
    [xpicom]="Эффекты окон"
    [xextras]="Меню, виджет, обои"
)
declare -A CUSTOM_HINT=(
    [gnome]="рядом с XFCE, сессия выбирается при входе"
    [gnomeext]="док, трей, размытие, темы, мониторинг"
    [hyprland]="тайлинг, Waybar, Rofi, конфиги JaKooLit"
    [xtheme]="палитра на выбор, иконки, курсор, шрифты"
    [xpanel]="36 px, полупрозрачная, часы по центру"
    [xpicom]="Picom: скругления, тени, размытие, анимации"
    [xextras]="Rofi на SUPER+D, Conky с заметками, обои"
)
CUSTOM_STEPS=("${GNOME_STEPS[@]}" "${HYPR_STEPS[@]}" "${XFCE_STEPS[@]}")

# Что можно откатить (приложения + настройка системы; обновление системы откату не подлежит)
REVERT_STEPS=(claude discord telegram keepassxc torbrowser obsidian happ amnezia docker deepseek graphify hexstrike time keyboard nolock gnome gnomeext hyprland xtheme xpanel xpicom xextras)
declare -A REVERT_DESC=(
    [claude]="Удалить Claude Desktop"
    [discord]="Удалить Discord"
    [telegram]="Удалить Telegram"
    [keepassxc]="Удалить KeePassXC"
    [torbrowser]="Удалить Tor Browser"
    [obsidian]="Удалить Obsidian"
    [happ]="Удалить Happ"
    [amnezia]="Удалить AmneziaVPN"
    [hexstrike]="Удалить HexStrike AI"
    [docker]="Удалить Docker"
    [deepseek]="Удалить DeepSeek Harness (dsh)"
    [graphify]="Удалить Graphify (CLI)"
    [time]="Вернуть часовой пояс, синхронизацию и формат часов"
    [keyboard]="Вернуть прежние раскладки клавиатуры"
    [nolock]="Вернуть блокировку экрана по времени"
    [gnome]="Удалить GNOME (если ставил скрипт)"
    [gnomeext]="Удалить расширения GNOME, вернуть список включённых"
    [hyprland]="Удалить Hyprland, вернуть прежние конфиги ~/.config"
    [xtheme]="XFCE: вернуть прежнюю тему, иконки, курсор, шрифты"
    [xpanel]="XFCE: вернуть прежнюю панель"
    [xpicom]="XFCE: убрать Picom, вернуть встроенный композитор"
    [xextras]="XFCE: убрать Rofi-хоткей, Conky, вернуть обои"
)

# ----------------------------------------------------------------------------
# Диспетчер установки одного шага по ключу
# ----------------------------------------------------------------------------
run_step() {
    case "$1" in
        system)    do_system ;;
        base)      do_base ;;
        claude)    do_claude ;;
        discord)   do_discord ;;
        telegram)  do_telegram ;;
        keepassxc) do_keepassxc ;;
        torbrowser) do_torbrowser ;;
        obsidian)  do_obsidian ;;
        happ)      do_happ ;;
        amnezia)   do_amnezia ;;
        hexstrike) do_hexstrike ;;
        docker)    do_docker ;;
        deepseek)  do_deepseek ;;
        graphify)  do_graphify ;;
        time)      do_set_time ;;
        keyboard)  do_set_keyboard ;;
        nolock)    do_set_nolock ;;
        gnome)     do_custom_gnome ;;
        gnomeext)  do_custom_gnomeext ;;
        hyprland)  do_custom_hyprland ;;
        xtheme)    do_custom_xtheme ;;
        xpanel)    do_custom_xpanel ;;
        xpicom)    do_custom_xpicom ;;
        xextras)   do_custom_xextras ;;
        *) err "Неизвестный шаг: $1"; return 1 ;;
    esac
}

# ----------------------------------------------------------------------------
# Интерактивный мастер (меню — lib/ui.sh)
# ----------------------------------------------------------------------------
# Порядок выполнения выбранных категорий (результат -> CAT_ORDER)
order_categories() {
    CAT_ORDER=()
    local remaining=("${CAT_CHOSEN[@]}")
    if [[ ${#remaining[@]} -le 1 ]]; then CAT_ORDER=("${remaining[@]}"); return; fi
    while [[ ${#remaining[@]} -gt 1 ]]; do
        local k pick new=()
        pick=$(ui_radiolist "Порядок выполнения" "Что выполнить следующим? (осталось: ${#remaining[@]})" \
            remaining CAT_DESC) || { CAT_ORDER=("${CAT_CHOSEN[@]}"); return; }
        [[ -z "$pick" ]] && pick="${remaining[0]}"
        CAT_ORDER+=("$pick")
        for k in "${remaining[@]}"; do [[ "$k" != "$pick" ]] && new+=("$k"); done
        remaining=("${new[@]}")
    done
    CAT_ORDER+=("${remaining[0]}")
}

# Экран подтверждения со сводкой. Возврат 0 = согласие.
confirm_summary() {
    local msg="Будет выполнено в таком порядке:\n\n" n=1 c a
    for c in "${CAT_ORDER[@]}"; do
        msg+="$n) ${CAT_DESC[$c]}\n"; ((n++))
        case "$c" in
            apps)
                if [[ ${#APP_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${APP_CHOSEN[@]}"; do msg+="      - ${APP_DESC[$a]}\n"; done
                else msg+="      (приложения не выбраны)\n"; fi ;;
            ai)
                if [[ ${#AI_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${AI_CHOSEN[@]}"; do msg+="      - ${AI_DESC[$a]}\n"; done
                else msg+="      (AI не выбран)\n"; fi ;;
            settings)
                if [[ ${#SETTINGS_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${SETTINGS_CHOSEN[@]}"; do msg+="      - ${SETTINGS_DESC[$a]}\n"; done
                else msg+="      (пункты настройки не выбраны)\n"; fi ;;
            custom)
                if [[ ${#CUSTOM_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${CUSTOM_CHOSEN[@]}"; do msg+="      - ${CUSTOM_DESC[$a]}\n"; done
                else msg+="      (пункты кастомизации не выбраны)\n"; fi ;;
            revert)
                if [[ ${#REVERT_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${REVERT_CHOSEN[@]}"; do msg+="      - ${REVERT_DESC[$a]}\n"; done
                else msg+="      (пункты отката не выбраны)\n"; fi ;;
        esac
    done
    ui_confirm "Подтверждение" "$msg"
}

# Кастомизация: выбор окружений, затем подпунктов каждого (результат -> CUSTOM_CHOSEN).
# Пустой выбор на любом экране или отмена — код 1 (мастер вернётся в начало).
pick_custom() {
    local groups=() g sub=()
    CUSTOM_CHOSEN=()
    ui_checklist "Кастомизация" "Какое окружение кастомизировать?" \
        CUSTOM_GROUPS CUSTOM_GROUP_DESC groups && [[ ${#groups[@]} -gt 0 ]] || return 1
    for g in "${groups[@]}"; do
        sub=()
        case "$g" in
            gnome)    ui_checklist "Кастомизация: GNOME" "Что поставить?" GNOME_STEPS CUSTOM_DESC sub || return 1 ;;
            hyprland) sub=("${HYPR_STEPS[@]}") ;;   # один пункт — выбран вместе с группой
            xfce)     ui_checklist "Кастомизация: XFCE" "Что настроить? (палитру спрошу при установке)" \
                          XFCE_STEPS CUSTOM_DESC sub || return 1 ;;
        esac
        [[ ${#sub[@]} -gt 0 ]] || return 1
        CUSTOM_CHOSEN+=("${sub[@]}")
    done
}

# Короткое сообщение перед возвратом на первый экран
back_to_start() {
    warn "Ничего не выбрано или отменено — возвращаюсь в начало."
    sleep 1.2
}

CAT_CHOSEN=(); CAT_ORDER=(); APP_CHOSEN=(); AI_CHOSEN=(); SETTINGS_CHOSEN=(); CUSTOM_CHOSEN=(); REVERT_CHOSEN=()
run_wizard() {
    if ! ui_gum && ! have whiptail; then
        warn "Нет ни gum, ни whiptail — ставлю всё по умолчанию (без меню)."
        do_system; do_base
        local a; for a in "${APP_STEPS[@]}" "${AI_STEPS[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done
        return
    fi
    ui_banner
    # 1–4) выбор. Пустой список, Esc или «Отмена» — назад, на первый экран
    local c good
    while true; do
        APP_CHOSEN=(); AI_CHOSEN=(); SETTINGS_CHOSEN=(); CUSTOM_CHOSEN=(); REVERT_CHOSEN=()
        ui_checklist "Что будем делать?" "Отметь нужные этапы" MAIN_MENU CAT_DESC CAT_CHOSEN \
            || { warn "Выход."; exit 0; }
        [[ " ${CAT_CHOSEN[*]} " == *" exit "* ]] && { ok "Выход."; exit 0; }
        [[ ${#CAT_CHOSEN[@]} -eq 0 ]] && { back_to_start; continue; }
        order_categories
        good=1
        for c in "${CAT_ORDER[@]}"; do
            case "$c" in
                apps)     ui_checklist "Установка приложений" "Какие приложения поставить?" \
                              APP_STEPS APP_DESC APP_CHOSEN && [[ ${#APP_CHOSEN[@]} -gt 0 ]] || good=0 ;;
                ai)       ui_checklist "AI: модели и инструменты" "Что поставить?" \
                              AI_STEPS AI_DESC AI_CHOSEN && [[ ${#AI_CHOSEN[@]} -gt 0 ]] || good=0 ;;
                settings) ui_checklist "Настройка системы" "Что настроить?" \
                              SETTINGS_STEPS SETTINGS_DESC SETTINGS_CHOSEN && [[ ${#SETTINGS_CHOSEN[@]} -gt 0 ]] || good=0 ;;
                custom)   pick_custom || good=0 ;;
                revert)   ui_checklist "Откат" "Что откатить/удалить?" \
                              REVERT_STEPS REVERT_DESC REVERT_CHOSEN && [[ ${#REVERT_CHOSEN[@]} -gt 0 ]] || good=0 ;;
            esac
            [[ $good -eq 1 ]] || break
        done
        [[ $good -eq 1 ]] || { back_to_start; continue; }
        confirm_summary && break
        back_to_start
    done
    # 5) выполнение
    log "План: ${CAT_ORDER[*]}"
    local a
    for c in "${CAT_ORDER[@]}"; do
        case "$c" in
            update) do_system ;;
            apps)   do_base   # базовые инструменты — зависимость приложений
                    for a in "${APP_CHOSEN[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done ;;
            ai)     do_base   # python3/pipx/curl нужны для AI-инструментов
                    for a in "${AI_CHOSEN[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done ;;
            settings) for a in "${SETTINGS_CHOSEN[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done ;;
            custom) for a in "${CUSTOM_CHOSEN[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done ;;
            revert) for a in "${REVERT_CHOSEN[@]}"; do run_undo "$a" || warn "Откат '$a' с ошибкой."; done ;;
        esac
    done
}

main() {
    setup_prepare
    if [[ $# -gt 0 && ( "$1" == "undo" || "$1" == "revert" || "$1" == "--undo" ) ]]; then
        # Явный откат: ./setup.sh undo amnezia prompt ...
        shift
        [[ $# -eq 0 ]] && { warn "Укажи, что откатывать: ${REVERT_STEPS[*]}"; exit 0; }
        local s; for s in "$@"; do run_undo "$s" || warn "Откат '$s' с ошибкой — продолжаю."; done
    elif [[ $# -gt 0 ]]; then
        # Явная установка: ./setup.sh claude amnezia ...
        local s; for s in "$@"; do run_step "$s" || warn "Шаг '$s' с ошибкой — продолжаю."; done
    elif [[ -t 0 ]]; then
        ui_init
        run_wizard
    else
        # Неинтерактивно — всё по умолчанию
        do_system; do_base
        local a; for a in "${APP_STEPS[@]}" "${AI_STEPS[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done
    fi
    step "Готово"
    ok "Все выбранные шаги выполнены. Полный лог: $LOG_FILE"
}

main "$@"
