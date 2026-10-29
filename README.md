# kali-new

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
