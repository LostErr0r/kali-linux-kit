#!/usr/bin/env bash
# modules/web.sh — веб-пентест: словари SecLists, перебор директорий и параметров (ffuf, gobuster).
# Ставится из репозитория Kali через pentest_apt (modules/pentest.sh) — с тем же откатом.

do_seclists() {
    step "SecLists — словари для перебора, из репозитория Kali"
    pentest_apt seclists "SecLists" seclists && log "Словари: /usr/share/seclists (около 2 ГБ)"
}

do_ffuf() {
    step "ffuf — быстрый веб-фаззер, из репозитория Kali"
    pentest_apt ffuf "ffuf" ffuf \
        && log "Команда: ffuf -u https://site/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt"
}

do_gobuster() {
    step "gobuster — перебор директорий, DNS и vhost, из репозитория Kali"
    pentest_apt gobuster "gobuster" gobuster \
        && log "Команда: gobuster dir -u https://site -w /usr/share/seclists/Discovery/Web-Content/common.txt"
}
