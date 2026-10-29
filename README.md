# kali-new

**Русский** · [English](#english)

Скрипт для быстрой настройки свежей Kali Linux (в т.ч. на флэшке): обновление системы,
установка приложений и AI-инструментов, настройка системы. У каждого шага есть откат.

## Быстрый старт

```bash
git clone https://github.com/LostErr0r/kali-new.git
cd kali-new
./setup.sh
```

> Запускай от обычного пользователя (`kali`), **не от root** — `sudo` скрипт вызовет сам.

## Запуск

| Команда | Что делает |
|---|---|
| `./setup.sh` | Интерактивное меню: выбор категорий, порядка, пунктов и подтверждение |
| `./setup.sh telegram time` | Выполнить только указанные шаги, без меню |
| `./setup.sh undo telegram time` | Откатить указанные шаги |
| `TZ_ZONE=Europe/Moscow ./setup.sh time` | Задать часовой пояс без меню |

Меню рисуется через [gum](https://github.com/charmbracelet/gum): он ставится из репозитория Kali при первом запуске мастера. Если gum поставить не удалось, будет обычное окно whiptail.

Лог работы пишется в `~/kali-setup.log`.

## Что умеет

### Обновление системы
`apt update` + `full-upgrade` + `autoremove`. Базовые пакеты (curl, git, python3, pipx…)
ставятся автоматически перед приложениями и AI.

### Приложения
| Ключ | Что ставится |
|---|---|
| `discord` | Discord (официальный .deb) |
| `telegram` | Telegram (`telegram-desktop` из репозитория Kali) |
| `keepassxc` | KeePassXC — менеджер паролей (из репозитория Kali) |
| `torbrowser` | Tor Browser (`torbrowser-launcher` из репозитория Kali; первый запуск скачает и проверит браузер) |
| `obsidian` | Obsidian (последний релиз с GitHub) |
| `happ` | Happ — прокси-клиент |
| `amnezia` | AmneziaVPN (автоматическая установка) |
| `docker` | Docker + docker-compose |

### AI: модели и инструменты
| Ключ | Что ставится |
|---|---|
| `claude` | Claude Desktop (официальный apt-репозиторий Anthropic) |
| `deepseek` | DeepSeek Harness (`dsh`, через npm) |
| `graphify` | Graphify — граф кодовой базы, скил `/graphify` |
| `hexstrike` | HexStrike AI — MCP-сервер для AI-ассистента |

### Настройка системы
| Ключ | Что делает |
|---|---|
| `time` | Часовой пояс (выбор: регион → город), синхронизация по NTP, секунды в часах на панели |
| `keyboard` | Вторая раскладка Russian, переключение **Win+Space** |
| `nolock` | Экран не блокируется и не гаснет по таймеру (ручная блокировка работает) |

`keyboard`, `nolock` и секунды в часах рассчитаны на XFCE.

### Кастомизация
Сначала выбираешь окружение, потом его подпункты.

**GNOME**
| Ключ | Что делает |
|---|---|
| `gnome` | Окружение GNOME (`kali-desktop-gnome`) рядом с XFCE. Экран входа остаётся LightDM — сессию выбираешь при входе |
| `gnomeext` | Расширения: Dash to Dock, AppIndicator, Blur my Shell, User Themes, Just Perfection, Caffeine, System Monitor, Freon + Extension Manager. Включаются автоматически |

**Hyprland**
| Ключ | Что делает |
|---|---|
| `hyprland` | Hyprland в стиле [JaKooLit](https://github.com/JaKooLit/Hyprland-Dots): тайлинг, Waybar, Rofi, swaync, hyprlock, Quickshell — пакеты из репозитория Kali, `awww` и `wallust` собираются через cargo, конфиги — из JaKooLit/Hyprland-Dots |

- Нужна видеокарта с ускорением. В VMware: *Settings → Display → Accelerate 3D graphics*.
- Текущие `~/.config/{hypr,waybar,rofi,kitty,…}` сохраняются; `./setup.sh undo hyprland` возвращает их.
- Клавиши: **SUPER+H** — шпаргалка, **SUPER+Enter** — терминал, **SUPER+D** — меню, **SUPER+Q** — закрыть окно, **SUPER+1…0** — рабочие столы, **Alt+Shift** — раскладка.

**XFCE** — украсить текущее окружение
| Ключ | Что делает |
|---|---|
| `xtheme` | Тема GTK + рамки окон в палитре, папки Papirus под цвет, курсор Bibata, шрифты Inter + JetBrainsMono Nerd |
| `xpanel` | Верхняя панель 36 px, полупрозрачная, часы по центру, без значка уведомлений |
| `xpicom` | Picom: скруглённые углы, тени, размытие, плавное появление окон (без 3D — лёгкий режим без размытия) |
| `xextras` | Rofi по **SUPER+D**; Conky-виджет на Lua/Cairo — часы, кольца CPU/RAM/диск, сеть с графиками, VPN (`tun0`/`amn0`/`wg0`), внешний IP и **заметки** из `~/notes.txt` (правка — **Win+N**; `# ` — заголовок, `x ` — сделано); обои в цветах палитры |

Палитры: **Catppuccin Mocha**, **Nordic**, **Orchis**, **Dracula** — спрашиваются один раз при установке.
Без меню: `PALETTE=nordic ./setup.sh xtheme xextras`.

## Откат

Перед изменением настроек скрипт запоминает исходные значения в
`~/.local/state/kali-setup/`, поэтому `./setup.sh undo <ключ>` возвращает именно то,
что было до него. Откатить можно всё, кроме обновления системы.

## Структура

```
setup.sh              — точка входа: меню, списки шагов, диспетчер
assets/conky/         — Lua-виджет Conky (копируется шагом xextras)
lib/ui.sh             — меню мастера (gum, запасной вариант — whiptail)
lib/common.sh         — общие помощники: вывод/лог, установка, состояние для отката, xfconf
modules/
  system.sh           — обновление системы, базовые пакеты
  apps.sh             — приложения
  ai.sh               — AI-инструменты
  settings.sh         — настройка системы
  custom.sh           — кастомизация: GNOME, Hyprland, XFCE
  uninstall.sh        — откат всех шагов
```

### Как добавить новый шаг
1. Функция `do_<ключ>` в нужном модуле (`modules/*.sh`).
2. Ключ и описание — в списки категории в `setup.sh` (`APP_STEPS`/`APP_DESC` и т.п.) и в `run_step`.
3. Функция `undo_<ключ>` в `modules/uninstall.sh`, ключ — в `run_undo`, `REVERT_STEPS` и `REVERT_DESC`.

---

## English

[Русский](#kali-new) · **English**

A script for quickly setting up a fresh Kali Linux install (including a live USB): system update,
apps and AI tools, system tweaks. Every step can be rolled back.

### Quick start

```bash
git clone https://github.com/LostErr0r/kali-new.git
cd kali-new
./setup.sh
```

> Run it as a regular user (`kali`), **not as root** — the script calls `sudo` itself.

### Usage

| Command | What it does |
|---|---|
| `./setup.sh` | Interactive menu: pick categories, order, items, then confirm |
| `./setup.sh telegram time` | Run only the listed steps, no menu |
| `./setup.sh undo telegram time` | Roll back the listed steps |
| `TZ_ZONE=Europe/Moscow ./setup.sh time` | Set the time zone without the menu |

The menu is drawn with [gum](https://github.com/charmbracelet/gum), which is installed from the Kali repository on the first run. If gum can't be installed, a plain whiptail dialog is used instead.

The log is written to `~/kali-setup.log`.

> The script's interface (menus, messages) is in Russian.

### Features

#### System update
`apt update` + `full-upgrade` + `autoremove`. Base packages (curl, git, python3, pipx…)
are installed automatically before apps and AI tools.

#### Apps
| Key | What gets installed |
|---|---|
| `discord` | Discord (official .deb) |
| `telegram` | Telegram (`telegram-desktop` from the Kali repository) |
| `keepassxc` | KeePassXC — password manager (from the Kali repository) |
| `torbrowser` | Tor Browser (`torbrowser-launcher` from the Kali repository; the first launch downloads and verifies the browser) |
| `obsidian` | Obsidian (latest GitHub release) |
| `happ` | Happ — proxy client |
| `amnezia` | AmneziaVPN (unattended install) |
| `docker` | Docker + docker-compose |

#### AI: models and tools
| Key | What gets installed |
|---|---|
| `claude` | Claude Desktop (official Anthropic apt repository) |
| `deepseek` | DeepSeek Harness (`dsh`, via npm) |
| `graphify` | Graphify — codebase knowledge graph, `/graphify` skill |
| `hexstrike` | HexStrike AI — MCP server for an AI assistant |

#### System settings
| Key | What it does |
|---|---|
| `time` | Time zone (pick region → city), NTP sync, seconds in the panel clock |
| `keyboard` | Adds a Russian layout, switch with **Win+Space** |
| `nolock` | Screen doesn't lock or blank on a timer (manual lock still works) |

`keyboard`, `nolock` and the clock seconds are made for XFCE.

#### Customization
First pick a desktop environment, then its items.

**GNOME**
| Key | What it does |
|---|---|
| `gnome` | GNOME desktop (`kali-desktop-gnome`) alongside XFCE. The login screen stays LightDM — choose the session when logging in |
| `gnomeext` | Extensions: Dash to Dock, AppIndicator, Blur my Shell, User Themes, Just Perfection, Caffeine, System Monitor, Freon + Extension Manager. Enabled automatically |

**Hyprland**
| Key | What it does |
|---|---|
| `hyprland` | Hyprland in the style of [JaKooLit](https://github.com/JaKooLit/Hyprland-Dots): tiling, Waybar, Rofi, swaync, hyprlock, Quickshell — packages from the Kali repository, `awww` and `wallust` built with cargo, configs from JaKooLit/Hyprland-Dots |

- Requires a GPU with acceleration. In VMware: *Settings → Display → Accelerate 3D graphics*.
- Your current `~/.config/{hypr,waybar,rofi,kitty,…}` are backed up; `./setup.sh undo hyprland` restores them.
- Keys: **SUPER+H** — cheat sheet, **SUPER+Enter** — terminal, **SUPER+D** — menu, **SUPER+Q** — close window, **SUPER+1…0** — workspaces, **Alt+Shift** — keyboard layout.

**XFCE** — make the current desktop look nicer
| Key | What it does |
|---|---|
| `xtheme` | GTK theme + window borders in the palette, matching Papirus folders, Bibata cursor, Inter + JetBrainsMono Nerd fonts |
| `xpanel` | 36 px semi-transparent top panel, centered clock, no notification icon |
| `xpicom` | Picom: rounded corners, shadows, blur, smooth window fade-in (without 3D — a light mode with no blur) |
| `xextras` | Rofi on **SUPER+D**; a Lua/Cairo Conky widget — clock, CPU/RAM/disk rings, network with graphs, VPN (`tun0`/`amn0`/`wg0`), external IP and **notes** from `~/notes.txt` (edit with **Win+N**; `# ` — heading, `x ` — done); wallpaper in the palette colors |

Palettes: **Catppuccin Mocha**, **Nordic**, **Orchis**, **Dracula** — asked once during install.
Without the menu: `PALETTE=nordic ./setup.sh xtheme xextras`.

### Rollback

Before changing any settings the script saves the original values to
`~/.local/state/kali-setup/`, so `./setup.sh undo <key>` restores exactly what was there
before. Everything can be rolled back except the system update.

### Layout

```
setup.sh              — entry point: menu, step lists, dispatcher
assets/conky/         — Conky Lua widget (copied by the xextras step)
lib/ui.sh             — wizard menu (gum, falls back to whiptail)
lib/common.sh         — shared helpers: output/log, install, rollback state, xfconf
modules/
  system.sh           — system update, base packages
  apps.sh             — apps
  ai.sh               — AI tools
  settings.sh         — system settings
  custom.sh           — customization: GNOME, Hyprland, XFCE
  uninstall.sh        — rollback for all steps
```

#### Adding a new step
1. A `do_<key>` function in the right module (`modules/*.sh`).
2. The key and description go into the category lists in `setup.sh` (`APP_STEPS`/`APP_DESC` etc.) and into `run_step`.
3. An `undo_<key>` function in `modules/uninstall.sh`; the key goes into `run_undo`, `REVERT_STEPS` and `REVERT_DESC`.
