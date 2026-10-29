#!/usr/bin/env bash
# lib/ui.sh — меню мастера: gum (красиво), а если его нет — whiptail.
# Подключается из setup.sh после lib/common.sh.

UI_ACCENT="#367BF0"   # синий Kali
UI_DIM="#7F8C98"
UI_OK="#4CC38A"

# gum доступен и мы в терминале
ui_gum() { have gum && [[ -t 0 && -t 2 ]]; }

# Поставить gum для мастера (маленький пакет из репозитория Kali). Не вышло — останется whiptail.
ui_init() {
    [[ -t 0 ]] || return 0
    have gum && return 0
    log "Ставлю gum для красивого меню..."
    sudo apt install -y gum >/dev/null 2>&1 || warn "gum не поставился — меню будет в whiptail."
}

ui_banner() {
    ui_gum || return 0
    clear
    gum style --border rounded --border-foreground "$UI_ACCENT" --padding "1 4" --margin "1 2" \
        "$(gum style --bold --foreground "$UI_ACCENT" '◆  K A L I   S E T U P')" \
        "$(gum style --foreground "$UI_DIM" 'быстрая настройка свежей Kali')"
}

# Заголовок экрана: чистый экран, шапка, крупная строка + подсказка
_ui_header() {
    clear >&2
    gum style --margin "1 2 0 2" --foreground "$UI_DIM" \
        "$(gum style --bold --foreground "$UI_ACCENT" '◆ KALI SETUP')  ·  быстрая настройка свежей Kali" >&2
    gum style --margin "1 2 0 2" --bold --foreground "$UI_ACCENT" "$1" >&2
    [[ -n "${2:-}" ]] && gum style --margin "0 2" --foreground "$UI_DIM" "$2" >&2
    echo >&2
}

# gum делит --selected по запятым — в подписях меняем запятую на похожий символ
_ui_label() { printf '%s' "${1//,/‚}"; }

# Подписи пунктов: «название   пояснение» — пояснения (массив <имя>_HINT рядом с <имя>_DESC)
# выровнены в колонку и выведены серым. Заполняет массивы _UI_SHOW (что показать) и
# _UI_PLAIN (то же без цвета — так gum возвращает выбор).
#   _ui_items <массив-ключей> <assoc-описаний>
_ui_items() {
    local -n __k="$1"; local -n __d="$2"
    local hint_name="${2%_DESC}_HINT" k name hint w=0 pad
    _UI_SHOW=(); _UI_PLAIN=()
    declare -p "$hint_name" >/dev/null 2>&1 || hint_name=""
    for k in "${__k[@]}"; do (( ${#__d[$k]} > w )) && w=${#__d[$k]}; done
    for k in "${__k[@]}"; do
        name="$(_ui_label "${__d[$k]}")"; hint=""
        if [[ -n "$hint_name" ]]; then local -n __h="$hint_name"; hint="$(_ui_label "${__h[$k]:-}")"; fi
        if [[ -n "$hint" ]]; then
            printf -v pad '%*s' $(( w - ${#name} + 3 )) ''
            _UI_SHOW+=("${name}${pad}"$'\e[38;2;127;140;152m'"${hint}"$'\e[0m')
            _UI_PLAIN+=("${name}${pad}${hint}")
        else
            _UI_SHOW+=("$name"); _UI_PLAIN+=("$name")
        fi
    done
}

_ui_choose() {
    gum choose --cursor "❯ " --cursor.foreground "$UI_ACCENT" \
        --selected.foreground "$UI_ACCENT" --height 16 --padding "0 2" --no-show-help "$@"
}

# Чек-лист: <title> <prompt> <массив-ключей> <assoc-описаний> <массив-результата> [OFF|ON]
# Результат — в выходном массиве в КАНОНИЧНОМ порядке ключей. Отмена — код 1.
ui_checklist() {
    local title="$1" prompt="$2"
    local -n _steps="$3"; local -n _desc="$4"; local -n _out="$5"
    local default="${6:-OFF}"   # по умолчанию ничего не отмечено
    local k t sel chosen=()
    _out=()
    if ui_gum; then
        local i pre=()
        declare -A key_of=()
        _ui_items "$3" "$4"
        for i in "${!_steps[@]}"; do key_of[${_UI_PLAIN[i]}]="${_steps[i]}"; done
        [[ "$default" == ON ]] && pre=(--selected "$(IFS=,; echo "${_UI_SHOW[*]}")")
        _ui_header "$title" "$prompt"
        sel=$(_ui_choose --no-limit --header "Space — выбрать · Enter — дальше · Esc — отмена" \
            --header.foreground "$UI_DIM" --cursor-prefix "○ " --selected-prefix "◉ " \
            --unselected-prefix "○ " "${pre[@]}" "${_UI_SHOW[@]}") || return 1
        while IFS= read -r t; do [[ -n "$t" ]] && chosen+=("${key_of[$t]}"); done <<<"$sel"
    else
        local args=() i
        _ui_items "$3" "$4"
        for i in "${!_steps[@]}"; do args+=("${_steps[i]}" "${_UI_PLAIN[i]}" "$default"); done
        sel=$(whiptail --title "$title" --checklist "$prompt" \
            20 78 "${#_steps[@]}" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
        eval "chosen=($sel)"
    fi
    for k in "${_steps[@]}"; do
        for t in "${chosen[@]}"; do [[ "$t" == "$k" ]] && { _out+=("$k"); break; }; done
    done
    return 0
}

# Один вариант из списка: <title> <prompt> <массив-ключей> <assoc-описаний> [ключ-по-умолчанию]
# Выбранный ключ — в stdout. Отмена — код 1.
ui_radiolist() {
    local title="$1" prompt="$2"
    local -n _keys="$3"; local -n _d="$4"
    local def="${5:-${_keys[0]}}" k sel lab
    if ui_gum; then
        local i show_def=""
        declare -A key_of=()
        _ui_items "$3" "$4"
        for i in "${!_keys[@]}"; do
            key_of[${_UI_PLAIN[i]}]="${_keys[i]}"
            [[ "${_keys[i]}" == "$def" ]] && show_def="${_UI_SHOW[i]}"
        done
        _ui_header "$title" "$prompt"
        sel=$(_ui_choose --limit 1 --header "↑↓ — выбрать · Enter — дальше · Esc — отмена" \
            --header.foreground "$UI_DIM" --selected "$show_def" "${_UI_SHOW[@]}") || return 1
        echo "${key_of[$sel]:-$def}"   # пустой выбор — вариант по умолчанию
    else
        local args=()
        for k in "${_keys[@]}"; do args+=("$k" "${_d[$k]}" "$([[ "$k" == "$def" ]] && echo ON || echo OFF)"); done
        whiptail --title "$title" --radiolist "$prompt" 16 78 "${#_keys[@]}" "${args[@]}" 3>&1 1>&2 2>&3
    fi
}

# Длинный список с поиском: <title> <prompt> пары «ключ» «подпись»... Ключ — в stdout.
ui_menu() {
    local title="$1" prompt="$2"; shift 2
    local sel
    if ui_gum; then
        local lines=()
        while [[ $# -ge 2 ]]; do
            lines+=("$1${2:+   $2}"); shift 2
        done
        _ui_header "$title" "$prompt"
        sel=$(printf '%s\n' "${lines[@]}" | gum filter --height 16 --padding "0 2" --no-show-help --placeholder "начни печатать для поиска…" \
            --indicator "❯" --indicator.foreground "$UI_ACCENT" \
            --match.foreground "$UI_ACCENT" --prompt "› " --prompt.foreground "$UI_ACCENT") || return 1
        echo "${sel%%   *}"
    else
        whiptail --title "$title" --menu "$prompt" 22 78 14 "$@" 3>&1 1>&2 2>&3
    fi
}

# Сводка + «да/нет»: <title> <текст со строками \n>. 0 = да.
ui_confirm() {
    local title="$1" body="$2"
    if ui_gum; then
        echo >&2
        gum style --border rounded --border-foreground "$UI_ACCENT" --padding "1 3" --margin "0 2" \
            "$(gum style --bold --foreground "$UI_ACCENT" "$title")" "" "$(printf '%b' "$body")" >&2
        echo >&2
        gum confirm "Начать выполнение?" --affirmative "Поехали" --negative "Отмена" \
            --selected.background "$UI_ACCENT" --padding "0 2"
    else
        whiptail --title "$title" --yesno "${body}\nНачать выполнение?" 24 78
    fi
}
