#!/usr/bin/env bash
# lib/common.sh — общие переменные и функции-помощники.
# Подключается из setup.sh ПЕРВЫМ, до модулей.

# ----------------------------------------------------------------------------
# Настройки
# ----------------------------------------------------------------------------
LOG_FILE="${HOME}/kali-setup.log"
HEXSTRIKE_DIR="${HOME}/tools/hexstrike-ai"   # куда клонировать hexstrike (если ставим из git)
ZSHRC="${HOME}/.zshrc"
DOWNLOAD_DIR=""                               # создаётся в setup_prepare()

# ----------------------------------------------------------------------------
# Цвета и вывод
# ----------------------------------------------------------------------------
RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

log()  { echo "${BLUE}[*]${RESET} $*" | tee -a "$LOG_FILE"; }
ok()   { echo "${GREEN}[+]${RESET} $*" | tee -a "$LOG_FILE"; }
warn() { echo "${YELLOW}[!]${RESET} $*" | tee -a "$LOG_FILE"; }
err()  { echo "${RED}[x]${RESET} $*" | tee -a "$LOG_FILE"; }
step() { echo; echo "${BOLD}${BLUE}==== $* ====${RESET}" | tee -a "$LOG_FILE"; }

# ----------------------------------------------------------------------------
# Помощники
# ----------------------------------------------------------------------------
# Установлена ли команда
have() { command -v "$1" >/dev/null 2>&1; }

# Установлен ли deb-пакет
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

# Скачать последний релизный asset с GitHub по маске имени.
#   gh_latest_asset <owner/repo> <grep-маска> <куда-сохранить-файл>
gh_latest_asset() {
    local repo="$1" pattern="$2" out="$3"
    local url
    url=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oP '"browser_download_url":\s*"\K[^"]+' \
        | grep -iE "$pattern" | head -n1)
    if [[ -z "$url" ]]; then
        err "Не нашёл asset по маске '$pattern' в $repo"
        return 1
    fi
    log "Качаю: $url"
    curl -fL --retry 3 -o "$out" "$url"
}

# Поставить локальный .deb с автодотяжкой зависимостей
install_deb() {
    local deb="$1"
    sudo apt install -y "$deb" || sudo apt install -y -f
}

# Удалить пакеты и подчистить зависимости (для модуля отката)
apt_purge() {
    sudo apt purge -y "$@" 2>/dev/null || true
    sudo apt autoremove -y 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# Блоки в ~/.zshrc (добавить/убрать по маркеру, идемпотентно)
# ----------------------------------------------------------------------------
zshrc_add_block() {
    local marker="$1"
    local begin="# >>> kali-setup: ${marker} >>>"
    local end="# <<< kali-setup: ${marker} <<<"
    touch "$ZSHRC"
    grep -qF "$begin" "$ZSHRC" && return 0   # уже добавлено
    { printf '\n%s\n' "$begin"; cat; printf '%s\n' "$end"; } >> "$ZSHRC"
}

zshrc_remove_block() {
    local marker="$1"
    local begin="# >>> kali-setup: ${marker} >>>"
    local end="# <<< kali-setup: ${marker} <<<"
    [[ -f "$ZSHRC" ]] || return 0
    grep -qF "$begin" "$ZSHRC" || return 0
    sed -i "\|${begin}|,\|${end}|d" "$ZSHRC"
}

# ----------------------------------------------------------------------------
# Подготовка: права, sudo, лог, временная папка, очистка при выходе
# ----------------------------------------------------------------------------
setup_prepare() {
    if [[ "$(id -u)" -eq 0 ]]; then
        err "Не запускай скрипт от root. Запусти от пользователя kali — sudo будет вызван сам."
        exit 1
    fi
    if ! sudo -v; then
        err "Нужны права sudo."
        exit 1
    fi
    # держим sudo "живым", пока работает скрипт
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    DOWNLOAD_DIR="$(mktemp -d /tmp/kali-setup.XXXXXX)"
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; rm -rf "$DOWNLOAD_DIR"' EXIT
    : > "$LOG_FILE"
    log "Лог пишется в $LOG_FILE"
    log "Временные файлы: $DOWNLOAD_DIR"
}

# ----------------------------------------------------------------------------
# Состояние для отката: что было ДО нас (записывается один раз, при первом запуске шага)
# ----------------------------------------------------------------------------
STATE_DIR="${HOME}/.local/state/kali-setup"

state_get() { cat "${STATE_DIR}/$1" 2>/dev/null; }
state_has() { [[ -e "${STATE_DIR}/$1" ]]; }
state_del() { local k; for k in "$@"; do rm -f "${STATE_DIR}/${k}"; done; }

# Записать значение, только если его ещё нет (повторный запуск не затирает исходное)
state_set_once() {
    state_has "$1" && return 0
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$2" > "${STATE_DIR}/$1"
}

# Сохранить исходный файл один раз. Если файла не было — запоминаем и это.
state_backup_file() {
    local path="$1" key="$2"
    state_has "${key}.bak" || state_has "${key}.absent" && return 0
    mkdir -p "$STATE_DIR"
    if [[ -f "$path" ]]; then cp -f "$path" "${STATE_DIR}/${key}.bak"
    else : > "${STATE_DIR}/${key}.absent"; fi
}

# Вернуть файл как было (или удалить, если его не было)
state_restore_file() {
    local path="$1" key="$2"
    if state_has "${key}.bak"; then
        mkdir -p "$(dirname "$path")"
        cp -f "${STATE_DIR}/${key}.bak" "$path"
    elif state_has "${key}.absent"; then
        rm -f "$path"
    fi
    state_del "${key}.bak" "${key}.absent"
}

# update-alternatives: текущий выбор группы / есть ли в группе вариант
alt_current() { update-alternatives --query "$1" 2>/dev/null | awk '/^Value:/{print $2}'; }
alt_has()     { update-alternatives --list "$1" 2>/dev/null | grep -qxF "$2"; }

# ----------------------------------------------------------------------------
# xfconf (XFCE): изменить свойство, запомнив исходное значение для отката
# ----------------------------------------------------------------------------
have_xfce() { have xfconf-query && [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; }

#   xfconf_set <канал> <свойство> <тип> <значение>
xfconf_set() {
    local ch="$1" prop="$2" type="$3" val="$4" key cur
    key="xfconf.${ch}${prop//\//.}"
    if cur="$(xfconf-query -c "$ch" -p "$prop" 2>/dev/null)"; then
        state_set_once "$key" "v:${cur}"
    else
        state_set_once "$key" "absent"
    fi
    xfconf-query -c "$ch" -p "$prop" -s "$val" 2>/dev/null \
        || xfconf-query -c "$ch" -p "$prop" -n -t "$type" -s "$val"
}

#   xfconf_restore <канал> <свойство> — вернуть как было до xfconf_set
xfconf_restore() {
    local ch="$1" prop="$2" key val
    key="xfconf.${ch}${prop//\//.}"
    state_has "$key" || return 0
    val="$(state_get "$key")"
    if [[ "$val" == absent ]]; then
        xfconf-query -c "$ch" -p "$prop" -r 2>/dev/null || true
    else
        xfconf-query -c "$ch" -p "$prop" -s "${val#v:}" 2>/dev/null || true
    fi
    state_del "$key"
}

# Пути плагинов «Часы» на панели XFCE (/plugins/plugin-N)
xfce_clock_plugins() {
    xfconf-query -c xfce4-panel -lv 2>/dev/null | awk '$1 ~ "^/plugins/plugin-[0-9]+$" && $2 == "clock" {print $1}'
}
