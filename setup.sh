#!/usr/bin/env bash
#
# setup.sh — настройка рабочей Kali Linux (в т.ч. на флэшке).
#
# Модули:
#   lib/common.sh        — переменные и помощники
#   modules/system.sh    — обновление системы, базовые пакеты
#   modules/apps.sh      — приложения
#   modules/ai.sh        — AI: Claude Desktop, DeepSeek Harness, Graphify, HexStrike AI
#   modules/settings.sh  — настройка системы (время, клавиатура, блокировка экрана)
#   modules/custom.sh    — кастомизация (пока пусто)
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
for _m in system apps ai settings custom uninstall; do
    source "${SCRIPT_DIR}/modules/${_m}.sh"
done
unset _m

# ----------------------------------------------------------------------------
# Данные для меню
# ----------------------------------------------------------------------------
CATEGORIES=(update apps ai settings custom revert)
declare -A CAT_DESC=(
    [update]="Обновление системы"
    [apps]="Установка приложений"
    [ai]="AI: модели и инструменты"
    [settings]="Настройка системы"
    [custom]="Кастомизация (пока пусто)"
    [revert]="Откат (удалить / вернуть назад)"
)

# base ставится автоматически как зависимость перед приложениями
APP_STEPS=(discord telegram keepassxc torbrowser obsidian happ amnezia docker)
declare -A APP_DESC=(
    [discord]="Discord"
    [telegram]="Telegram"
    [keepassxc]="KeePassXC (менеджер паролей)"
    [torbrowser]="Tor Browser"
    [obsidian]="Obsidian"
    [happ]="Happ (прокси-клиент)"
    [amnezia]="AmneziaVPN"
    [docker]="Docker (контейнеры + compose)"
)

# AI: модели и инструменты (отдельная категория меню)
AI_STEPS=(claude deepseek graphify hexstrike)
declare -A AI_DESC=(
    [claude]="Claude Desktop"
    [deepseek]="DeepSeek Harness (dsh)"
    [graphify]="Graphify (граф кодовой базы, скил /graphify)"
    [hexstrike]="HexStrike AI (MCP-сервер)"
)

SETTINGS_STEPS=(time keyboard nolock)
declare -A SETTINGS_DESC=(
    [time]="Часовой пояс (выбор из списка), синхронизация, секунды в часах"
    [keyboard]="Вторая раскладка Russian, переключение Win+Space"
    [nolock]="Не блокировать экран по времени (никогда)"
)

# Кастомизация — пока пусто, пункты добавим позже
CUSTOM_STEPS=()
declare -A CUSTOM_DESC=()

# Пункты, которые в меню по умолчанию НЕ отмечены (тяжёлые/меняющие окружение)
DEFAULT_OFF=()

# Что можно откатить (приложения + настройка системы; обновление системы откату не подлежит)
REVERT_STEPS=(claude discord telegram keepassxc torbrowser obsidian happ amnezia docker deepseek graphify hexstrike time keyboard nolock)
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
        *) err "Неизвестный шаг: $1"; return 1 ;;
    esac
}

# ----------------------------------------------------------------------------
# Интерактивный мастер (whiptail)
# ----------------------------------------------------------------------------
# Чек-лист: <title> <prompt> <массив-ключей> <assoc-описаний> <массив-результата> [ON|OFF]
# Результат — в выходном массиве в КАНОНИЧНОМ порядке ключей.
wt_checklist() {
    local title="$1" prompt="$2"
    local -n _steps="$3"; local -n _desc="$4"; local -n _out="$5"
    local default="${6:-ON}"
    local args=() k t sel chosen=() on
    for k in "${_steps[@]}"; do
        on="$default"
        [[ " ${DEFAULT_OFF[*]} " == *" $k "* ]] && on=OFF
        args+=("$k" "${_desc[$k]}" "$on")
    done
    sel=$(whiptail --title "$title" --checklist "$prompt" \
        20 78 "${#_steps[@]}" "${args[@]}" 3>&1 1>&2 2>&3) || { _out=(); return 1; }
    eval "chosen=($sel)"
    _out=()
    for k in "${_steps[@]}"; do
        for t in "${chosen[@]}"; do [[ "$t" == "$k" ]] && { _out+=("$k"); break; }; done
    done
    return 0
}

# Порядок выполнения выбранных категорий (результат -> CAT_ORDER)
order_categories() {
    CAT_ORDER=()
    local remaining=("${CAT_CHOSEN[@]}")
    if [[ ${#remaining[@]} -le 1 ]]; then CAT_ORDER=("${remaining[@]}"); return; fi
    while [[ ${#remaining[@]} -gt 1 ]]; do
        local args=() k first=1 pick new=()
        for k in "${remaining[@]}"; do
            if [[ $first -eq 1 ]]; then args+=("$k" "${CAT_DESC[$k]}" "ON"); first=0
            else args+=("$k" "${CAT_DESC[$k]}" "OFF"); fi
        done
        pick=$(whiptail --title "Порядок выполнения" \
            --radiolist "Что выполнить следующим? (осталось пунктов: ${#remaining[@]})" \
            16 78 "${#remaining[@]}" "${args[@]}" 3>&1 1>&2 2>&3) || { CAT_ORDER=("${CAT_CHOSEN[@]}"); return; }
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
                else msg+="      (пока пусто)\n"; fi ;;
            revert)
                if [[ ${#REVERT_CHOSEN[@]} -gt 0 ]]; then
                    for a in "${REVERT_CHOSEN[@]}"; do msg+="      - ${REVERT_DESC[$a]}\n"; done
                else msg+="      (пункты отката не выбраны)\n"; fi ;;
        esac
    done
    msg+="\nНачать выполнение?"
    whiptail --title "Подтверждение" --yesno "$msg" 24 78
}

CAT_CHOSEN=(); CAT_ORDER=(); APP_CHOSEN=(); AI_CHOSEN=(); SETTINGS_CHOSEN=(); CUSTOM_CHOSEN=(); REVERT_CHOSEN=()
run_wizard() {
    if ! have whiptail; then
        warn "whiptail не найден — ставлю всё по умолчанию (без меню)."
        do_system; do_base
        local a; for a in "${APP_STEPS[@]}" "${AI_STEPS[@]}"; do run_step "$a" || warn "Шаг '$a' с ошибкой."; done
        return
    fi
    # 1) категории
    wt_checklist "Что будем делать?" "Выбери этапы (Пробел — вкл/выкл, Enter — ок):" \
        CATEGORIES CAT_DESC CAT_CHOSEN || { warn "Отменено."; exit 0; }
    [[ ${#CAT_CHOSEN[@]} -eq 0 ]] && { warn "Ничего не выбрано — выходим."; exit 0; }
    # 2) порядок
    order_categories
    # 3) под-списки
    local c
    for c in "${CAT_ORDER[@]}"; do
        case "$c" in
            apps)   wt_checklist "Установка приложений" "Какие приложения поставить?" \
                        APP_STEPS APP_DESC APP_CHOSEN ;;
            ai)     wt_checklist "AI: модели и инструменты" "Что поставить?" \
                        AI_STEPS AI_DESC AI_CHOSEN ;;
            settings) wt_checklist "Настройка системы" "Что настроить?" \
                        SETTINGS_STEPS SETTINGS_DESC SETTINGS_CHOSEN ;;
            custom)
                if [[ ${#CUSTOM_STEPS[@]} -eq 0 ]]; then
                    whiptail --title "Кастомизация" --msgbox "Пока пусто — пункты добавим позже." 8 60
                else
                    wt_checklist "Кастомизация" "Что настроить?" \
                        CUSTOM_STEPS CUSTOM_DESC CUSTOM_CHOSEN
                fi ;;
            revert) wt_checklist "Откат" "Что откатить/удалить? (по умолчанию ничего не отмечено)" \
                        REVERT_STEPS REVERT_DESC REVERT_CHOSEN OFF ;;
        esac
    done
    # 4) подтверждение
    confirm_summary || { warn "Отменено на экране подтверждения."; exit 0; }
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
