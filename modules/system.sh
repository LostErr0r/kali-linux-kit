#!/usr/bin/env bash
# modules/system.sh — обновление системы и базовые пакеты.

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
