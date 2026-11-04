#!/usr/bin/env bash
# modules/forensics.sh — форензика: разбор журналов Windows (Hayabusa) и отчёты по таймлайну (Takajo).

FORENSICS_DIR="/opt"   # инструменты ставятся в /opt/<имя>, команды — в /usr/local/bin

# Скачать последний релиз-архив с GitHub и распаковать в /opt/<имя> (папка — пользователю).
# Бинарник внутри (<имя>-<версия>-lin-x64-gnu) переименовывается в /opt/<имя>/<имя>.
#   install_gh_zip <owner/repo> <grep-маска> <имя>
install_gh_zip() {
    local repo="$1" pattern="$2" name="$3" zip dir="${FORENSICS_DIR}/$3" bin
    zip="${DOWNLOAD_DIR}/${name}.zip"
    have unzip || sudo apt install -y unzip
    gh_latest_asset "$repo" "$pattern" "$zip" || return 1
    sudo rm -rf "$dir"
    sudo mkdir -p "$dir"
    sudo unzip -q "$zip" -d "$dir" || return 1
    sudo chown -R "$USER:" "$dir"   # чтобы обновлять правила без sudo
    bin="$(find "$dir" -maxdepth 1 -type f -name "${name}-*-lin-x64-*" | head -n1)"
    [[ -n "$bin" ]] || { err "В архиве нет бинарника ${name}"; return 1; }
    mv -f "$bin" "${dir}/${name}"
    chmod +x "${dir}/${name}"
}

do_hayabusa() {
    step "Hayabusa (анализ журналов .evtx по правилам Sigma, релиз с GitHub)"
    if [[ -x "${FORENSICS_DIR}/hayabusa/hayabusa" ]]; then
        ok "Hayabusa уже установлена (${FORENSICS_DIR}/hayabusa). Пропускаю."
        return
    fi
    if ! install_gh_zip "Yamato-Security/hayabusa" 'lin-x64-gnu\.zip$' hayabusa; then
        warn "Не удалось поставить Hayabusa — проверь https://github.com/Yamato-Security/hayabusa/releases"
        return 1
    fi
    # правила и config Hayabusa ищет рядом с настоящим бинарником, поэтому хватает симлинка
    sudo ln -sf "${FORENSICS_DIR}/hayabusa/hayabusa" /usr/local/bin/hayabusa
    ok "Hayabusa установлена. Пример: hayabusa json-timeline -d ./logs -L -o timeline.jsonl"
    log "Обновить правила: hayabusa update-rules"
}

do_takajo() {
    step "Takajo (отчёты по результатам Hayabusa, релиз с GitHub)"
    if [[ -x "${FORENSICS_DIR}/takajo/takajo" ]]; then
        ok "Takajo уже установлен (${FORENSICS_DIR}/takajo). Пропускаю."
        return
    fi
    if ! install_gh_zip "Yamato-Security/takajo" 'lin-x64-gnu\.zip$' takajo; then
        warn "Не удалось поставить Takajo — проверь https://github.com/Yamato-Security/takajo/releases"
        return 1
    fi
    # Takajo берёт templates/ и conf/ из ТЕКУЩЕЙ папки, поэтому обёртка запускает его из /opt/takajo,
    # а относительные пути (существующие файлы и значение -o/--output) переводит в абсолютные.
    sudo tee /usr/local/bin/takajo >/dev/null <<EOF
#!/usr/bin/env bash
# kali-setup: обёртка Takajo
args=() prev=""
for a in "\$@"; do
    if [[ \${#args[@]} -gt 0 && "\$a" != -* && "\$a" != /* ]] \\
        && [[ -e "\$a" || "\$prev" == -o || "\$prev" == --output ]]; then
        a="\$PWD/\$a"
    fi
    args+=("\$a"); prev="\$a"
done
cd "${FORENSICS_DIR}/takajo" && exec ./takajo "\${args[@]}"
EOF
    sudo chmod +x /usr/local/bin/takajo
    ok "Takajo установлен. Пример: takajo html-report -t timeline.jsonl -o report"
}
