#!/usr/bin/env bash
# modules/ai.sh — AI: модели и инструменты (Claude Desktop, DeepSeek Harness, Graphify, HexStrike AI).

do_claude() {
    step "Claude Desktop (официальный apt-репозиторий Anthropic)"
    if pkg_installed claude-desktop; then
        ok "Claude Desktop уже установлен (v$(dpkg-query -W -f='${Version}' claude-desktop 2>/dev/null)). Пропускаю."
        return
    fi
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

do_deepseek() {
    step "DeepSeek Harness (dsh) — кодинг-агент от DeepSeek"
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
    if have dsh || npm ls -g @deepseek-ai/dsh >/dev/null 2>&1; then
        ok "DeepSeek Harness (dsh) уже установлен ($(dsh --version 2>/dev/null)). Пропускаю."
        return
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

do_graphify() {
    step "Graphify (граф кодовой базы + скил для AI-ассистента)"
    # PyPI-пакет называется graphifyy (двойная y), команда — graphify. Нужен Python 3.10+ и pipx.
    # Копия исходников/скила лежит в репозитории проекта: skills/graphify/
    if have graphify; then
        ok "Graphify уже установлен ($(graphify --version 2>/dev/null)). Пропускаю установку CLI."
    else
        have pipx || sudo apt install -y pipx 2>/dev/null || true
        pipx ensurepath >/dev/null 2>&1 || true
        if pipx install graphifyy 2>/dev/null; then
            ok "Graphify CLI установлен через pipx (команда: graphify)."
        else
            warn "Не удалось поставить graphifyy через pipx. Поставь вручную: pipx install graphifyy"
            return 1
        fi
    fi
    # Регистрируем скил у обнаруженного ассистента (Claude Code / Cursor / Codex и т.п.)
    if have graphify; then
        if graphify install 2>/dev/null; then
            ok "Скил graphify зарегистрирован. В ассистенте: /graphify .  — построить граф текущей папки."
        else
            warn "'graphify install' не отработал автоматически — выполни его вручную в нужной папке."
        fi
    fi
    log "Исходники и скил Graphify также лежат в репозитории проекта: ${SCRIPT_DIR:-.}/skills/graphify/"
}

do_hexstrike() {
    step "HexStrike AI (MCP-сервер для AI-ассистента)"
    if pkg_installed hexstrike-ai; then
        ok "HexStrike уже установлен (пакет Kali hexstrike-ai). Пропускаю."
        return
    fi
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
