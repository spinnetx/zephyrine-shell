# Zephyrine · Центр настроек — дизайн

Статус: проект (2026-10-02), ничего из описанного ещё не реализовано. Документ — спецификация для
независимой реализации частей разными агентами: у каждой части есть входы, выходы, контракт и
способ проверки без GUI. Решения пользователя (форма, разделы, генератор тем) не пересматриваются.

Нумерация разделов: §1 решения и факты · §2 архитектура · §3 генератор тем · §4 бэкенды ·
§5 модель данных · §6 UI · §7 безопасность и откат · §8 проверка без GUI · §9 план · §10 вопросы ·
§11 ловушки для исполнителей.

---------------------------------------------------------------------------------------------------

## 1. Ключевые решения и проверенные факты

### 1.1 Решения (кратко)

| # | Решение | Почему |
|---|---|---|
| D1 | Окно — `FloatingWindow` в том же процессе `qs` (создаётся `LazyLoader` при открытии), обычное окно Hyprland с правилом float/size/center | Не блокирует клавиатуру других окон (в отличие от overlay-слоя лаунчера), двигается, получает стекло hyprglass как остальные окна, поля ввода работают без `HyprlandFocusGrab`. Альтернатива — §2.8 |
| D2 | Единственный писатель настроек — CLI `zephyrine-settings` (Python 3, только stdlib). Шелл только читает (FileView) и показывает превью | Валидация, бэкапы, блокировка, применение — в одном месте, и это место тестируется из sandbox без GUI |
| D3 | Источник правды = `quickshell/scheme.json` (база палитры, дополняется «ext»-цветами, §3.4) + `settings/settings.json` (только отличия от дефолтов из `settings/schema.json`). Всё остальное — генерируемые артефакты | Ровно формулировка пользователя «scheme.json + настройки» |
| D4 | Темы — шаблоны с чистой подстановкой (без логики) + «якорная» деривация с short-circuit: при значениях по умолчанию подставляются исходные литералы → вывод байт-в-байт равен текущим файлам. Golden-тест — обязательный шлюз | Гарантия «не сломать существующий вид» |
| D5 | Hyprland — генерируемый `~/.config/hypr/settings.lua`, подключается в конце `hyprland.lua` через `pcall(dofile, …)`; применяется `hyprctl reload config-only`. Мониторы — runtime-`eval` со сторожем отката ВНУТРИ компоситора | Никакого редактирования живого Lua регэкспами; ошибка в сгенерированном файле не ломает основной конфиг |
| D6 | `Colors.qml` дополнительно читает сгенерированный `quickshell/scheme.override.json` (по умолчанию `{"colours": {}}`); `Config.qml` связывает выбранные константы с новым синглтоном `Prefs` с теми же значениями по умолчанию | Имена свойств не меняются → остальной бар не трогается |
| D7 | IPC-таргет `settings`: `open()`, `openAt(section)`, `toggle()`, `close()`. Форма «`open [раздел]`» доступна как `zephyrine-settings open [раздел]` (CLI сам выбирает функцию) | Проверено: IPC Quickshell 0.3.1 требует точное число аргументов (§1.2) |
| D8 | `state.json`/`Persist.qml` не трогаем: там рантайм-состояние (DND, instance). Настройки ≠ состояние: DND переключается через `Notifs.dnd`, как сейчас | Нет двух источников правды для одного флага |

### 1.2 Проверено на этой машине (2026-10-02)

- Quickshell 0.3.1 (`quickshell-git`), Hyprland 0.56.2, Python 3.14 (+ `jinja2` 3.1.6 установлен явно, но в
  дизайне не обязателен), `lua`/`luac`/`luajit`, `node`, `jq`, `ffmpeg`/`ffprobe`, `wl-copy`, `hyprpicker`, `gio`.
- IPC: `qs -p ~/.config/quickshell/zephyrine ipc call toaster notify "x"` → «Too few arguments provided (3
  required but 1…)», лишний аргумент → «Too many arguments». **Код возврата при этом 0** — скрипты должны
  разбирать вывод, а не `$?`. Имя функции `show` конфликтует с подкомандой `qs ipc show` (известно по Toaster).
- `qs log -p ~/.config/quickshell/zephyrine -t N` из sandbox работает — ошибки QML видны без GUI.
- Hyprland Lua: `dofile`, `require`, `pcall`, `loadfile`, `io`, `os` доступны; `package.path` начинается с
  `~/.config/hypr/?.lua`. `hl.get_config("…")` читает значения (`general.col.active_border` → таблица
  `colors={0xEE33CCFF,0xEE00FF99}, angle=45`; `plugin.hyprglass.glass_opacity` = 0.7; `input.repeat_rate` 25,
  `repeat_delay` 600). Есть `hl.unbind(key)`, `hl.bind(…, {description=…})`, `hl.timer`, `hl.notification.create`,
  `hl.monitor({output, mode, position, scale, transform, disabled, mirror, …})`, `hyprctl configerrors`,
  `hyprctl reload config-only`, `hyprctl output create headless`.
- `hyprctl binds -j` для Lua-биндов отдаёт `dispatcher: "__lua", arg: "<внутренний id>"` — **команда бинда не
  видна**, опознать бинд можно только по `description` (сейчас у всех пустой).
- `hyprctl dispatch dpms on` (старый синтаксис) → ошибка Lua; `hyprctl dispatch 'hl.dsp.dpms({action="on"})'` → ok.
  Значит, `hypridle.conf` (`hyprctl dispatch dpms off/on`) сейчас **не гасит экран** по таймауту (§10, вопрос 1).
- Мониторы: сейчас только `eDP-1` (1920x1080@60, режимы до 120 Гц). `wlr-randr`, `nwg-displays` — нет.
- Палитра: в 12 файлах тем 31 уникальный цвет, которого нет в `scheme.json` (4 из них — рамки Hyprland, не из
  палитры). `scheme.json` и `zed/themes/zephyrine.json` воспроизводятся `json.dumps(indent=4/2)` **без**
  финального `\n`; `thunderbird/zephyrine-theme/manifest.json` — не воспроизводится (инлайн-объект `gecko`).
- Obsidian: `--interactive-accent-hsl: 267, 85%, 78%` — ручное приближение; реальный HSL `#bb9af7` = 261°, 85%,
  79% → формулой не воспроизвести, нужен литерал с якорем (§3.5).
- Живые копии совпадают с репо: gtk-3.0/4.0 (`gtk.css`, `settings.ini`), qt6ct, тема Obsidian во всех 3 vault'ах,
  Thunderbird `userChrome.css` и `manifest.json` внутри xpi, Zen `userChrome.css`/`userContent.css`. Путь
  профиля Zen содержит пробелы: `smhkr7xv.Default (release)`.
- XDG-автозапуск в сессии **не работает** (`xdg-desktop-autostart.target` inactive): `~/.config/autostart/
  {org.telegram.desktop,ssh-add}.desktop` никто не исполняет. `dex` установлен, но не вызывается.
- Портал `Settings=gtk` → GTK читает gsettings: `gtk-theme 'adw-gtk3-dark'`, `color-scheme 'prefer-dark'`,
  `font-name 'Inter  10'`, `monospace-font-name 'JetBrainsMono Nerd Font  10'`.

---------------------------------------------------------------------------------------------------

## 2. Архитектура

### 2.1 Потоки данных

```
              ┌──────────────────────── qs (процесс шелла) ────────────────────────┐
  IPC/бинд →  │ Overlays.settingsOpen ─→ LazyLoader ─→ SettingsWindow (FloatingWindow) │
  кнопки   →  │        ▲                                   │  ▲ читает                 │
              │        │                     Prefs.set(k,v)│  │ Prefs.values/preview   │
              │        │                                   ▼  │                        │
              │        │                SettingsCli (очередь Process) ──┐              │
              │   Config.qml ◄─ Prefs.qml ◄─ FileView(settings.json)    │              │
              │   Colors.qml ◄─ FileView(scheme.json + scheme.override.json)           │
              └───────────────────────────────────────────────────────┼──────────────┘
                                                                      ▼ argv, JSON на stdout
                         zephyrine-settings (Python, flock, валидация по schema.json)
                           │ 1) пишет settings.json (атомарно, история для undo)
                           │ 2) палитра = scheme.json ⊕ деривация акцента (palette-roles.json)
                           │ 3) рендер целей (templates/*.tmpl, эмиттеры) → сравнение с текущим
                           │ 4) бэкап → запись в репо → деплой живых копий → reload-действия
                           ▼
   quickshell/scheme.override.json · .config/hypr/settings.lua · gtk.css · qt6ct · zed · kitty · zathura ·
   Obsidian (3 vault'а) · Thunderbird (профиль + xpi) · Zen (профиль) · (этап 3) hypridle.conf
```

### 2.2 Структура файлов

Репозиторий `~/my_zephyrine_conf/` (новое помечено `+`, генерируемое — `G`):

```
settings/
  DESIGN.md                      этот документ
+ schema.json                    ключи, типы, дефолты, диапазоны, цели применения (§5) — общая для CLI и UI
+ settings.json                  значения пользователя: ТОЛЬКО отличия от дефолтов (на старте {"version": 1})
+ palette-roles.json             якоря производных цветов/строк (§3.5) — метаданные, не данные пользователя
+ targets.json                   манифест целей (§3.2): вид, шаблон, выход, деплой, reload, detect
+ templates/<приложение>/*.tmpl  шаблоны тем (§3.3)
+ zsettings/                     Python-пакет, только stdlib:
    __main__.py cli.py model.py color.py render.py palette.py targets.py hypr.py idle.py
    backup.py doctor.py sysinfo.py util.py
+ bin/zephyrine-settings         #!/bin/sh: PYTHONPATH="$(dirname "$0")/.." exec python3 -m zsettings "$@"
+ tests/                         unittest + снимки (§8): test_*.py, snapshots/perturb/*.txt, mock_hl.lua,
                                 fixtures/home/ (фейковые профили Zen/TB, obsidian.json, vault'ы)
quickshell/
  scheme.json                    ИСТОЧНИК базовой палитры; дополняется ext-ключами (§3.4), формат не меняется
G scheme.override.json           только переопределённые ключи, по умолчанию {"colours": {}}
+ Prefs.qml                      синглтон в КОРНЕ (рядом с Config/Colors; в qmldir: singleton Prefs Prefs.qml)
  Config.qml, Colors.qml         точечные правки (§2.6)
  services/Overlays.qml          + settingsOpen/settingsSection + IpcHandler "settings"
+ services/SettingsCli.qml       очередь вызовов CLI, разбор JSON-результата, тосты
+ services/Displays.qml          (этап 3) мониторы: снимок, try/confirm/revert через CLI
+ components/                    общие контролы настроек (§6.2): SetCard, SetRow, SetSlider, SetDropdown,
                                 SetSegmented, SetButton, StatusChip, HexField
+ settings/                      окно: SettingsWindow.qml, Sidebar.qml, PageHeader.qml,
                                 pages/{Appearance,Network,Devices,System}Page.qml,
                                 parts/*.qml (AccentPicker, TargetsList, WallpaperGrid, MonitorCard,
                                 MonitorConfirm, BindsList, KeyCapture, LayoutsEditor, DefaultApps,
                                 AutostartList, AboutCard), logic.js + logic-test.js (node)
.config/hypr/
  hyprland.lua                   ОДНОРАЗОВАЯ правка (§3.9): подключение settings.lua, бинд SUPER+I, правило окна
G settings.lua                   генерируется эмиттером (§3.9)
G hypridle.conf                  генерируется с этапа 3 (сейчас ручной)
```

Состояние `~/.local/state/zephyrine/` (каталог 700; существующие `state.json`, `notifs.json`,
`launcher-history.json` не трогаем):

```
settings.lock                    flock для CLI (одновременно — один писатель)
generated.json                   sha256 последнего записанного вывода по каждой цели (drift, §3.6),
                                 счётчик версии xpi Thunderbird
backups/<YYYYmmdd-HHMMSS>-<причина>/manifest.json + файлы      последние 20, каталог 700
settings-history/<ts>.json       версии settings.json для «Отменить» (последние 50)
monitor-pending.json             токен и снимок мониторов на время подтверждения (этап 3)
wallpaper-desktop, wallpaper-lock   симлинки на выбранные видео (v1.1, §4.1)
cache/wallpaper-thumbs/<sha1>.jpg   превью обоев (ffmpeg)
```

### 2.3 Хранение настроек

**Формат.** JSON, `"version": 1`, вложенные объекты; в файле только ключи, отличные от дефолта
(«разреженный»). Эффективное значение = `settings.json` ⊕ `schema.json.default`. Плюсы: смена дефолта в схеме
доходит до пользователя; файл маленький; golden-состояние = пустой файл. Запись — только CLI: атомарно
(tmp в том же каталоге → fsync → rename), права 644 (секретов нет: пароли Wi-Fi живут только в
NetworkManager), предыдущая версия → `settings-history/`.

**Где.** Варианты:

| Вариант | Плюсы | Минусы |
|---|---|---|
| **A (рекомендую).** `~/my_zephyrine_conf/settings/settings.json` | Рядом с `scheme.json` — вместе это и есть «источник правды»; попадает в «нулевой конфиг», переносится `deploy.sh` | Машинно-специфичное (мониторы) тоже в репо — смягчается привязкой мониторов по `desc:` (на другой машине правила просто не совпадут) |
| B. `~/.config/zephyrine/settings.json` | XDG-стандарт, машинно-локально | Не попадает в репо; нужна ещё одна строка в snapshot/deploy |
| C. `~/.local/state/zephyrine/settings.json` | Рядом с `state.json` | Смешивает настройки и рантайм-состояние |

**Согласование с Persist/state.json.** Правило: «настройка» — то, что пользователь выбрал осознанно и хочет
восстановить на новой машине (тема, шрифты, таймауты, раскладки); «состояние» — рантайм (DND, instance,
история). `Persist.qml` и `state.json` остаются как есть; `Prefs.qml` повторяет их приёмы (FileView,
`printErrors: false`, флаг `ready`, безопасные дефолты до загрузки), но ничего не пишет сам.

Путь до репо в QML — абсолютный `Quickshell.env("HOME") + "/my_zephyrine_conf/…"` (как `Config.lockCommand`);
**не** `Quickshell.shellPath("../…")`: `~/.config/quickshell/zephyrine` — симлинк, `..` разрешится не туда.

### 2.4 Контракт CLI (граница между QML- и Python-частями)

```
zephyrine-settings get [KEY]                       → JSON эффективных значений (с дефолтами)
zephyrine-settings set KEY=VALUE… [--no-apply] [--dry-run]
zephyrine-settings reset KEY…                      → удалить ключи из settings.json (вернуть дефолт)
zephyrine-settings apply [--targets a,b] [--dry-run] [--force] [--no-exec]
zephyrine-settings render --target T [--out DIR] [--settings FILE] [--scheme FILE]
zephyrine-settings status                          → JSON по целям: installed/managed/drift/restart/lastApplied
zephyrine-settings doctor                          → JSON доступности бэкендов (§4) для UI и тестов
zephyrine-settings undo                            → предыдущая версия settings.json + apply
zephyrine-settings backup list | restore ID
zephyrine-settings open [SECTION]                  → qs ipc call settings open | openAt SECTION
zephyrine-settings monitors snapshot|try SPEC|confirm TOKEN|revert TOKEN   (этап 3)
zephyrine-settings sysinfo                         → JSON для «О системе» (этап 4, Y6)
zephyrine-settings xkb                             → каталог раскладок/вариантов/опций из base.lst (Y1)
zephyrine-settings binds list | check COMBO [--ignore ID] | capture | release   → сочетания: каталог действий + прочие бинды Hyprland, занятость, submap захвата (Y2)
zephyrine-settings autostart                       → инфраструктурные exec_cmd из hyprland.lua (только просмотр) (Y4)
zephyrine-settings mime list | set CATEGORY APP.desktop [--no-exec]   → приложения по умолчанию (Y3; gio mime, в settings.json не пишется)
zephyrine-settings test golden|perturb [KEY]|lint|all
```

- Значения в `set`: JSON-литерал, если парсится (`0.9`, `true`, `null`, `"#7aa2f7"`), иначе строка.
  Несколько пар — одна транзакция (одна запись, один apply).
- Вывод — **одна строка JSON на stdout**, логи — stderr:
  `{"ok":true,"changed":["quickshell","gtk3","kitty"],"actions":["kitty:usr1"],"restart":["thunderbird","zen"],
  "skipped":[{"target":"zen","reason":"profile-not-found"}],"errors":[],"backup":"20261002-101112-set"}`
- Коды выхода: 0 — ок; 1 — частичный сбой (часть целей); 2 — ошибка валидации; 3 — занято (flock 5 с);
  4 — отказ из-за drift (без `--force`); 5 — внутренняя ошибка.
- Переменные для тестов: `ZEPHYRINE_ROOT` (репо), `ZEPHYRINE_STATE` (каталог состояния), обычный `HOME`
  (изолированный HOME для интеграционного теста). `--no-exec` — не трогать процессы (kill/reload/gsettings) —
  обязателен при запуске из sandbox Claude.
- Процессы, которые должны пережить CLI (mpvpaper, hypridle), стартуют с `start_new_session=True`.

### 2.5 Как окно получает и применяет значения

1. **Чтение.** `Prefs.qml` держит `FileView { watchChanges: true }` на `settings.json` и на `schema.json`;
   `values` = merge(defaults, file). Пока не загружено или JSON битый — последние валидные значения/дефолты
   (как `Colors.apply`). Для ключей, нужных бару, — явные типизированные свойства (`glassAlpha`, `radius`,
   `shellFont`…), для UI — `get(key)`/`def(key)`/`range(key)` из схемы.
2. **Превью.** `Prefs.preview(key, v)` кладёт значение в `previewMap`; свойства Prefs отдают
   preview ?? значение ?? дефолт → бар меняется мгновенно (ползунки альфы/радиуса). Превью — только для того,
   что бар может показать сам (альфы, радиусы, размер шрифта); акцент превью не нужен — применение ~0.2 с.
3. **Фиксация.** `Prefs.commit(key)` (отпускание ползунка, выбор в списке) → `SettingsCli.set({k: v})`.
   Очередь: один процесс за раз; пока идёт — новые значения склеиваются (последнее значение ключа побеждает),
   ползунки дополнительно дебаунсятся 300 мс.
4. **Результат.** JSON разбирается: ошибки → строка ошибки в карточке + тост `Toaster.show(…, "error")`,
   превью снимается (откат визуально); `restart` → чипы «нужен перезапуск» и общий баннер; после успеха —
   снекбар «Применено · Отменить» (5 с) → `zephyrine-settings undo`.
5. **Обратная связь через файл.** CLI переписал `settings.json` → FileView перечитал → `values` обновились →
   превью для этого ключа снимается. Prefs никогда не пишет файл сам — петли записи невозможны.
6. Если шелл не запущен — CLI работает сам по себе (скрипты, тесты, будущий `deploy.sh`).

Проверить при реализации: FileView `watchChanges` переживает атомарную замену файла (rename). Если нет —
CLI пишет `settings.json`/`scheme.override.json` на месте (truncate+write), а Prefs/Colors переживают
кратковременно битый JSON (уже так: держат последнее валидное).

### 2.6 Config.qml / Colors.qml — настраиваемые, не ломая бар

- **Colors.qml.** Второй `FileView` на `scheme.override.json`; `pick(key, def)` сначала смотрит в override,
  затем в scheme, затем дефолт. Нет файла / пустые `colours` → поведение байт-в-байт как сейчас. Имена
  свойств не меняются (помнить ловушку `onSurface` → `fg`).
- **Config.qml.** Только эти свойства становятся связанными (остаются `readonly`, тип и имя те же; при сбое
  Prefs — ровно текущие значения):

  | Свойство Config | Было | Станет | Этап |
  |---|---|---|---|
  | `barAlpha` | 0.88 | `Prefs.glassAlpha` | v1 |
  | `pillAlpha` | 0.94 | `Prefs.surfaceAlpha` | v1 |
  | `pillRadius` | 12 | `Prefs.radius` | v1 |
  | `barRadius`, `popoutRadius` | 14 | `Prefs.radius + 2` | v1 |
  | `fontFamily` | JetBrainsMono Nerd Font | `Prefs.shellFont` (только семейства «… Nerd Font») | v1.1 |
  | `fontSize` / `iconSize` | 13 / 16 | `Prefs.shellFontSize` / `+3` | v1.1 |
  | `volumeMax`, `volumeStep` | 1.0 / 0.05 | `Prefs.…` | 3 |
  | `batteryCritical` | 0.15 | `Prefs.…` | 3 |
  | `toastDefaultMs`, `notifMax`, `dndAllowCritical` | 5000 / 50 / true | `Prefs.…` | 4 |

  Новые: `zephyrineRoot`, `settingsCli` (путь к `settings/bin/zephyrine-settings`). Жёстко заданные в
  компонентах радиусы (PopItem 8, PopField/Tip 10) и плотности карточек (0.94/0.96) **не** параметризуем —
  это осознанная читаемость попапов над видео.
- **Prefs не импортирует Config** (иначе цикл Config → Prefs → Config); лежит в корне, импортирует только
  QtQuick/Quickshell/Quickshell.Io. Имя `Prefs`, не `Settings` (конфликт с `QtCore.Settings`) и не `State`.
- Новые QML-файлы live-reload подхватывает ненадёжно → после внедрения пользователь перезапускает шелл
  (`kill <pid qs>; setsid qs -p ~/.config/quickshell/zephyrine`), либо `touch shell.qml`.

### 2.7 Как открывается

- `services/Overlays.qml`: `property bool settingsOpen`, `property string settingsSection: "appearance"`,
  `openSettings(section)`, `closeSettings()`, `toggleSettings()`; `IpcHandler { target: "settings" }` с
  функциями `open(): void`, `openAt(section: string): void`, `toggle(): void`, `close(): void`.
  Открытие настроек НЕ закрывает лаунчер/меню питания и не зависит от правила «один оверлей».
- Секции (`openAt`): `appearance`, `network`, `devices`, `system`; подразделы через `/`:
  `appearance/wallpaper`, `network/wifi`, `network/bluetooth`, `devices/audio`, `devices/display`,
  `devices/power`, `system/keyboard`, `system/binds`, `system/apps`, `system/autostart`,
  `system/notifications`, `system/about` — окно прокручивает к карточке.
- Бинд: `SUPER + I` (свободен; конвенция Windows/GNOME) → `qs … ipc call settings toggle` — в `hyprland.lua`
  (не в settings.lua: должен работать, даже если сгенерированный файл сломан).
- Меню питания: 6-я кнопка «Настройки» (`Config.icons.settings`, клавиша `I`, рус. `ш`, не danger).
- Глубокие ссылки из попапов: Wi-Fi — «Настройки сети…» на месте скрытой сейчас кнопки «Подробнее»
  (`nm-connection-editor` не установлен), Bluetooth/Звук/Батарея — «Настройки…» → `openAt(...)`.
- Вариант (не по умолчанию): отдельная пилюля-шестерёнка слева от кнопки питания.

### 2.8 Тип окна: варианты

| | FloatingWindow (рекомендую) | PanelWindow, слой Overlay (как лаунчер) |
|---|---|---|
| Клавиатура | обычный фокус окна, другие окна доступны | `Exclusive`/`OnDemand` — модально, блокирует остальное |
| Перемещение/размер | да (Hyprland), правило задаёт стартовый размер | нет, фиксированная карточка |
| Стекло | hyprglass как у всех окон | своя альфа, hyprglass на слои не включён |
| Риски | класс/app-id окна Quickshell надо уточнить (`hyprctl clients -j` после первого открытия); закрытие окна компоситором (SUPER+C) должно сбрасывать `settingsOpen` | меньше неизвестных, но неудобно для долгой работы и проверки темы «рядом» с kitty |

Правило окна (в `hyprland.lua`, поля проверить по факту): `match = { title = "^Zephyrine · Настройки$" }`,
`float = true`, `size = "1040 700"`, `center = true`. Минимальный размер окна 860×560.

---------------------------------------------------------------------------------------------------

## 3. Генератор тем (раздел «Внешний вид»)

### 3.1 Источники

- `quickshell/scheme.json` — база палитры (формат Caelestia: `colours.<имя>` = hex без `#`). Дополняется
  ext-ключами (§3.4) в том же объекте `colours` (Colors.qml их просто не использует; `pick()` фильтрует не-hex).
- `settings/settings.json` + `settings/schema.json` — параметры: акцент, альфы, радиусы, шрифты, обои, рамки.
- `settings/palette-roles.json` — какие ключи палитры производны от каких «баз» и как (§3.5).
- Старый `theme/obsidian-neon-scheme.json` — legacy (другие нейтрали/outline), генератором НЕ используется.

### 3.2 Виды целей и манифест

| Вид | Что делает | Пример |
|---|---|---|
| `template` | рендер всего файла из `templates/…tmpl` | gtk.css, zed, kitty/zephyrine.conf |
| `patch` | замена строк по регэкспу в ручном файле, остальное не трогается | `kitty.conf` font_*, `settings.ini` gtk-font-name, `qt6ct.conf` [Fonts] |
| `data` | дамп данных | `scheme.override.json` |
| `emit` | файл целиком строится кодом (без golden) | `.config/hypr/settings.lua` |
| `command` | только рантайм-команда, без файла | `gsettings set …`, перезапуск mpvpaper |

`targets.json` (на цель): `id`, `kind`, `template`, `output` (путь в репо), `deploy` (`none` | `copy:<путь>` |
`obsidian-vaults` | `zen-profile` | `tb-profile` | `tb-xpi`), `reload` (`none` | `hypr-reload` | `kitty-usr1` |
`hypridle-restart` | `mpvpaper-restart` | `gsettings`), `restart` (текст для UI), `detect` (`command -v X`,
наличие профиля/реестра), `keys` (какие ключи настроек влияют — для выбора целей при `set`).

Цели v1/v1.1 (всё сейчас совпадает с репо, §1.2):

| id | вид | выход в репо | живая копия / деплой | применение | что нужно приложению |
|---|---|---|---|---|---|
| quickshell | data | `quickshell/scheme.override.json` | симлинк | FileView | вживую |
| hypr | emit | `.config/hypr/settings.lua` | симлинк | `hyprctl reload config-only` | вживую |
| gtk3, gtk4 | template | `.config/gtk-{3,4}.0/gtk.css` | копия в `~/.config/gtk-*/` | copy | новые окна; открытые GTK — перезапуск (трюк «gsettings gtk-theme туда-обратно» — проверить, может мигнуть) |
| qt6ct | template | `.config/qt6ct/colors/zephyrine.conf` | копия | copy | проверить, следит ли qt6ct за файлом; иначе перезапуск Qt-приложений |
| zed | template | `.config/zed/themes/zephyrine.json` | симлинк | — | Zed следит за `themes/` (проверить) |
| kitty | template | `.config/kitty/zephyrine.conf` | симлинк | `pkill -USR1 -x kitty` | вживую (kitty перечитывает конфиг по SIGUSR1) |
| zathura | template | `.config/zathura/zathurarc` | симлинк на файл | — | перезапуск или `:source` |
| obsidian | template | `obsidian/Zephyrine/theme.css` | копии в `<vault>/.obsidian/themes/Zephyrine/` (vault'ы из `~/.config/obsidian/obsidian.json`, сейчас 3, все на `/mnt/data`) | copy | проверить live; иначе Ctrl+R |
| tb-css | template | `thunderbird/userChrome.css` | `<профиль TB>/chrome/userChrome.css` | copy | полный перезапуск |
| tb-theme | template | `thunderbird/zephyrine-theme/manifest.json` | zip → `<профиль>/extensions/zephyrine-theme@zephyrine.xpi` | zip | полный перезапуск; проверить, нужен ли рост `version` (если да — `1.0.N`, N в `generated.json`; golden идёт с N=0 → `"1.0"`) |
| zen-chrome, zen-content | template | `zen/userChrome.css`, `zen/userContent.css` | `<профиль Zen>/chrome/` | copy | полный перезапуск |
| fonts-* (v1.1) | patch + command | `settings.ini` ×2, `qt6ct.conf`, `kitty.conf` | копии/симлинк; для `qt6ct.conf` в живой копии повторить подстановку `color_scheme_path` как `deploy.sh` | copy, gsettings, usr1 | GTK4 — вживую через gsettings; GTK3/Qt — перезапуск |
| wallpaper (v1.1) | command | — | симлинки в состоянии | `mpvpaper-restart` | вживую (только экземпляр рабочего стола) |
| hypridle (этап 3) | template + блоки | `.config/hypr/hypridle.conf` | симлинк | `hypridle-restart` | вживую |
| hyprlock (опц.) | template | `.config/hypr/hyprlock.conf` | симлинк | — | со следующей блокировки |
| SDDM | — | — | нужен root (`sddm/install-theme.sh`) | — | только подсказка с командой в UI |

Профили ищутся так же, как в `deploy.sh` (`installs.ini` → `Default=`, `obsidian.json` → `vaults`). Логику
дублировать не надо навсегда: позже `deploy.sh` вызывает `zephyrine-settings apply --targets …` (побочная
задача Z1). Нет приложения/профиля/смонтированного `/mnt/data` → цель `skipped` с причиной, не ошибка.

### 3.3 Шаблонизатор

Синтаксис только подстановки: `{{ путь }}` и `{{ путь | фильтр | фильтр:аргумент }}`. Никаких циклов и
условий — там, где нужна структура (hypridle-листенеры, settings.lua), Python готовит готовые блоки-строки
(`{{ idle.dimBlock }}`) или файл строится эмиттером.

Пространства имён контекста: `c.<ключ>` — цвет эффективной палитры; `s.<ключ>` — строковые производные
(`s.primaryHsl`); `a.glass`, `a.surface` — альфы; `r.lg|md|sm|xs` — радиусы; `f.shell|ui|mono.family|size`;
`hypr.*`; `idle.*`; `meta.*` (версия xpi).

Фильтры (вывод должен совпадать с текущим написанием байт-в-байт):

| Фильтр | Вывод | Где нужен |
|---|---|---|
| `hex` | `#bb9af7` | CSS, kitty, zathura, манифесты |
| `bare` | `bb9af7` | scheme-подобные |
| `hexa:AA` | `#bb9af7AA` (AA — литерал 2 hex или `a.*` через `hexbyte`) | Zed |
| `argb:AA` | `#AAbb9af7` | qt6ct |
| `rgb` | `187, 154, 247` | Obsidian `--zp-*: r, g, b;` |
| `rgba:A` | `rgba(187, 154, 247, 0.28)` | GTK, CSS |
| `hyprrgba:AA` | `rgba(bb9af7ee)` | Hyprland |
| `anchor:L` (для `a.*`, `r.*`) | при дефолтной базе — **литерал L как записан** (`"0.72"`); иначе `L + (база − дефолт)`, обрезка [0,1] для альф / [0,∞) для радиусов, столько же знаков после точки | GTK view 0.72 / headerbar 0.92 от glass 0.88; Zed `dd` |
| `hexbyte` | `dd` из альфы (round(a·255)) | Zed, qt6ct |
| `num:N` | число с N знаками (`11.0`) | kitty `font_size` |
| `px` | `12px` | CSS |
| `lua_str`, `json_str`, `css_str` | экранирование строки | шрифты, пути |

Строгость: неизвестный путь/фильтр → ошибка рендера; в выводе не должно остаться `{{`; шаблоны не содержат
«сырых» `#rrggbb`/`rgba(` вне плейсхолдеров, кроме белого списка намеренных констант (`#000000`-тени,
`transparent`) — это проверяет `test lint`.

Варианты движка:

| | Свой мини-движок (рекомендую) | jinja2 |
|---|---|---|
| Зависимости | только stdlib | `python-jinja` (сейчас стоит явно, но не как зависимость чего-то нашего; в `install_script.sh` нет) |
| Байт-точность | полный контроль (нет trim/whitespace-магии) | нужны `keep_trailing_newline`, `StrictUndefined`, аккуратность с пробелами |
| Логика в шаблонах | нет (и не нужна — выносим в Python) | есть; соблазн размазать логику по шаблонам |
| Объём | ~150 строк + тесты | 0 строк движка, но обвязка фильтров та же |

### 3.4 Палитра: роли и ext-ключи

Главное правило шаблонов: **один и тот же hex в разных местах может играть разные роли**, и в шаблон
подставляется роль, а не «ключ, у которого такое же значение». Пример: `#bb9af7` в kitty — это и `cursor`
(акцент → `c.primary`), и `color5` (ANSI magenta → `c.purple`, НЕ меняется при смене акцента).

Классификация: элементы интерфейса (фокус, выделение, активная вкладка, CTA-кнопки, курсор, рамки фокуса)
→ семантические ключи (`primary*`, `secondary*`, `error*`, `success*`, `warning*`, `surface*`, `outline*`,
`fg`); подсветка синтаксиса, ANSI-цвета терминала, «радуга» заголовков Obsidian, граф → «оттенки»
(`purple`, `blue`, … — постоянные). Нейтрали (фоны, контейнеры, outline) в v1 не переопределяются,
поэтому их роль на результат пока не влияет, но размечать всё равно по смыслу.

Стартовый словарь ext-ключей (добавляются в `scheme.json → colours`; имена может уточнить исполнитель
задачи S1.1, принцип — нет). «Якорь» — от какой базы цвет производится при переопределении (§3.5);
«—» — константа.

| Ключ | hex | якорь | где сейчас |
|---|---|---|---|
| `primaryLight` | cdb2f9 | primary | gtk `accent_color`; obsidian `--interactive-accent-hover`, `--color-accent-2`; zen hover кнопок; userContent |
| `primaryLighter` | d2baf9 | primary | obsidian `--text-accent-hover`, `--italic-color` |
| `secondaryLight` | a9c1fa | secondary | obsidian `--link-color-hover`; zen userContent `link-color-hover` |
| `focusBorder` | 3a5a9a | secondary | zed `border.focused`, `panel/pane.focused_border` |
| `successLight` | b5dc8a | success | gtk `success_color` |
| `successDeep` | 4a7a2a | success | zed `version_control.word_added` |
| `errorLight` | ff9aab | error | gtk `destructive_color`, `error_color` |
| `onErrorStrong` | 2a0a10 | error | zathura `notification-error-fg` |
| `warning` | e0af68 | — (база, в v1 не меняется) | gtk `warning_bg_color`; zathura; obsidian `--zp-warning`; zed warning/modified/conflict |
| `warningLight` | f0c98a | warning | gtk `warning_color` |
| `onWarning` | 2a1d08 | warning | gtk `warning_fg_color` |
| `warningContainer` | 4a3a1f | warning | zed `conflict/modified/warning.border` |
| `purple`, `purpleBright`, `purpleDim` | bb9af7, d2baf9, 7c4fa8 | — | kitty 5/13; zed ANSI magenta, keyword, preproc; obsidian `--color-purple`, `--code-keyword`, h1 |
| `blue`, `blueBright`, `blueDim` | 7aa2f7, a9c1fa, 5b82c8 | — | kitty 4/12; zed ANSI/функции; obsidian `--code-function`, h2 |
| `cyan`, `cyanBright`, `cyanDim` | 2ac3de, 6fe3f0, 1f8fa3 | — | kitty 6/14; zed ANSI, types; obsidian h3 |
| `green`, `greenBright`, `greenDim` | 9ece6a, b5dc8a, 6a9145 | — | kitty 2/10; zed ANSI, strings |
| `yellow`, `yellowBright`, `yellowDim` | e0af68, f0c98a, b08a4a | — | kitty 3/11; zed ANSI, constants |
| `red`, `redBright`, `redDim`, `redAlt`, `redDeep` | f7768e, ff9aab, b8566a, d9506a, c25068 | — | kitty 1/9; zed ANSI, players[1], `punctuation.special` |
| `orange`, `pink`, `sky` | ff9e64, f5a3d4, 89ddff | — | zed numbers/booleans; obsidian `--color-orange/pink`, `--code-operator` |
| `neutral40`, `neutral45`, `neutral60` | 5b6190, 6b7199, a0a6c8 | — | obsidian `--color-base-40/60`, `--code-comment`; zed comment, bright_black, dim_white |
| `white` | ffffff | — | qt6ct BrightText |

Плюс строковая производная в `palette-roles.json`: `primaryHsl` = литерал `"267, 85%, 78%"`, якорь primary,
режим `hsl-string` (при смене акцента считается честно). Цвета рамок Hyprland (33ccff/00ff99/595959,
тень 1a1a1a) — не палитра, а настройки `hypr.borders.*` (§5).

### 3.5 Производные значения: «якорная» деривация

Для каждого производного ключа K с якорем B (из `palette-roles.json`):

- **Short-circuit:** если эффективное значение B равно базовому из `scheme.json` → K = литерал из
  `scheme.json` (без вычислений — поэтому golden всегда точный, никакой плавающей точки).
- Иначе в OKLCH: `L' = L_newB + (L_K − L_B)`, `C' = C_K · (C_newB / C_B)` (если `C_B≈0` → `C_K`),
  `H' = H_newB + (H_K − H_B)`; затем возврат в sRGB с уменьшением хромы до попадания в гамут
  (бинарный поиск), округление компонент half-up. Режим `hsl-string` — HSL нового значения, целые.
- Якорь у ключей семейства primary в самом `scheme.json`: `onPrimary`, `primaryContainer`,
  `onPrimaryContainer`, `inversePrimary`, `primaryFixed`, `primaryFixedDim`, `onPrimaryFixed`,
  `onPrimaryFixedVariant`, `surfaceTint`, `primary_paletteKeyColor` (часть из них равна primary — дельта 0,
  станут новым акцентом).
- Альфы и радиусы — тот же принцип в фильтре `anchor:L` (§3.3).
- `scheme.override.json` = только ключи, у которых эффективное значение ≠ базового (по умолчанию пусто).

Валидация акцента: контраст `primary` к `background` ≥ 3:1 и `onPrimary` к `primary` ≥ 4.5:1 (WCAG); если
`onPrimary` после деривации не проходит — переключаем на тёмный/светлый вариант (L≈0.25 / L≈0.95 той же
хромы/оттенка), UI показывает значение контраста. Тема тёмная: акценты с OKLCH L < 0.55 отклоняются с
понятной ошибкой.

### 3.6 Как не сломать существующий вид

1. **Golden-тест** (`zephyrine-settings test golden`): рендер всех целей при `settings.json = {}` и текущем
   `scheme.json` → побайтное сравнение с файлами в репо И с живыми копиями (включая manifest внутри xpi).
   Ноль различий — условие приёмки каждого шаблона и всего v1.
2. **Тест возмущений** (`test perturb KEY`): база KEY := заметное значение-маркер (например, primary
   `#ff00ff`, glass 0.5, radius 20) → список изменившихся строк по файлам; сравнивается с одобренным снимком
   `tests/snapshots/perturb/<KEY>.txt`. Так ловятся неверные роли (ANSI magenta, поменявшая цвет вместе с
   акцентом). Снимки один раз ревьюит человек/агент и коммитит; дальше — регрессионный тест.
3. **Lint шаблонов** (`test lint`): нет сырых цветов вне плейсхолдеров (кроме белого списка), нет `{{` в
   выводе, все ext-ключи из `scheme.json` где-то используются (или помечены как запас).
4. **Drift-защита:** после записи CLI хранит sha256 вывода в `generated.json`. Перед следующей записью: если
   текущий файл ≠ последнему сгенерированному — его правили руками → цель получает статус `drift`, запись
   отменяется (код 4), UI предлагает «Показать различия» (`kitty -e sh -c 'diff -u … | less'`), «Перезаписать»
   (двойное нажатие, как в меню питания) или «Не управлять этой целью».
5. **Приём во владение (adoption):** первая запись в цель разрешена только если golden для неё = 0 различий.
6. Маркер «сгенерировано, не править» в текстовых выходах (CSS/conf/Lua) — отдельным одобренным шагом ПОСЛЕ
   прохождения golden (меняет файлы на одну строку комментария; снимок golden обновляется осознанно). В JSON
   маркер не добавляем.
7. После внедрения правки цветов/радиусов в эти 11 файлов делаются в шаблонах, а не в выходах (иначе drift).

### 3.7 Что безопасно параметризовать

| Параметр | Диапазон / значения | Цели | Риск и ограничение |
|---|---|---|---|
| Акцент `appearance.accent` | `null` (из палитры) или `#rrggbb`; пресеты: purple bb9af7, blue 7aa2f7, cyan 2ac3de, green 9ece6a, yellow e0af68, orange ff9e64, red f7768e, pink f5a3d4 | все | контраст (§3.5); ANSI/синтаксис не меняются |
| Альфа стекла `appearance.glassAlpha` | 0.50–1.00, шаг 0.01 (деф. 0.88) | бар, GTK, Obsidian, TB, Zen, Zed (через `anchor`) | ниже 0.5 текст над видео нечитаем — нижняя граница жёсткая |
| Плотность элементов `appearance.surfaceAlpha` | 0.70–1.00 (0.94) | пилюли, GTK container, Obsidian, TB | — |
| Скругление `appearance.radius` | 0–20 (12): `lg=r+2`, `md=r`, `sm=max(0,r−2)`, `xs=max(0,r−4)` | бар, GTK, Obsidian, TB, Zen | `999px`-пилюли остаются литералами |
| Скругление окон `appearance.windowRounding` | 0–20 (10) | Hyprland `decoration.rounding` | — |
| Рамки окон `hypr.borders.style` | `legacy` (текущий градиент 33ccffee→00ff99ee, 45°; неактивная 595959aa) / `accent` (primary→secondary, `ee`; неактивная outlineVariant `aa`) / `custom` | Hyprland | по умолчанию `legacy` — вид не меняется |
| Толщина рамки | 0–4 (2) | Hyprland | — |
| Шрифт шелла (v1.1) | только семейства с «Nerd Font» из `fc-list` (иначе пропадут иконки бара), 10–16 | бар, hyprlock (опц.) | иконки рисуются тем же `Txt` |
| Шрифт интерфейса (v1.1) | любое семейство из `fc-list`, 8–14 | GTK `settings.ini`, gsettings, qt6ct general | GTK3/Qt — перезапуск |
| Моноширинный шрифт (v1.1) | `fc-list :spacing=mono` (63 семейства), 8–16 | kitty, zathura, qt6ct fixed, Obsidian, gsettings monospace | — |
| Обои (v1.1) | существующий видеофайл из `wallpapers/`, `wallpapers-candidates/**` или выбранный вручную | mpvpaper (рабочий стол), lock-with-video.sh; SDDM — подсказка с sudo-командой | — |
| Прозрачность kitty (v1.1) | 0.5–1.0 (0.70) | `kitty.conf background_opacity` (patch) | — |
| Стекло hyprglass (v1.1, «дополнительно») | `glass_opacity` 0.3–1.0 (0.7), кнопка «сброс» | settings.lua | остальные параметры hyprglass настраивались с трудом (см. CONTEXT п.19) — не выносим |

**Не параметризуем в v1:** светлую тему (все шаблоны рассчитаны на тёмную), произвольные фоны/нейтрали,
отдельные цвета на приложение, синтаксис/ANSI, внутреннюю альфа-схему Zed, селекторы TB/Zen, кривые
анимаций Hyprland, выбор другой палитры целиком (v2: `settings/palettes/*.json` → «применить пресет» =
замена базы в `scheme.json` с бэкапом).

### 3.8 Применение и перезапуски

Порядок в `apply`: валидация → эффективная палитра → рендер затронутых целей → сравнение с текущим (без
изменений — ничего не пишем и не перезапускаем; идемпотентность) → drift-проверка → бэкап → запись в репо
(через realpath: **симлинк никогда не заменяется файлом**) → деплой копий → reload-действия → JSON-отчёт.
Таблица «что нужно приложению» — §3.2. UI показывает на каждой цели чип: «вживую» / «нужен перезапуск» /
«не установлено» / «профиль не найден» / «изменён вручную»; браузеры и почту сам не перезапускает (вкладки,
письма), kitty/hypridle/mpvpaper/Hyprland — сам.

### 3.9 Hyprland: settings.lua

Одноразовая правка конца `hyprland.lua` (с бэкапом; после — `hyprctl reload` и `hyprctl configerrors`):

```lua
-----------------------------
---- ZEPHYRINE SETTINGS -----
-----------------------------
-- settings.lua генерирует центр настроек (zephyrine-settings) — руками не править.
-- Ошибка в нём не ломает конфиг: показываем уведомление и живём с тем, что выше.
do
    local dir  = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
    local path = dir .. "/settings.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, path)
        if not ok then
            hl.notification.create({ text = "Zephyrine: ошибка в settings.lua: " .. tostring(err), timeout = 15000 })
        end
    end
end
```

Плюс в той же правке: бинд `SUPER + I` (§2.7) и правило окна настроек (§2.8).

Эмиттер (`hypr.py`) пишет детерминированный файл из эффективных настроек, все строки через `lua_str`:

```lua
-- СГЕНЕРИРОВАНО zephyrine-settings из settings/settings.json. Не править вручную.
hl.config({ decoration = { rounding = 10 } })
hl.config({ general = { border_size = 2, col = {
    active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
    inactive_border = "rgba(595959aa)" } } })
if hl.plugin and hl.plugin.hyprglass then hl.plugin.hyprglass.config({ glass_opacity = 0.7 }) end
-- этап 3: hl.monitor({ output = "desc:…", mode = "…", position = "…", scale = 1 })
-- этап 4: hl.config({ input = { kb_layout = "pl,ru", kb_variant = ",", kb_options = "grp:alt_shift_toggle" } })
--         hl.unbind("SUPER + Q"); hl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"), { description = "zp:terminal · Терминал" })
--         hl.on("hyprland.start", function() hl.exec_cmd("Telegram") end)
```

- Ключи, которыми владеет settings.lua: `decoration.rounding`, `general.border_size`, `general.col.*`,
  `plugin.hyprglass.glass_opacity`; с этапа 3 — правила мониторов; с этапа 4 — `input.kb_*`,
  `input.repeat_*`, переопределения биндов, управляемый автозапуск. Те же значения в `hyprland.lua` остаются
  как запасные (при значениях по умолчанию settings.lua ничего не меняет).
- Проверить при реализации: (а) частичный вызов `hyprglass.config({glass_opacity=…})` не сбрасывает
  `dark.*` (сверить `hl.get_config("plugin.hyprglass.dark.brightness")` после reload); (б) повторный
  `hl.monitor` для того же выхода в конце конфига побеждает (headless-выход); (в) `output = "desc:…"`
  работает в Lua; (г) следит ли Hyprland за файлами из `dofile` (если нет — reload всегда явный).
- Перед установкой файла: `luac -p` + `hyprctl repl 'local f,e = loadfile(p) return e or "ok"'`
  (синтаксис Lua самого Hyprland); после `reload config-only` — `hyprctl configerrors` пуст, иначе откат
  из бэкапа + повторный reload + ошибка в отчёте.

------------------------------------------------------------------------------------------------### 3.10 Светлая тема (`appearance.mode` = `dark` | `light`)

- **Палитра.** Светлая схема лежит в `palette-roles.json` → `schemes.light` (те же 97 ключей, что в `quickshell/scheme.json`); пересобирается
  `settings/tools/make_light_palette.py --write` (OKLCH: тот же оттенок, светлота и насыщенность по таблице; «Fixed»-роли — как в тёмной).
  `palette.pick_scheme` выбирает базовую схему по режиму, дальше обычная якорная деривация (§3.5) от светлого `primary`.
- **Акцент** один на обе темы. На светлой он автоматически приводится к светлоте ≤ 0.52 OKLCH (`color.light_accent`, идемпотентно), ошибка —
  только если контраст к светлому фону < 3:1; на тёмной правила прежние (светлота ≥ 0.55). Пресеты в `AccentPicker` показывают на
  светлой теме приведённые цвета (`lightHex`), а в настройки пишется исходный.
- **Quickshell** получает светлую палитру через `scheme.override.json` (в светлом режиме — почти все ключи), `Colors.qml` не менялся.
- **Шаблоны**: пространство `m` (`m.scheme` = dark|light, `m.cls`) — Obsidian (`.theme-dark, .theme-light { color-scheme: {{ m.scheme }} }`), Zed
  (`appearance`), Thunderbird (`color_scheme`). Патчи и `gsettings`: поле `map` {режим → значение} (`patch.fields`) — `gtk-application-prefer-dark-theme`,
  `gtk-theme-name` (adw-gtk3-dark ↔ adw-gtk3), иконки (Papirus-Dark ↔ Papirus) в settings.ini GTK 3/4 и qt6ct.conf, а также `color-scheme`,
  `gtk-theme`, `icon-theme` в dconf. Экран блокировки и вход (цели `hyprlock`, `sddm`) берут цвета из палитры, т.е. тоже светлые.
- **Не зависят от режима (ограничения)**: стекло окон Hyprland (`hyprglass`, его параметры в `hyprland.lua` рассчитаны на тёмную тему),
  встроенные тёмные/светлые элементы Zen и Thunderbird (user.js ставит тёмную встроенную тему), базовая схема Obsidian (наш CSS подключён к
  обеим), обои и видео-фон входа/блокировки (поверх них затемнение берётся из `background` — на светлой теме оно светлое).
- **Тесты**: `tests/test_light_theme.py` — одинаковые ключи, контраст WCAG по ролям (в т.ч. для всех пресетов акцента), рендер всех шаблонов,
  `m.*`, `map` в патчах; тёмные golden не менялись (кроме строки селектора Obsidian).
- **Drift при смене режима.** Смена `appearance.mode` перекрашивает все цели, поэтому `set appearance.mode=…` применяется с `force`: незнакомые
  файлы (в т.ч. руками правленные копии GTK/профилей) перезаписываются, прежнее содержимое — в бэкапе (`undo`/«Отменить»). Остальные настройки
  по-прежнему сообщают drift. Дополнительно принимаются без drift файлы с шапкой «СГЕНЕРИРОВАНО zephyrine-settings» и вывод в противоположном режиме.
- Zen: подписи вкладок задаются явно (`.tab-label { color: var(--zp-fg) }`), `color-scheme: {{ m.scheme }}` на корне; встроенная тема браузера
  (user.js: compact-dark) от режима не зависит.
- Автопереключение по времени (`auto`) — не реализовано (идея).

### 3.11 Курсор мыши и иконки

Вкладка «Курсор и иконки» страницы «Внешний вид» (`parts/ThemesCard.qml`, плитки — `parts/ThemeGrid.qml`).

| Ключ | Значение | Куда применяется |
|---|---|---|
| `appearance.icons.theme` | string, nullable, `null` = по режиму темы (Papirus-Dark / Papirus) | `gtk-icon-theme-name` (settings.ini GTK 3/4), `icon_theme` (qt6ct.conf), gsettings `icon-theme` |
| `appearance.cursor.theme` | string, дефолт `Qogir` | `gtk-cursor-theme-name`, gsettings `cursor-theme`, `hl.env` XCURSOR_THEME/HYPRCURSOR_THEME (settings.lua), `hyprctl setcursor` |
| `appearance.cursor.size` | integer 16–64 (шаг 4), дефолт 24 | `gtk-cursor-theme-size`, gsettings `cursor-size`, XCURSOR_SIZE/HYPRCURSOR_SIZE, `hyprctl setcursor` |

- **Список тем** — `zephyrine-settings themes --kind icons|cursors [--no-thumbs]` (`zsettings/themes.py`): каталоги по Icon Theme Spec
  (`~/.icons`, `$XDG_DATA_HOME/icons`, `$XDG_DATA_DIRS/*/icons`; для тестов `ZEPHYRINE_ICON_DIRS` заменяет весь поиск). Иконки — каталог с
  `index.theme` и `Directories` (без `Hidden=true`, `hicolor` исключён), курсор — каталог с подкаталогом `cursors/`. Имя темы = имя каталога.
  Образцы: у иконок до 5 файлов (папка, терминал, браузер, настройки, текст; ищутся в `Directories`, самый крупный размер первым, без
  `Inherits`), у курсоров — PNG кадров `left_ptr`/`pointer`/`text`: Xcursor разбирается в самом модуле (ближайший к 32 px кадр, снятие
  предумножения альфы, PNG через `zlib`), кэш `<state>/cache/cursor-thumbs/`.
- **Проверка при `set`**: тема должна быть установлена (`themes.check_values`; только для изменяемых ключей и значений не по умолчанию — reset/undo
  всегда допустимы; если тем такого вида нет вовсе — проверять нечем). Имя ограничено шаблоном `^[A-Za-z0-9][A-Za-z0-9._+ -]{0,63}$`
  (оно попадает в ini/gsettings/Lua).
- **`null` у иконок.** Поле `fallback` patch-правки/gsettings-команды (`patch.fields`): если `from` пуст, значение берётся из `map` по `fallback.from`
  (`appearance.mode`). Явно выбранная тема иконок режимом не меняется; «По режиму темы» (reset) возвращает прежнее поведение.
- **Цель `cursor`** (`zsettings/cursor.py`, kind=command): `hyprctl setcursor <тема> <размер>` вживую; вызывается только при смене (подпись в
  generated.json; без записи и при дефолтах — ничего), вне Hyprland (нет `HYPRLAND_INSTANCE_SIGNATURE`) пропускается как `hyprland-not-running`.
  Переменные окружения для следующего входа пишет цель `hypr` (блок «Курсор мыши» в settings.lua — только при отличии от Qogir/24, при дефолтах
  `settings.lua` не меняется).
- **Что подхватывается сразу**: курсор Hyprland и новые окна GTK 4 (gsettings), иконки GTK 4. GTK 3 и Qt — после перезапуска приложений; Qt и
  XWayland читают `XCURSOR_*` из окружения при запуске, поэтому для них — перезапуск приложения/следующий вход.
- **`hyprland.lua` и dconf.** Раньше `hyprland.start` каждый раз ставил `gtk-theme`/`icon-theme` через `gsettings set` на Papirus-Dark, что затирало бы
  выбранные иконки (и светлую тему); теперь там `zephyrine-settings apply --targets gsettings` (с прежними командами как запасным вариантом).
- Тесты: `tests/test_themes.py` (сканер, Xcursor→PNG, схема, `fallback`, эмиттер, patch-цели, gsettings, `cursor`, CLI `themes`).

---

## 4. Бэкенды по разделам

Колонка «проверено» — результат команд 2026-10-02 на этой машине.

### 4.1 Внешний вид

| Функция | Механизм | Проверено | Нет / риски |
|---|---|---|---|
| Палитра бара | `scheme.json` + `scheme.override.json` → Colors.qml (FileView) | Colors.qml уже перечитывает файл на лету | проверить watch при rename |
| Темы приложений | CLI (§3) | все живые копии = репо | — |
| Hyprland рамки/скругления/стекло | settings.lua + `hyprctl reload config-only` | `hl.get_config` читает значения, `configerrors` есть | — |
| Шрифты | `fc-list : family`, `fc-list :spacing=mono family`; gsettings `font-name`/`monospace-font-name` | JetBrainsMono Nerd Font, Inter есть; портал Settings=gtk | GTK3/Qt вживую не обновятся |
| Обои | симлинки `~/.local/state/zephyrine/wallpaper-{desktop,lock}`; mpvpaper-автозапуск в `hyprland.lua` и `VIDEO=` в `scripts/lock-with-video.sh` смотрят на симлинк с фолбэком на текущее видео; смена = перенаправить симлинк + убить ТОЛЬКО mpvpaper рабочего стола (без `-l overlay`/`input-ipc-server`) и запустить заново; превью — `ffmpeg -ss 2 -frames:v 1 -vf scale=320:-1` | mpvpaper, ffmpeg есть; путь сейчас захардкожен в 3 местах (hyprland.lua, lock-with-video.sh, sddm/install-theme.sh) | SDDM — только root; NVIDIA держит mpvpaper (известно, не трогаем) |
| Цвет с экрана (опц.) | `hyprpicker -f hex` | установлен | GUI-процесс: запускает шелл, не sandbox |

### 4.2 Сеть и Bluetooth

| Функция | Механизм | Проверено | Нет / риски |
|---|---|---|---|
| Wi-Fi: радио, список, подключение, скрытая сеть, пароль | существующий `services/Wifi.qml` (nmcli, пароль только через stdin) — переиспользуем целиком | работает в попапе | `nm-connection-editor` НЕТ → кнопку «Подробнее» заменяет центр настроек |
| Детали подключения | `nmcli -t -g IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,GENERAL.HWADDR device show <dev>` (LC_ALL=C) | nmcli есть | — |
| Сохранённые сети | `nmcli -t -f NAME,UUID,TYPE,AUTOCONNECT connection show`; забыть — `nmcli connection delete uuid <U>`; автоподключение — `nmcli connection modify uuid <U> connection.autoconnect yes|no` | — | разрушительные операции — с подтверждением (§7) |
| Ethernet | `nmcli device status` (уже в Net.qml) | — | — |
| Режим «в самолёте» (опц.) | `nmcli radio all off` + `adapter.enabled = false` | — | с подтверждением |
| Bluetooth: адаптер, видимость, устройства, connect/disconnect/forget/trust | `Quickshell.Bluetooth`: `BluetoothAdapter{enabled, discoverable, discovering, pairable}`, `BluetoothDevice{connect(), disconnect(), pair(), cancelPair(), forget(), trusted, blocked, battery}` | адаптер `zephyrka` включён; API модуля сверено по qmltypes | — |
| Сопряжение с PIN/подтверждением | своего агента BlueZ в сессии нет (bluedevil удалён с KDE); помощник `settings/zsettings/btagent.py` (python3-dbus + gi есть): регистрирует `org.bluez.Agent1`, по stdio JSON-строки `{"type":"confirm","device":…,"passkey":123456}` ↔ ответы UI | `import dbus`, `import gi` — ок | РЕАЛИЗОВАНО (N3): dbus-python + GLib, события `pair_request`/`pair_update`/`pair_end`, ответы `{action:confirm|reject|passkey|pin}` — см. шапку `btagent.py`; UI — `parts/BtAgent.qml`, `parts/BtPairCard.qml`. Без агента работают устройства «Just Works» |

### 4.3 Звук, экран, питание

| Функция | Механизм | Проверено | Нет / риски |
|---|---|---|---|
| Выход/вход по умолчанию, громкость, mute | `Quickshell.Services.Pipewire` (`defaultAudioSink/Source`, `preferredDefaultAudioSink`, `PwObjectTracker`) — как в AudioPopout | PipeWire 1.6.9, sink/source Ryzen HD Audio | — |
| Громкость приложений | `Pipewire.nodes` с `isStream` | — | — |
| Профили карт (опц.) | `pactl list cards` / `pactl set-card-profile` | pactl есть | вне v-плана, кнопка «pavucontrol» (установлен) |
| Макс. громкость / шаг | `Config.volumeMax/volumeStep` → Prefs | — | — |
| Мониторы: чтение | `hyprctl monitors all -j` (режимы, описание, позиция, масштаб, transform) | только eDP-1 сейчас | — |
| Мониторы: применение | runtime `hyprctl eval` с `hl.monitor(spec)` + сторож отката в компоситоре (§7.2); персистентно — settings.lua | Lua-API есть; headless-выход создаётся | проверить, что runtime `hl.monitor` применяется сразу (иначе `hyprctl keyword monitor …`, команда в hyprctl есть) |
| Яркость | `brightnessctl -e4 -n2 set N%` (те же флаги, что в биндах), чтение sysfs `amdgpu_bl1` (max 65535) как в Osd.qml | brightnessctl, sysfs есть | OSD всплывёт при движении ползунка — допустимо |
| Яркость внешнего монитора (опц.) | `ddcutil` | установлен | права i2c не проверены |
| Профиль питания | `Quickshell.Services.UPower` → `PowerProfiles.profile` / `PowerProfile.*`, `degradationReason` | power-profiles-daemon 0.30 активен: performance / balanced / power-saver (сейчас performance) | — |
| Батарея | `UPower.displayDevice` (как BatteryPopout) | — | — |
| Таймауты простоя | `hypridle.conf` из шаблона (затемнение / блокировка / dpms / suspend, каждый можно выключить) + перезапуск hypridle | hypridle запущен из hyprland.lua | **сейчас dpms по таймауту не работает** (старый синтаксис) и затемнение = `brightnessctl -s set 10` — сырое 10 из 65535 (≈0%), не 10% — §10 |

### 4.4 Система и приложения

| Функция | Механизм | Проверено | Нет / риски |
|---|---|---|---|
| Раскладки | список из `/usr/share/X11/xkb/rules/base.lst` (`! layout`, `! variant`, `! option` — `grp:*` 45 шт.); применение — `input.kb_layout/kb_variant/kb_options` в settings.lua + `reload config-only`; проверка — `hyprctl devices -j` | 99 раскладок; сейчас `pl,ru`, `grp:alt_shift_toggle` | неверная раскладка → валидация до записи |
| Повтор клавиш | `input.repeat_rate/repeat_delay` (25/600) | значения прочитаны | — |
| Сочетания клавиш: список | `hyprctl binds -j` (modmask, key, description, release, locked…) | 61 бинд | у Lua-биндов не видно команды — только `description` (сейчас пустые) |
| Сочетания: переопределение | каталог «действий Zephyrine» (терминал, файлы, лаунчер, меню питания, уведомления, настройки, блокировка, скриншоты, торренты…); этап 4 начинается с одноразовой правки `hyprland.lua`: `description = "zp:<id> · <подпись>"` у этих биндов; settings.lua делает `hl.unbind(old)` + `hl.bind(new, …, {description})`; конфликт — проверка по `hyprctl binds -j` (modmask+key) | `hl.unbind`, `description` есть в API | формат строки `hl.unbind` проверить |
| Захват комбинации | на время ввода: `hyprctl dispatch 'hl.dsp.submap("zp_capture")'` (submap без биндов, кроме Escape → reset) — иначе Hyprland перехватит SUPER+… раньше окна; сторож `hl.timer` 15 с сбрасывает submap, если окно упало | `hl.define_submap`, `hl.dsp.submap` есть | — |
| Тачпад и указатель (Y7) | ключи `input.touchpad.{naturalScroll,tapToClick,tapAndDrag,disableWhileTyping,clickfinger,middleButtonEmulation,scrollFactor}` и `input.sensitivity` → `hl.config({ input = { sensitivity, touchpad = { natural_scroll, tap_to_click, tap_and_drag, disable_while_typing, clickfinger_behavior, middle_button_emulation, scroll_factor } } })` в settings.lua; блок пишется только при отличии от дефолтов (дефолты = текущий `hyprland.lua`/Hyprland) | дефолты сверены с `hyprland.lua` (`touchpad = {…}`) | имена опций Lua (`tap_to_click`) сверить на живой системе: `hyprctl configerrors` пуст; `sensitivity` общий для всех указателей |
| Приложения по умолчанию | список кандидатов — `gio mime <type>` (Registered/Recommended); запись — `gio mime <type> <app>.desktop` по всем типам категории; браузер — `xdg-settings set default-web-browser`; категории в schema.json (браузер, почта, файлы, текст, PDF, изображения, видео, аудио, торренты) | gio/xdg-mime/xdg-settings есть; сейчас zen, thunar, zathura, Zed, Loupe, mpv, Thunderbird, tremc | `.config/mimeapps.list` в репо — шаблон, пишем только живой файл |
| Терминал / файловый менеджер | переменные `terminal`/`fileManager` → бинды SUPER+Q/E через переопределение биндов | — | — |
| Автозапуск | см. §10, вопрос 2. Рекомендация: управляемый список в `settings.json` → `hl.on("hyprland.start")` в settings.lua; инфраструктурные строки hyprland.lua (hyprglass, polkit, keyring, порталы, hypridle, qs, mpvpaper, ssh-add, gsettings) показываются read-only | XDG-автозапуск не исполняется | изменения — со следующего входа; «Запустить сейчас» — отдельной кнопкой |
| Уведомления / DND | `Notifs.dnd` (IPC `notifs dnd`), `Notifs.clearAll()`; `toastDefaultMs`, `notifMax`, `dndAllowCritical` → Prefs | работает в попапе часов | расписание DND — идея v2 |
| О системе | `zephyrine-settings sysinfo`: `hostnamectl --json=short`, `/etc/os-release`, `uname -r`, `hyprctl version -j`, `qs --version`, `/proc/cpuinfo`, `/proc/meminfo`, `/proc/uptime`, GPU — `lspci`/sysfs, диски — как Disks.qml; «Скопировать» — `wl-copy` | всё есть | — |

------------------------------------------------------------------------------------------------### 4.5 Панель (положение и состав, Y8)

Ключи читает сам шелл из `settings.json` (`Prefs.qml`), целей генератора у них нет — применяются вживую, перезапуск не нужен.

| Функция | Механизм | Заметки |
|---|---|---|
| Положение | `bar.position` = `top` \| `bottom` \| `left` \| `right` (по умолчанию `top`) | `Bar.qml`: якоря окна layer-shell и `exclusiveZone = Config.barExtent`; фон бара — отступ `barMargin` с трёх сторон (кроме прижатой к краю) |
| Состав и порядок | `bar.left` / `bar.center` / `bar.right` — списки id; каждый id — не более чем в одной зоне, нескрытые вне зон = «Скрытые» | реестр id → компонент в `Bar.qml` (`registry`), список id и подписи — `zsettings/barlayout.py`, `BarCard.qml`, `Prefs.qml` (дублируются, править во всех) |
| Вертикальная панель | зоны идут сверху вниз; у элементов есть компактные виды (`IconPill`, `VWorkspaces`, `VClock`, `VTray`, `VStatus`); `activeWindow`, `media`, `limits`, `disk` на ней не показываются (в редакторе помечены) | значения — в подсказках и hover-попапах; толщина `Config.barThickness` = 48 |
| Попапы / подсказки / тосты / OSD | `Popout.qml` раскрывается под/над/справа/слева от панели (носитель вдоль бара, карточка у триггера); `Tip.qml` — от панели; тосты и OSD отступают на `barExtent`, когда панель с их стороны | |
| Дополнительные виджеты | `temp` (CPU/GPU °C, без своего попапа — значения в подсказке, подробности у `cpu`), `battery` (значок + %), `kbd` (раскладка, клик — следующая), `timer` (обратный отсчёт, `services/Countdown.qml`, попап `timer`; своё время набирается кнопками +/−, без клавиатуры: ввод с клавиатуры в попапах панели не работает, см. §11), `weather` (wttr.in `?format=j1`, `services/Weather.qml` + `weather.js`, попап `weather`: сводка, плитки, восход/закат, почасовой и 3-дневный прогноз; город — `weather.city`), `volume` / `wifi` / `bluetooth` (отдельные пилюли с теми же попапами, что у статус-иконок) | по умолчанию НЕ на панели (`barlayout.DEFAULT_HIDDEN`), добавляются в редакторе; погода запрашивается, только пока виджет стоит на панели; вертикальные виды — `IconPill` (`label` вместо иконки) |
| Экран блокировки и окно входа | цели `hyprlock` (шаблон `templates/hypr/hyprlock.conf.tmpl` → `.config/hypr/hyprlock.conf`) и `sddm` (`templates/sddm/theme.conf.user.tmpl` → `sddm/zephyrine/theme.conf.user`, копируется в `/usr/share/sddm/themes/zephyrine/` командой `sudo sddm/install-theme.sh`); ключи `appearance.accent`, `appearance.fonts.lock.family`, `appearance.fonts.login.family` | при дефолтных настройках вывод совпадает с прежним (golden; значения `sddm` = `theme.conf`); SDDM-часть вступает в силу только после sudo-шага |
| Редактор | вкладка «Панель» во «Внешнем виде» (`BarCard.qml`): положение, ↑/↓ в зоне, перенос между зонами, убрать/добавить, сброс | перетаскивание мышью — идея на потом |

Проверка: `barlayout.check_values` (известные id, без повторов между зонами) вызывается из `zephyrine-settings set`.

---

## 5. Модель данных

`settings/schema.json` — плоский словарь «ключ с точками → описание». Поля описания: `type`
(`number|integer|boolean|string|color|enum|font|path|array|object`), `default`, `min`/`max`/`step`,
`enum`, `nullable`, `targets` (какие цели перегенерировать), `live` (bool), `stage`. UI берёт отсюда диапазоны
и дефолты («Сбросить»), подписи — в QML.

| Ключ | Тип | По умолчанию | Применяется в | Этап |
|---|---|---|---|---|
| `appearance.accent` | color, nullable | `null` (= primary из scheme.json) | все цели палитры | v1 |
| `appearance.glassAlpha` | number 0.5–1, шаг 0.01 | 0.88 | бар, gtk*, obsidian, tb-css, zen-chrome, zed | v1 |
| `appearance.surfaceAlpha` | number 0.7–1 | 0.94 | бар, gtk*, obsidian, tb-css | v1 |
| `appearance.radius` | integer 0–20 | 12 | бар, gtk*, obsidian, tb-css, zen-chrome | v1 |
| `appearance.windowRounding` | integer 0–20 | 10 | hypr | v1 |
| `appearance.targets.<id>` | boolean | true | вкл/выкл управление целью | v1 |
| `hypr.borders.style` | enum legacy/accent/custom | `legacy` | hypr | v1 |
| `hypr.borders.size` | integer 0–4 | 2 | hypr | v1 |
| `hypr.borders.custom` | object `{active:[rgba…], angle, inactive}` | текущие значения | hypr | v1 |
| `hypr.glassOpacity` | number 0.3–1 | 0.7 | hypr (hyprglass) | v1.1 |
| `appearance.fonts.shell.family` / `.size` | font (Nerd) / integer 10–16 | JetBrainsMono Nerd Font / 13 | бар (Config) | v1.1 |
| `appearance.fonts.ui.family` / `.size` | font / integer 8–14 | Inter / 10 | gtk settings.ini, gsettings, qt6ct | v1.1 |
| `appearance.fonts.mono.family` / `.size` | font mono / integer 8–16 | JetBrainsMono Nerd Font / 11 | kitty, zathura, qt6ct fixed, obsidian, gsettings | v1.1 |
| `appearance.icons.theme` | string, nullable (`null` = по режиму) | `null` | gtk settings.ini, qt6ct, gsettings (§3.11) | v1.1 |
| `appearance.cursor.theme` / `.size` | string / integer 16–64 | Qogir / 24 | gtk settings.ini, gsettings, hypr (env), `hyprctl setcursor` (§3.11) | v1.1 |
| `appearance.kittyOpacity` | number 0.5–1 | 0.70 | kitty.conf | v1.1 |
| `appearance.wallpaper.desktop` | path | `wallpapers/japanese-night-village.1920x1080.mp4` | mpvpaper | v1.1 |
| `appearance.wallpaper.lock` | path, nullable (`null` = как рабочий стол) | `null` | lock-with-video.sh | v1.1 |
| `network.confirmDisruptive` | boolean | true | UI (подтверждения) | 2 |
| `audio.volumeMax` / `audio.volumeStep` | number 1–1.5 / 0.01–0.1 | 1.0 / 0.05 | Config | 3 |
| `display.monitors` | array `{match, enabled, mode, position, scale, transform, mirror}` | `[]` (= правила hyprland.lua) | hypr | 3 |
| `display.confirmTimeoutSec` | integer 5–60 | 15 | сторож отката | 3 |
| `power.idle.dimSec` / `.dimLevel` | integer, nullable / string | 150 / `"10"` (сырое, как сейчас) | hypridle | 3 |
| `power.idle.lockSec` | integer, nullable | `null` (автолок выключен пользователем) | hypridle | 3 |
| `power.idle.dpmsSec` | integer, nullable | 330 | hypridle | 3 |
| `power.idle.suspendSec` | integer, nullable | `null` | hypridle | 3 |
| `power.batteryCritical` | number 0.05–0.3 | 0.15 | Config | 3 |
| `input.layouts` | array `{layout, variant}` | `[{pl,""},{ru,""}]` | hypr | 4 |
| `input.switchOption` | enum из `grp:*` / `""` | `grp:alt_shift_toggle` | hypr | 4 |
| `input.extraOptions` | array string | `[]` | hypr | 4 |
| `input.repeatRate` / `.repeatDelay` | integer | 25 / 600 | hypr | 4 |
| `binds.<action>` | array of string (комбинации) | как в hyprland.lua (лаунчер: `SUPER + Super_L` (release), `SUPER + space`, `SUPER + R`) | hypr | 4 |
| `apps.terminal` / `apps.fileManager` | string (команда) | `kitty` / `thunar` | hypr (бинды) | 4 |
| `autostart` | array `{id, name, cmd, enabled, delaySec}` | перенос пользовательских строк (Telegram, zen-browser, viber) — после решения §10 | hypr | 4 |
| `notifications.toastMs` / `.historyMax` / `.dndAllowCritical` | integer / integer / boolean | 5000 / 50 / true | Config | 4 |

Не хранится в settings.json (источник правды — сама система): состояние Wi-Fi/Bluetooth/сетей (NetworkManager,
BlueZ), громкость и устройства (PipeWire/WirePlumber), профиль питания (power-profiles-daemon), приложения по
умолчанию (`mimeapps.list`), DND (`state.json`).

Пример `settings.json` после смены акцента и альфы:

```json
{
  "version": 1,
  "appearance": { "accent": "#7aa2f7", "glassAlpha": 0.82 }
}
```

---------------------------------------------------------------------------------------------------

## 6. UI

### 6.1 Навигация и клавиатура

Сайдбар (220 px) с четырьмя разделами в порядке пользователя, контент — прокручиваемый столбец карточек.
Внизу сайдбара — сводка «N приложений ждут перезапуска» (клик → карточка целей). Клавиатура (нужна и для
проверки через `hl.dsp.send_shortcut`, если это сработает с окном qs): `Ctrl+1…4` — раздел, `Ctrl+Tab` —
следующий, `Tab`/`Shift+Tab` — по контролам, стрелки — в списках и ползунках, `Enter`/`Space` —
активировать, `Esc` — закрыть всплывающее/окно. Состояние (раздел, прокрутка) живёт в Overlays, пока окно
закрыто.

### 6.2 Компоненты

Переиспользуем как есть: `Txt`, `PopSwitch`, `PopField` (поля, пароль с «глазом»), `PopItem` (строки списков,
кнопки-иконки), `PopBar` (полоски уровней), `Tip`, паттерн «двойное нажатие = подтверждение» из
`PowerMenu.qml` (armed + 3 с), спиннер из WifiPopout, `Toaster.show`.

Новые общие (`quickshell/components/`, стиль как у существующих — шапка-комментарий по-русски, цвета только
`Colors.*`, размеры `Config.*`):

| Компонент | Назначение |
|---|---|
| `SetCard` | карточка раздела: заголовок, необязательная иконка и чип статуса, содержимое; фон `Qt.alpha(Colors.surfaceContainer, Config.pillAlpha)`, рамка `Qt.alpha(Colors.outline, 0.28)`, радиус `Config.popoutRadius` |
| `SetRow` | строка «подпись + пояснение мелким + контрол справа» с местом под ошибку |
| `SetSlider` | `PopSlider` с min/max/step, значением справа, `preview` при движении и `commit` при отпускании |
| `SetDropdown` | выбор из списка (выпадающий список внутри окна, а не отдельный PopupWindow), поиск при >10 пунктах |
| `SetSegmented` | 2–4 варианта (профиль питания, стиль рамок) |
| `SetButton` | обычная / основная / опасная (с armed-подтверждением) |
| `StatusChip` | «вживую», «нужен перезапуск», «не установлено», «изменён вручную», «ошибка» |
| `HexField` | `PopField` + проверка `#rrggbb` + образец цвета + контраст |

Специфичные для окна (`quickshell/settings/parts/`): `AccentPicker`, `TargetsList`, `WallpaperGrid`,
`MonitorCard`, `MonitorConfirm` (слой Overlay на ВСЕХ экранах), `BindsList`, `KeyCapture`, `LayoutsEditor`,
`DefaultApps`, `AutostartList`, `AboutCard`. Чистая логика (позиции мониторов «справа от/над», конфликты
биндов, разбор `base.lst`, форматирование) — в `settings/logic.js` с node-тестом по образцу
`launcher/search-test.js`.

Стиль: окно — `Qt.alpha(Colors.background, Config.barAlpha)`; выбранный пункт сайдбара —
`Qt.alpha(Colors.primaryContainer, 0.75)` (как текущая строка лаунчера), hover — `Colors.surfaceContainerHighest`;
разделители `Qt.alpha(Colors.outline, 0.35)`; иконки — Nerd Font из `Config.icons` (добавить недостающие:
палитра, монитор, клавиатура уже есть и т.д.).

### 6.3 Состояния ошибок

| Ситуация | Отображение |
|---|---|
| Бэкенд отсутствует (`doctor`) | строка неактивна, чип «не установлено: X», подсказка, что поставить |
| Ошибка валидации | под полем красным (`Colors.error`, `fontSize − 1`), значение не применено |
| CLI упал / код ≠ 0 | баннер над содержимым раздела: кратко по-русски + сырое сообщение мелким (как форма Wi-Fi) + «Повторить» |
| Частичный сбой целей | тост на каждую упавшую цель, чип «ошибка» в списке целей |
| Drift | чип «изменён вручную» + «Показать различия» / «Перезаписать» (двойное нажатие) / «Не управлять» |
| Нет профиля/приложения | чип «профиль не найден»/«не установлено», не ошибка |
| CLI занят (код 3) | тихий повтор через 500 мс, после 3 неудач — баннер |
| Мониторы: откат сработал | тост «Настройки экрана возвращены» |

### 6.4 Анимации

Как в шелле: `Config.animMs` (200) + `Config.animEasing` (OutCubic). Смена раздела — контент
opacity 0→1 и сдвиг y 8→0; подсветка пункта сайдбара едет `Behavior on y`; карточки, раскрывающие детали, —
`Behavior on height`; цвета — `ColorAnimation` как в Pill/PopItem; таймер отката мониторов — линейная полоска
на всю длительность; спиннер «применяется…» — `RotationAnimation` как в WifiPopout.

### 6.5 Макеты

Каркас окна и «Внешний вид» (v1):

```
╭─ Zephyrine · Настройки ─────────────────────────────────────────────────────────────── ✕ ─╮
│ ┌──────────────────────┐  Внешний вид                                                   │
│ │󰏘 Внешний вид        ◀│  ╭ Акцент ──────────────────────────────────────────────────╮ │
│ │󰖩 Сеть и Bluetooth    │  │ (●)(●)(●)(●)(●)(●)(●)(●)   [#bb9af7      ]  контраст 7.9 ✓  │ │
│ │󰕾 Звук, экран, питание│  │ из палитры · сбросить                                    │ │
│ │󰌌 Система и приложения│  ╰──────────────────────────────────────────────────────────╯ │
│ │                      │  ╭ Стекло и формы ──────────────────────────────────────────╮ │
│ │                      │  │ Прозрачность фона      ━━━━━━━━━━━━━━●────   0.88  ↺      │ │
│ │                      │  │ Плотность элементов    ━━━━━━━━━━━━━━━━━●─   0.94  ↺      │ │
│ │                      │  │ Скругление             ━━━━━━━━━●────────    12    ↺      │ │
│ │                      │  │ Скругление окон        ━━━━━━━━●─────────    10    ↺      │ │
│ │                      │  │ Рамки окон      [ Как сейчас | Акцент | Свои ]  толщина 2 │ │
│ │                      │  ╰──────────────────────────────────────────────────────────╯ │
│ │                      │  ╭ Шрифты (v1.1) ───────────────────────────────────────────╮ │
│ │                      │  │ Панель       [JetBrainsMono Nerd Font ▾]  [13]           │ │
│ │                      │  │ Интерфейс    [Inter ▾]                    [10]           │ │
│ │                      │  │ Моноширинный [JetBrainsMono Nerd Font ▾]  [11]           │ │
│ │                      │  ╰──────────────────────────────────────────────────────────╯ │
│ │                      │  ╭ Обои (v1.1) ─────────────────────────────────────────────╮ │
│ │                      │  │ ┌────┐ ┌────┐ ┌────┐ ┌────┐   ☑ и на экране блокировки   │ │
│ │                      │  │ │ ▶  │ │ ✓  │ │ ▶  │ │ ▶  │   SDDM: нужна команда с sudo │ │
│ │                      │  │ └────┘ └────┘ └────┘ └────┘   [Скопировать команду]      │ │
│ │                      │  ╰──────────────────────────────────────────────────────────╯ │
│ │                      │  ╭ Применение к приложениям ────────────────────────────────╮ │
│ │                      │  │ Панель (Quickshell)          вживую                 [■]  │ │
│ │                      │  │ Hyprland                     вживую                 [■]  │ │
│ │                      │  │ Kitty · Zed                  вживую                 [■]  │ │
│ │                      │  │ GTK 3/4 · Qt                 ↻ открытые окна        [■]  │ │
│ │                      │  │ Zathura · Obsidian (3)       ↻ перезапуск / Ctrl+R  [■]  │ │
│ │ ⓘ 2 приложения ждут  │  │ Thunderbird · Zen            ↻ полный перезапуск    [■]  │ │
│ │   перезапуска        │  │ ⚠ GTK 3: изменён вручную  [Различия] [Перезаписать]       │ │
│ └──────────────────────┘  ╰──────────────────────────────────────────────────────────╯ │
│                                    ┌ Применено · Отменить ┐                              │
╰───────────────────────────────────────────────────────────────────────────────────────────╯
```

«Сеть и Bluetooth» (этап 2):

```
  Сеть и Bluetooth
  ╭ Wi-Fi ───────────────────────────────────────────────────────── [■ вкл] ╮
  │ 󰤨 Home-5G · подключено · 82%      IP 192.168.1.23 · шлюз .1 · DNS …     │
  │ ───────────────────────────────────────────────────────────────────────  │
  │ 󰤥 Neighbour            󰌾  64%                                            │
  │ 󰤢 Cafe-Free                41%                                            │
  │ [󰑐 Обновить]  [󰌾 Скрытая сеть…]                                           │
  │ Сохранённые: Home-5G (авто ■) [Забыть]   Office (авто □) [Забыть]         │
  ╰─────────────────────────────────────────────────────────────────────────╯
  ╭ Bluetooth ──────────────────────────────────────────────────── [■ вкл] ╮
  │ Видимость для других [□]                                               │
  │ 󰂱 WH-1000XM4   подключено · 󰁹 80%   [Отключить] [Доверять ■] [Забыть]   │
  │ 󰂯 MX Keys      сопряжено            [Подключить]                        │
  │ [󰑐 Найти устройства]   Сопряжение: «Подтвердите код 123456» [Да] [Нет]  │
  ╰────────────────────────────────────────────────────────────────────────╯
```

«Звук, экран, питание» (этап 3):

```
  ╭ Звук ──────────────────────────────────────────────────────────────────╮
  │ Выход  [Ryzen HD Audio Аналоговый стерео ▾]  󰕾 ━━━━━━━━●──── 75%  [mute] │
  │ Вход   [Ryzen HD Audio Аналоговый стерео ▾]  󰍬 ━━━━━━━━━━━● 100% [mute] │
  │ Приложения:  Zen ━━━━━●──── 50%   Telegram ━━━━━━━━●── 80%              │
  │ Макс. громкость [100% | 150%]          [Открыть pavucontrol]           │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Экраны ────────────────────────────────────────────────────────────────╮
  │ ┌ eDP-1 · встроенный ─────────────┐ ┌ DP-6 · Dell U2415 ──────────────┐ │
  │ │ Режим   [1920x1080 @ 60 ▾]      │ │ Режим [1920x1200 @ 60 ▾]        │ │
  │ │ Масштаб [1 | 1.25 | 1.5 | 2]    │ │ Положение [над eDP-1 ▾]         │ │
  │ │ Поворот [0° ▾]   Вкл [■]        │ │ Вкл [■]   Зеркало [нет ▾]       │ │
  │ └─────────────────────────────────┘ └─────────────────────────────────┘ │
  │                                        [Сбросить]  [Применить…]        │
  │ Яркость 󰃟 ━━━━━━━━━━━━━━━━━━━● 100%                                     │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Питание ───────────────────────────────────────────────────────────────╮
  │ Профиль  [ Экономия | Баланс | Производительность ]                     │
  │ Батарея 87% · разряжается · осталось 3 ч 10 мин · ёмкость 91%           │
  │ Затемнять через   [2.5 мин ▾]   Гасить экран через [5.5 мин ▾]         │
  │ Блокировать через [никогда ▾]   Сон через          [никогда ▾]         │
  ╰────────────────────────────────────────────────────────────────────────╯
```

Подтверждение мониторов (`MonitorConfirm`, слой Overlay на каждом экране, `Exclusive`-клавиатура):

```
          ╭────────────────────────────────────────────────╮
          │ 󰍹  Оставить новые настройки экранов?            │
          │    Без ответа вернём прежние через 12 с         │
          │    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━──────────     │
          │      [ Оставить · Enter ]   [ Вернуть · Esc ]   │
          ╰────────────────────────────────────────────────╯
```

«Система и приложения» (этап 4):

```
  ╭ Клавиатура ────────────────────────────────────────────────────────────╮
  │ Раскладки:  ⋮ PL Polish            [▾ вариант] [✕]                      │
  │             ⋮ RU Russian           [▾ вариант] [✕]     [+ Добавить]     │
  │ Переключение [Alt+Shift ▾]   Повтор: задержка [600] мс, частота [25]/с  │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Сочетания клавиш ───────────────────────── [поиск…        ] ───────────╮
  │ Лаунчер            Super · Super+Space · Super+R            [Изменить]  │
  │ Меню питания       Super+Esc · XF86PowerOff                 [Изменить]  │
  │ Настройки          Super+I                                  [Изменить]  │
  │ Терминал           Super+Q  → [kitty ▾]                     [Изменить]  │
  │ … остальные (только просмотр): Super+C закрыть окно, Super+1…0 …        │
  ╰────────────────────────────────────────────────────────────────────────╯
     KeyCapture: «Нажмите сочетание… (Esc — отмена)»  → «Super+Shift+K · свободно ✓»
  ╭ Тачпад ────────────────────────────────────────────────────────────────╮
  │ Естественная прокрутка [■]   Касание = клик [■]   Касание и перетаскивание [■]│
  │ Отключать при наборе [■]   Клик по числу пальцев [■]   Средняя кнопка [□]     │
  │ Скорость прокрутки ──●── 1.0×      Чувствительность указателя ──●── 0.00      │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Приложения по умолчанию ───────────────────────────────────────────────╮
  │ Браузер [Zen ▾]   Почта [Thunderbird ▾]   Файлы [Thunar ▾]              │
  │ Текст [Zed ▾]     PDF [Zathura ▾]   Изображения [Loupe ▾]   Видео [mpv ▾]│
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Автозапуск ────────────────────────────────────────────────────────────╮
  │ [■] Telegram        Telegram                     задержка 0 с  [✕]     │
  │ [■] Zen Browser     zen-browser                  задержка 0 с  [✕]     │
  │ [■] Viber           QT_QPA_PLATFORM=wayland viber  5 с         [✕]     │
  │ Системное (только просмотр): hyprglass, polkit, keyring, порталы, …     │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ Уведомления ───────────────────────────────────────────────────────────╮
  │ Не беспокоить [□]   Важные показывать в DND [■]                         │
  │ Время показа [5 с ▾]   Хранить [50 ▾]   [Очистить историю]              │
  ╰────────────────────────────────────────────────────────────────────────╯
  ╭ О системе ─────────────────────────────────────────────────────────────╮
  │ zephyrka · EndeavourOS · Linux 7.2.7 · Hyprland 0.56.2 · Quickshell 0.3.1│
  │ Ryzen 9 4900HS · 38 ГиБ · RTX (TU106) + Radeon · аптайм 3 ч             │
  │ Компоненты: ✓ nmcli ✓ PipeWire ✓ ppd ✗ nm-connection-editor …          │
  │ [Скопировать]                                                           │
  ╰────────────────────────────────────────────────────────────────────────╯
```

---------------------------------------------------------------------------------------------------

## 7. Безопасность и откат

### 7.1 Общее

- Любая перезапись файла: бэкап в `backups/<ts>-<причина>/` (+ `manifest.json` с исходным путём и sha256),
  ротация 20; `zephyrine-settings backup restore ID` и кнопка «Отменить» (история `settings.json`).
- Идемпотентность: рендер → сравнение → запись только при отличии; повторный `apply` = пустой `changed`.
- Атомарность: tmp + rename в каталоге realpath; симлинки (`~/.config/{hypr,kitty,zed,zathura/zathurarc}`,
  `quickshell/zephyrine`) не заменяются.
- Один писатель: `flock` на `settings.lock`.
- Нет приложения/профиля/vault'а/смонтированного `/mnt/data` → `skipped`, не ошибка. Путь профиля Zen с
  пробелами — только списки аргументов, никаких неэкранированных `sh -c`.
- Шрифты, раскладки, опции xkb, пути обоев — только из белых списков (fc-list, base.lst, существующие
  файлы). Строки в Lua — `lua_str`. Команды автозапуска — по определению команды пользователя, но
  выполняются только Hyprland при старте сессии, не CLI.
- Без root: SDDM, системные файлы — только показать команду (`sudo …/sddm/install-theme.sh`) и скопировать.

### 7.2 Мониторы (риск чёрного экрана)

1. `monitors snapshot` — текущие фактические параметры (`hyprctl monitors all -j`), не конфиг.
2. `monitors try SPEC` — через `hyprctl eval`: `_G.zp_mon = {token, prev}`, применить `hl.monitor` для
   каждого изменённого выхода, завести `hl.timer(…, {timeout = confirmTimeoutSec·1000, type = "oneshot"})`,
   который при `not confirmed` возвращает `prev` и шлёт `hl.notification`. **Сторож живёт в компоситоре** —
   откат сработает, даже если qs упал или окно на погасшем экране.
3. UI показывает `MonitorConfirm` на всех экранах; Enter/«Оставить» → `monitors confirm TOKEN` (флаг в `_G`,
   затем запись `display.monitors` в settings.json и settings.lua; reload не нужен); Esc/«Вернуть» →
   `monitors revert TOKEN`.
4. Запреты: нельзя выключить последний включённый выход; масштаб — только из списка, при котором логический
   размер ≥ 1024×600; пока ждём подтверждения — остальные изменения Hyprland блокируются (любой reload
   вернул бы старые правила).
5. Привязка к монитору — `desc:<description>`, если описание непустое и уникальное, иначе имя выхода.
   Обработчик `monitor.added` (ws 10 на внешнем) в hyprland.lua не трогаем.

### 7.3 Сеть и прочее

- Без подтверждения (двойное нажатие, 3 с) не выполняются: выключение Wi-Fi/Bluetooth-радио, отключение от
  активной сети, «Забыть» сеть/устройство, режим «в самолёте», выключение монитора, очистка истории
  уведомлений, перезапись drift-файла.
- Пароли Wi-Fi — только через stdin `nmcli --ask` (как сейчас), нигде не логируются и не сохраняются.
- Захват сочетаний: submap со сторожем (15 с) — клавиатура не останется без биндов.
- Раскладки: в списке всегда ≥ 1 раскладка; опция переключения обязательна при ≥ 2 раскладках.
- Idle: блокировка по таймауту/сон — только явным выбором пользователя (сейчас выключены осознанно).

---------------------------------------------------------------------------------------------------

## 8. Проверка без GUI

Ограничения среды (CONTEXT.md): sandbox убивает любые запущенные GUI-процессы, `qs` запускает только
пользователь; нет sudo и pkexec. Доступно: `qs ipc call`, `qs log -t`, `hyprctl` (repl/eval/reload/
configerrors/monitors/binds/devices/output create headless), `grim` (+ Read картинки), курсор
`hyprctl dispatch "hl.dsp.cursor.move({x=,y=})"` (потом вернуть в 960,540), `notify-send`, node, python, lua.
CLI из sandbox — только с `--no-exec` (никаких kill/запусков GUI) или в изолированном HOME.

| Часть | Как проверить |
|---|---|
| color.py, render.py, model.py | `python3 -m unittest discover settings/tests` (OKLCH-туда-обратно, форматы, `anchor`, строгость, разреженный merge, валидация по схеме) |
| Шаблоны | `test golden` (0 различий с репо и живыми копиями), `test perturb <ключ>` против снимков, `test lint` |
| Цели и деплой | интеграционный тест в изолированном HOME: `HOME=$(mktemp -d)` + `tests/fixtures/home` (фейковые `installs.ini`, профили, `obsidian.json` с vault'ами в tmp) + копия репо в `ZEPHYRINE_ROOT`; `apply`, повторный `apply` (пустой `changed`), ручная правка → `drift`, `backup restore` |
| Палитра бара | `set appearance.accent=#7aa2f7` → `grim -g "0,0 1920x52"` → Read (бар перекрасился), `undo` → снова golden; `qs log -t 30` без новых предупреждений |
| settings.lua | `luac -p`; прогон в системном `lua` с `tests/mock_hl.lua` (записывает вызовы `hl.*` в JSON) → сравнение с ожидаемым; живьём: `hyprctl reload config-only`, `hyprctl configerrors` пусто, `hyprctl repl 'return hl.get_config("decoration.rounding")'` |
| Мониторы | только на headless: `hyprctl output create headless` → `monitors try` для HEADLESS-N → `hyprctl monitors -j` (применилось) → ждать таймаут → откат; второй прогон с `confirm`; `hyprctl output remove HEADLESS-N`. Реальный eDP-1 из sandbox не трогать |
| dpms (вопрос 1) | `hl.dsp.dpms({action="off", monitor="HEADLESS-N"})` на headless → `dpmsStatus` false |
| hypridle | рендер шаблона vs ожидаемый текст; перезапуск делает шелл — проверка `pgrep -a hypridle` |
| Раскладки | settings.lua → reload → `hyprctl devices -j` (`layout`, `options`) |
| Бинды | `hyprctl binds -j`: новая комбинация с `description`, старой нет |
| Приложения по умолчанию | в изолированном HOME (`XDG_CONFIG_HOME` → tmp): `gio mime …` → `xdg-mime query default …` |
| Звук / BT / Wi-Fi | только чтение (`wpctl status`, `bluetoothctl show/devices`, `nmcli`) до и после действий пользователя; разрушительное — пользователь |
| UI (вид) | пользователь один раз перезапускает шелл → `qs ipc call settings openAt <раздел>` → `grim` → Read; каждый раздел/подраздел скриншотом; `qs log -t 50` |
| UI (логика) | `node quickshell/settings/logic-test.js` |
| UI (клики) | чек-лист пользователю (в todo.md); опционально — клавиатурная навигация через `hl.dsp.send_shortcut` (не проверено, работает ли с окном qs) |

---------------------------------------------------------------------------------------------------

## 9. План реализации

Агенты по политике: `opus-agent` — только реально сложное; `sonnet-agent` — основная реализация;
`haiku-agent` — мелкое однозначное; `local-agent` — механика. Python- и QML-треки независимы благодаря
контракту §2.4 и могут идти параллельно.

### 9.1 Этап v1 — «минимальный, но рабочий» вертикальный срез

Окно (каркас, 4 раздела, три — заглушки «скоро») + «Внешний вид»: акцент, две альфы, скругление, скругление
окон, рамки, список целей с чипами, «Отменить»; генератор для всех 11 целей тем + Hyprland.

| ID | Задача | Вход | Выход | Критерий приёмки | Зависит от | Агент | Параллельно |
|---|---|---|---|---|---|---|---|
| S1.1 | Схема и палитра: `schema.json` (ключи §5, v1 полно, будущие — заглушками), ext-ключи в `scheme.json` (§3.4), `palette-roles.json` (якоря), `targets.json` | §3.4, §3.5, §5, текущие файлы | 4 файла | `scheme.json` валиден, Colors.qml не изменил вида (`grim` бара до/после идентичен); каждый из 31 «внешних» цветов имеет ключ или помечен как не-палитра | — | sonnet (ultrathink) | с S1.3, S1.4, S1.9, S1.11 |
| S1.2 | Ядро CLI: `model.py` (схема, разреженный merge, валидация), атомарная запись, flock, `settings-history`, `undo`, `backup`, JSON-вывод и коды §2.4, `bin/zephyrine-settings`, `open` | §2.3–2.4 | `zsettings/{cli,model,backup,util}.py` + тесты | unittest зелёные; `get`/`set --no-apply`/`reset`/`undo` работают в изолированном каталоге | S1.1 (формат схемы; можно начать на заглушке) | sonnet | с S1.3, S1.4 |
| S1.3 | `color.py`: hex↔sRGB↔OKLab/OKLCH, гамут-клип, якорная деривация с short-circuit, контраст WCAG, `hsl-string` | §3.5 | модуль + тесты | туда-обратно ±0 для 31+60 цветов; short-circuit возвращает литерал; маркер-акцент даёт осмысленные контейнеры | — | sonnet | да |
| S1.4 | `render.py`: мини-шаблонизатор и фильтры §3.3 | §3.3 | модуль + тесты | все фильтры дают текущее написание (`rgba(20, 20, 20, 0.88)`, `#ffbb9af7`, `dd`, `11.0`, `12px`); неизвестный ключ/фильтр — ошибка | — | haiku (спецификация полная; если тесты не сходятся — sonnet) | да |
| S1.5a | Шаблоны GTK3 + GTK4 | S1.1, S1.4 | `templates/gtk/*.tmpl` | golden 0, lint 0, снимок perturb primary/glass/radius одобрен | S1.1, S1.4, S1.7 | sonnet | S1.5a–g все параллельно |
| S1.5b | Шаблон qt6ct (ARGB, 3×21 цвет) | то же | `templates/qt6ct/zephyrine.conf.tmpl` | то же | то же | haiku | да |
| S1.5c | Шаблон Zed (≈210 ссылок, синтаксис → hue-ключи, UI → семантика, альфы через `anchor`/`hexbyte`) | то же | `templates/zed/zephyrine.json.tmpl` | то же | то же | sonnet | да |
| S1.5d | Шаблоны kitty `zephyrine.conf` + zathurarc | то же | 2 шаблона | то же | то же | haiku | да |
| S1.5e | Шаблон Obsidian theme.css (`rgb`-тройки, `primaryHsl`, радиусы, шрифты) | то же | шаблон | то же | то же | sonnet | да |
| S1.5f | Шаблоны Thunderbird userChrome.css + manifest.json (текстовый, `meta.tbVersion`) | то же | 2 шаблона | то же | то же | haiku | да |
| S1.5g | Шаблоны Zen userChrome.css + userContent.css | то же | 2 шаблона | то же | то же | haiku | да |
| S1.6 | `targets.py` + `palette.py` + `doctor.py`: эффективная палитра, `scheme.override.json`, деплой (копии, vault'ы, профили, xpi), reload-действия, drift, статусы, `apply`, `status`, `doctor` | §3.2, §3.6, §3.8 | модули + интеграционный тест | изолированный HOME: apply/повтор/drift/restore по §8; реальные пути не трогаются в тестах | S1.2, S1.4 | sonnet | с S1.5 |
| S1.7 | Тестовый стенд: `test golden/perturb/lint`, фикстуры HOME, снимки | §3.6, §8 | `tests/*`, команды CLI | golden ловит изменение одного байта; perturb пишет читаемый отчёт | S1.4 | sonnet | раньше S1.5 (им нужен golden) |
| S1.8 | `hypr.py` эмиттер (рамки, скругление, glass_opacity) + `mock_hl.lua` + текст одноразовой правки hyprland.lua (§3.9: dofile, SUPER+I, правило окна) | §3.9 | модуль, тест, патч | settings.lua по умолчанию ничего не меняет (`get_config` до/после равны); `configerrors` пуст; правку живого hyprland.lua применять только после «да» пользователя, с бэкапом | S1.2 | sonnet (правку файла по готовому патчу — haiku) | да |
| S1.9 | `Prefs.qml` + правки `Config.qml`/`Colors.qml` (§2.6) + `services/SettingsCli.qml` | §2.5–2.6, контракт §2.4 | QML | бар идентичен (`grim` до/после), `qs log` чист; при подмене settings.json альфа бара меняется вживую | контракт | sonnet | с Python-треком |
| S1.10 | Каркас окна: Overlays (`settingsOpen`, IPC `settings`), `SettingsWindow` (FloatingWindow, LazyLoader в shell.qml), `Sidebar`, навигация/клавиатура, 6-я кнопка меню питания, глубокие ссылки из попапов | §2.7–2.8, §6.1 | QML | `qs ipc show` содержит `settings`; `openAt appearance|network|devices|system` → скриншоты; закрытие SUPER+C сбрасывает состояние | S1.9 | sonnet | с S1.11 |
| S1.11 | Общие компоненты `components/Set*.qml`, `StatusChip`, `HexField` | §6.2 | QML | страница-витрина (временная) на скриншоте; стиль совпадает с попапами | — | sonnet (простые StatusChip/SetCard/SetRow — haiku) | да |
| S1.12 | Страница «Внешний вид» v1 (AccentPicker, ползунки с превью, рамки, TargetsList, снекбар «Отменить», ошибки) | всё выше | `pages/AppearancePage.qml`, parts | смена акцента/альфы с UI и через CLI меняет бар, kitty, файлы; «Отменить» возвращает golden | S1.6, S1.8–S1.11 | sonnet | — |
| S1.13 | Приёмка с пользователем: перезапуск шелла, чек-лист кликов, вид GTK/Obsidian/TB/Zen после перезапуска приложений | — | отметки в todo.md | пункты чек-листа подтверждены | S1.12 | sonnet (оркестрирует) + пользователь | — |
| S1.14 | Документация: раздел README, запись в `~/CONTEXT.md`, пункты в todo.md | итоги | тексты | кратко, без дублей | S1.13 | haiku / local-agent | — |

Порядок: S1.1, S1.3, S1.4, S1.9, S1.11 стартуют сразу → S1.2, S1.7 → S1.5a–g (параллельно) и S1.6, S1.8 →
S1.10 → S1.12 → S1.13 → S1.14.

**Приёмка v1:** (1) `test golden` = 0 различий по всем целям; (2) `qs ipc call settings openAt appearance`
открывает окно (скриншот); (3) смена акцента (UI или `set appearance.accent=#7aa2f7`) перекрашивает бар и kitty
вживую, остальные выходы перегенерированы, TB/Zen помечены «нужен перезапуск»; (4) смена альфы меняет бар и
GTK/Obsidian/TB/Zen/Zed-выходы; (5) `undo` возвращает все файлы байт-в-байт; (6) settings.lua подключён,
`configerrors` пуст, скругление окон меняется; (7) существующие попапы/бар без регрессий (скриншоты, `qs log`).

### 9.2 Этап v1.1 — остальной «Внешний вид»

| ID | Задача | Агент | Зависит | Параллельно |
|---|---|---|---|---|
| A1 | Шрифты: patch-цели (`settings.ini` ×2, `qt6ct.conf` с подстановкой пути, `kitty.conf`), gsettings, шрифтовые плейсхолдеры в zathura/Obsidian, Config `fontFamily/fontSize` через Prefs, фильтр Nerd Font, UI | sonnet | v1 | с A2, A3 |
| A2 | Обои: симлинки в состоянии, одноразовая правка mpvpaper-строки hyprland.lua и `VIDEO=` в lock-with-video.sh (фолбэк на текущее видео), перезапуск только mpvpaper рабочего стола, превью ffmpeg, `WallpaperGrid`, подсказка SDDM | sonnet | v1 | да |
| A3 | Прозрачность kitty, glass_opacity hyprglass (кнопка «сброс») | haiku | v1 | да |
| A4 | (опц.) шаблон hyprlock.conf (34 цвета, шрифты, радиусы) | sonnet | A1 | да |

### 9.3 Этап 2 — «Сеть и Bluetooth»

| ID | Задача | Агент | Зависит | Параллельно |
|---|---|---|---|---|
| N1 | Страница Wi-Fi на `services/Wifi.qml` (переиспользуем без копирования логики) + детали подключения + сохранённые сети (забыть/автоподключение) + подтверждения | sonnet | v1 (каркас) | с N2 |
| N2 | Страница Bluetooth на `Quickshell.Bluetooth` (видимость, trust/forget/pair Just-Works, батарея) | sonnet | v1 | да |
| N3 | Агент BlueZ `btagent.py` (Agent1 через dbus-python, JSON по stdio) + диалог кода в UI | sonnet (ultrathink) | N2 | — |
| N4 | Попапы: «Подробнее» Wi-Fi → `openAt network/wifi`, ссылки из Bluetooth | haiku | N1 | да |

### 9.4 Этап 3 — «Звук, экран, питание»

| ID | Задача | Агент | Зависит | Параллельно |
|---|---|---|---|---|
| D1 | Звук: устройства, громкость, приложения, `volumeMax/Step` через Prefs | sonnet | v1 | с D2–D4 |
| D2 | Яркость (brightnessctl + sysfs) и профиль питания (`PowerProfiles`), батарея, `batteryCritical` | haiku | v1 | да |
| D3 | Простой: шаблон `hypridle.conf` с блоками (golden = текущий файл), перезапуск hypridle, исправление dpms/затемнения — только после ответа на вопрос 1 | sonnet | v1, вопрос 1 | да |
| D4 | Мониторы, CLI: `monitors snapshot/try/confirm/revert`, сторож в компоситоре, персистентность в settings.lua; приёмка — только на headless-выходе (§8) | sonnet (ultrathink); opus — только если `hl.monitor` в рантайме поведёт себя нестандартно (не применяется/не откатывается) | S1.8 | да |
| D5 | Мониторы, UI: `MonitorCard`, относительное положение (`logic.js` + node-тест), `MonitorConfirm` на всех экранах | sonnet | D4 | — |

### 9.5 Этап 4 — «Система и приложения»

| ID | Задача | Агент | Зависит | Параллельно |
|---|---|---|---|---|
| Y1 | Раскладки и повтор клавиш: разбор `base.lst`, `LayoutsEditor`, settings.lua, проверка `hyprctl devices -j` | sonnet | S1.8 | с Y3, Y5, Y6 |
| Y2 | Сочетания: одноразовая правка hyprland.lua (`description = "zp:<id> · …"` для действий Zephyrine — с согласия), каталог действий, `BindsList`, `KeyCapture` через submap со сторожем, конфликты, `unbind`+`bind` в settings.lua | sonnet (ultrathink) | S1.8 | да |
| Y3 | Приложения по умолчанию (`gio mime`, категории в схеме) | sonnet | v1 | да |
| Y4 | Автозапуск (после вопроса 2) + перенос пользовательских строк из hyprland.lua | sonnet | вопрос 2, S1.8 | да |
| Y5 | Уведомления: Config → Prefs (`toastMs`, `historyMax`, `dndAllowCritical`), DND, очистка | haiku | S1.9 | да |
| Y6 | «О системе»: `sysinfo` в CLI + `AboutCard` + вывод `doctor` | haiku | S1.6 | да |
| Y9 | **Меню приложений на панели** (реализовано): виджет `apps` (кнопка → закреплённый попап `popouts/AppsPopout.qml`): поиск (ранжирование `launcher/search.js`), категории из `.desktop`, часто используемые (история общая с лаунчером), Enter/↑/↓/Esc; на вертикальной панели — иконка | sonnet | Y8 | нет |
| Y8 | Положение и редактор панели: `bar.*` в схеме, `barlayout.py`, реестр и вертикальные виды в `Bar.qml`/`components/V*.qml`, адаптация `Popout`/`Tip`/тостов/OSD, `BarCard` | sonnet | Y7 | нет |
| Y7 | Тачпад и указатель: ключи `input.touchpad.*`/`input.sensitivity`, блок в `hypr.py`, `TouchpadCard` (вкладка «Тачпад»), тесты эмиттера | haiku | Y1 | да |

Статус на 2026-10-02: Y1–Y7 реализованы (вкладки «Клавиатура», «Тачпад», «Сочетания», «Приложения», «Автозапуск», «Уведомления», «О системе» в `SystemSection.qml`).
Правка `hyprland.lua` для Y2/Y4 сделана (с согласия пользователя): у действий Zephyrine `description = "zp:<id> · <подпись>"`, submap `zp_capture`,
Telegram/Zen/Viber убраны из `hyprland.start` (теперь в `autostart` → settings.lua; дефолт `autostart` = эти три записи, поэтому settings.lua
с автозапуском эмитится ВСЕГДА). Каталог действий и их дефолты — `zsettings/binds.py` (ACTIONS); переопределение = `pcall(hl.unbind, старое)` +
`hl.bind(новое, то же действие, {description})`, release-комбинации (SUPER одиночный) сохраняют `release = true`.
Захват безопасен по построению: UI принимает клавиши только после того, как `binds capture` подтвердил submap через `hyprctl submap`
(сначала Lua-синтаксис `hl.dsp.submap`, затем старый `dispatch submap`); если режим не включился — клавиши не принимаются (иначе
сочетание сработало бы), показывается диагностика (`configerrors`) и доступен ручной ввод «SUPER + SHIFT + K».
Проверить вживую: формат `hl.unbind` (для release-бинда), `hl.define_submap("zp_capture", …)`, что клавиши в submap доходят до окна настроек.

### 9.6 Сквозные задачи

| ID | Задача | Агент |
|---|---|---|
| Z1 | `deploy.sh`: после копирования вызывать `zephyrine-settings apply`; убрать дубли поиска профилей | sonnet |
| Z2 | Маркер «сгенерировано, не править» в текстовых выходах (после golden; обновить снимок) | haiku |
| Z3 | Пресеты палитр `settings/palettes/*.json` и «применить пресет» (v2) | sonnet |

---------------------------------------------------------------------------------------------------

## 10. Открытые вопросы к пользователю

**Решены 2026-10-02:** (1) hypridle — ЧИНИТЬ (dpms на Lua-синтаксис, затемнение до 10 %), правка конфига сделана до D3,
шаблон hypridle.conf (D3) берёт исправленный файл как golden; (2) автозапуск — модель A (свой список в settings.json →
`hyprland.start` в settings.lua; Telegram/Zen/Viber переезжают из hyprland.lua; мёртвые `~/.config/autostart/{org.telegram.desktop,ssh-add}.desktop` убрать).

Решения по умолчанию, которые можно переиграть без остановки работ: settings.json в репо (§2.3, вариант A);
окно — FloatingWindow (§2.8); бинд `SUPER+I`; рамки окон по умолчанию — «как сейчас» (циан→зелёный, не
палитра); свой мини-шаблонизатор вместо jinja2 (§3.3).

---------------------------------------------------------------------------------------------------

## 11. Ловушки для исполнителей

- QML: свойства вида `on` + Заглавная (`onSurface`) — это обработчики сигналов (цвета — `fg`/`fgVariant`/
  `primaryText`). Синглтон нельзя назвать `State`; не называть `Settings` (QtCore). `Region { item: … }` в
  PopupWindow 0.3.1 даёт пустую маску ввода — задавать x/y/width/height явно.
- Live-reload Quickshell ненадёжен для НОВЫХ файлов — после добавления перезапуск шелла пользователем.
  `pkill -f 'qs -p …'` из `!`-команды убивает собственную оболочку.
- IPC: точное число аргументов, код возврата 0 даже при ошибке; не называть функции `show`.
- `hyprctl dispatch` — только Lua-синтаксис (`hl.dsp.…`); старый (`dispatch exit`, `dispatch dpms off`)
  молча не работает.
- Не писать через симлинки rename-ом (заменит симлинк файлом) — писать в realpath.
- Профиль Zen: `~/.config/zen/smhkr7xv.Default (release)` — пробелы и скобки в пути.
- Obsidian vault'ы на `/mnt/data` (NTFS через fuseblk) — может быть не смонтирован.
- `qt6ct.conf` в репо содержит `~/...`; при деплое путь подставляется (`deploy.sh`) — patch-цель
  должна делать то же.
- GTK-альфы складываются по слоям: красим только «несущие» фоны (комментарий в gtk.css) — шаблон не должен
  добавлять фон вложенным виджетам. То же правило в Obsidian (обёртки — `transparent`).
- Из sandbox Claude: никаких запусков GUI (mpvpaper, hypridle, hyprpicker, qs) — CLI с `--no-exec`; реальный
  `eDP-1` не трогать (только headless-выходы); sudo недоступен.
- `gio mime` печатает заголовки на языке локали: при русской локали разбор по английским словам давал пустой список
  (вкладка «Приложения» была вся серая). Любые внешние команды, чей вывод парсится, — с `LC_ALL=C`; для списка приложений
  есть запасной путь — скан `.desktop` по `MimeType=` (mime.py).
- Текстовый ввод в попапах панели работает только в закреплённом попапе (`PopoutState.pin()` / `togglePinnedAt()` +
  `HyprlandFocusGrab` в `Popout.qml`) и если поле берёт фокус ПОСЛЕ получения клавиатуры (таймер ~60–80 мс): так сделаны пароль Wi-Fi
  (подтверждено пользователем) и поиск в меню приложений. Попытка закрепить попап по клику на уже сфокусированное поле (бывший ввод
  минут таймера) не печатала — у таймера оставлен набор кнопками +/−.
- NVIDIA: не трогать `VK_LOADER_DRIVERS_SELECT` и т.п. (CONTEXT п.24) — к настройкам экрана не относится.
