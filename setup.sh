#!/usr/bin/env bash
#
# setup.sh — первичная настройка рабочей Kali Linux (в т.ч. на флэшке).
#
# Что делает:
#   1. Обновляет систему (apt update + full-upgrade).
#   2. Ставит базовые инструменты (curl, wget, git, gpg и т.д.).
#   3. Ставит приложения: Claude Desktop, Discord, Obsidian, Happ, AmneziaVPN.
#   4. Ставит MCP-сервер HexStrike AI.
#   5. (опционально) DeepSeek harness — см. блок в конце, нужно уточнение.
#
# Запуск:
#   chmod +x setup.sh
#   ./setup.sh                 # всё целиком
#   ./setup.sh system claude   # только выбранные шаги (см. ниже список)
#
# ВАЖНО: запускай от ОБЫЧНОГО пользователя (kali), НЕ от root.
#        sudo скрипт попросит сам, где нужно.
#
set -uo pipefail

# ----------------------------------------------------------------------------
# Настройки
# ----------------------------------------------------------------------------
LOG_FILE="${HOME}/kali-setup.log"
DOWNLOAD_DIR="$(mktemp -d /tmp/kali-setup.XXXXXX)"   # сюда качаем установщики
HEXSTRIKE_DIR="${HOME}/tools/hexstrike-ai"           # куда клонировать hexstrike (если ставим из git)

# ----------------------------------------------------------------------------
# Вспомогательные функции
# ----------------------------------------------------------------------------
RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

log()   { echo "${BLUE}[*]${RESET} $*" | tee -a "$LOG_FILE"; }
ok()    { echo "${GREEN}[+]${RESET} $*" | tee -a "$LOG_FILE"; }
warn()  { echo "${YELLOW}[!]${RESET} $*" | tee -a "$LOG_FILE"; }
err()   { echo "${RED}[x]${RESET} $*" | tee -a "$LOG_FILE"; }
step()  { echo; echo "${BOLD}${BLUE}==== $* ====${RESET}" | tee -a "$LOG_FILE"; }

# Проверка: установлена ли команда
have() { command -v "$1" >/dev/null 2>&1; }

# Проверка: установлен ли deb-пакет
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

# ----------------------------------------------------------------------------
# Подготовка
# ----------------------------------------------------------------------------
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
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; rm -rf "$DOWNLOAD_DIR"' EXIT

: > "$LOG_FILE"
log "Лог пишется в $LOG_FILE"
log "Временные файлы: $DOWNLOAD_DIR"

# ============================================================================
# ШАГИ
# ============================================================================

do_system() {
    step "1. Обновление системы"
    sudo apt update
    sudo apt full-upgrade -y
    sudo apt autoremove -y
    ok "Система обновлена"
}

do_base() {
    step "2. Базовые инструменты"
    sudo apt install -y \
        curl wget git gnupg ca-certificates apt-transport-https \
        software-properties-common jq unzip build-essential \
        python3 python3-pip python3-venv pipx
    ok "Базовые пакеты установлены"
}

do_claude() {
    step "3. Claude Desktop (официальный apt-репозиторий Anthropic)"
    # Ключ подписи
    sudo curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc
    # Регистрируем репозиторий
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null
    sudo apt update
    if sudo apt install -y claude-desktop; then
        ok "Claude Desktop установлен. Запуск: claude-desktop (войди в аккаунт Anthropic)"
    else
        warn "Не удалось поставить из репозитория. Проверь доступ к downloads.claude.ai."
    fi
}

do_discord() {
    step "4. Discord (официальный .deb)"
    local deb="${DOWNLOAD_DIR}/discord.deb"
    if curl -fL --retry 3 -o "$deb" "https://discord.com/api/download?platform=linux&format=deb"; then
        install_deb "$deb" && ok "Discord установлен"
    else
        warn "Не скачался Discord .deb"
    fi
}

do_obsidian() {
    step "5. Obsidian (последний .deb с GitHub)"
    local deb="${DOWNLOAD_DIR}/obsidian.deb"
    if gh_latest_asset "obsidianmd/obsidian-releases" 'amd64\.deb$' "$deb"; then
        install_deb "$deb" && ok "Obsidian установлен"
    else
        warn "Не удалось получить Obsidian .deb"
    fi
}

do_happ() {
    step "6. Happ (последний .deb с GitHub)"
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

do_hexstrike() {
    step "8. HexStrike AI (MCP-сервер)"
    # Вариант А — пакет Kali (самый простой):
    if sudo apt install -y hexstrike-ai 2>/dev/null && pkg_installed hexstrike-ai; then
        ok "HexStrike установлен из репозитория Kali (hexstrike-ai)"
        return
    fi
    # Вариант Б — из исходников (официальный репозиторий 0x4m4/hexstrike-ai):
    warn "Пакет Kali не поставился, ставлю из git..."
    mkdir -p "$(dirname "$HEXSTRIKE_DIR")"
    if [[ -d "$HEXSTRIKE_DIR/.git" ]]; then
        git -C "$HEXSTRIKE_DIR" pull --ff-only
    else
        git clone https://github.com/0x4m4/hexstrike-ai.git "$HEXSTRIKE_DIR"
    fi
    python3 -m venv "$HEXSTRIKE_DIR/venv"
    "$HEXSTRIKE_DIR/venv/bin/pip" install --upgrade pip
    "$HEXSTRIKE_DIR/venv/bin/pip" install -r "$HEXSTRIKE_DIR/requirements.txt"
    ok "HexStrike установлен в $HEXSTRIKE_DIR"
    cat <<EOF | tee -a "$LOG_FILE"
  Запуск сервера:  ${HEXSTRIKE_DIR}/venv/bin/python ${HEXSTRIKE_DIR}/hexstrike_server.py
  Подключение MCP к Claude: добавь в конфиг mcpServers запись, которая запускает
  hexstrike_mcp.py с аргументом --server http://localhost:8888
EOF
}

do_deepseek() {
    step "9. DeepSeek Harness (dsh) — кодинг-агент от DeepSeek"
    # DeepSeek Harness ставится через npm как пакет @deepseek-ai/dsh.
    # Нужен Node.js >= 22.19 (рекомендуется Node 24). Если Node нет или он старый —
    # ставим Node 24 из официального репозитория NodeSource.
    local need_node=1
    if have node; then
        local major
        major=$(node -v | sed 's/^v//' | cut -d. -f1)
        if [[ "$major" -ge 22 ]]; then need_node=0; fi
    fi
    if [[ "$need_node" -eq 1 ]]; then
        log "Ставлю Node.js 24 из NodeSource..."
        curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    if ! have npm; then
        err "npm не найден — не могу поставить dsh. Проверь установку Node.js."
        return 1
    fi
    log "Ставлю DeepSeek Harness (@deepseek-ai/dsh) глобально через npm..."
    if sudo npm install -g @deepseek-ai/dsh; then
        ok "DeepSeek Harness установлен."
        log "  Запуск НЕ командой 'dsh', а с указанием профиля:"
        log "    dsh tui                      — терминальный интерфейс"
        log "    dsh web                      — веб-интерфейс (http://127.0.0.1:3080)"
        log "    dsh headless \"задача\"         — разовая задача без интерфейса"
        warn "При первом запуске нужен API-ключ DeepSeek (platform.deepseek.com) и выбор рабочей папки."
    else
        warn "Не удалось поставить @deepseek-ai/dsh. Проверь имя пакета в офиц. репозитории DeepSeek Harness."
    fi
}

# ============================================================================
# Запуск: все шаги или только выбранные аргументами
# ============================================================================
ALL_STEPS=(system base claude discord obsidian happ amnezia hexstrike deepseek)

run_step() {
    case "$1" in
        system)   do_system ;;
        base)     do_base ;;
        claude)   do_claude ;;
        discord)  do_discord ;;
        obsidian) do_obsidian ;;
        happ)     do_happ ;;
        amnezia)  do_amnezia ;;
        hexstrike) do_hexstrike ;;
        deepseek) do_deepseek ;;
        *) err "Неизвестный шаг: $1 (доступно: ${ALL_STEPS[*]})"; return 1 ;;
    esac
}

main() {
    local steps=("$@")
    [[ ${#steps[@]} -eq 0 ]] && steps=("${ALL_STEPS[@]}")
    for s in "${steps[@]}"; do
        run_step "$s" || warn "Шаг '$s' завершился с ошибкой — продолжаю дальше."
    done
    step "Готово"
    ok "Все выбранные шаги выполнены. Полный лог: $LOG_FILE"
}

main "$@"
