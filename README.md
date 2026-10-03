# Zephyrine Shell

> **Zephyrine Shell** — современная, элегантная графическая оболочка рабочего стола для Linux (Wayland), построенная на связке **Hyprland** и **Quickshell**.

Оболочка ориентирована на визуальную согласованность, плавные анимации, эффекты стекла и удобство повседневной работы.

---

## Особенности

- 🪟 **Hyprland + Quickshell**: Легковесная, отзывчивая Wayland-среда с аппаратным ускорением и эффектами Liquid Glass / Blur.
- 🎨 **Единая палитра и темы**: Встроенный генератор тем на лету применяет выбранные цвета акцента и палитру ко всем используемым приложениям:
  - **GTK 3 / GTK 4** (Adwaita / CSS оверлеи)
  - **Qt 6** (qt6ct + Fusion)
  - **Kitty** (терминал со стеклянной подложкой)
  - **Zed Editor**
  - **Zathura** (документы и PDF)
  - **Obsidian** (заметки)
  - **Thunderbird** (почтовый клиент)
  - **Zen Browser**
- ⚙️ **Центр управления (Zephyrine Settings)**:
  - Удобный графический интерфейс (`SUPER+I`) и мощный CLI `zephyrine-settings`.
  - Управление обоями (видео и статика через mpvpaper).
  - Настройка звука, профилей питания, мониторов и рабочих столов.
  - Управление Wi-Fi и Bluetooth с автоматическим агентом сопряжения.
  - Настройка сочетаний клавиш и управляемый автозапуск приложений.
- 🔔 **Встроенный сервер уведомлений и лаунчер**:
  - Тосты уведомлений, история уведомлений, режим «Не беспокоить» (DND).
  - Быстрый поиск и лаунчер приложений с поддержкой истории и локализованных имен.
  - Полнофункциональное меню питания и OSD громкости / яркости.
- 🔒 **Экран входа и блокировки**:
  - Тема SDDM в едином стиле Zephyrine с видеофоном и часами.
  - Экран блокировки Hyprlock с бесшовным видеофоном на слое overlay.

---

## Быстрый старт и установка

### Системные требования
- **ОС**: Arch Linux, EndeavourOS или совместимый дистрибутив Linux.
- **Wayland композитор**: Hyprland (версия 0.55+ с поддержкой Lua).
- **Интерфейс**: Quickshell (`quickshell` или `quickshell-git`).
- **Зависимости**: `mpvpaper`, `socat`, `jq`, `python`, `qt6ct`, `papirus-icon-theme`.

---

### Способ 1: Установка пакетом Arch Linux / EndeavourOS (Рекомендуется)

```bash
git clone https://github.com/spinnetx/zephyrine-shell.git
cd zephyrine-shell
makepkg -si
```

---

### Способ 2: Установка через инсталлятор

```bash
git clone https://github.com/spinnetx/zephyrine-shell.git
cd zephyrine-shell
./install.sh --system --sddm
```

---

### Способ 3: Сборка через Makefile

```bash
git clone https://github.com/spinnetx/zephyrine-shell.git
cd zephyrine-shell

# Системная установка (в /usr):
sudo make install

# Или пользовательская установка (в ~/.local):
make user-install
```

---

## Запуск сессии

1. **Через дисплейный менеджер (SDDM / GDM)**:  
   При входе в систему выберите сессию **Zephyrine**.
2. **Вручную из TTY**:  
   ```bash
   zephyrine-session
   ```

---

## Основные горячие клавиши

| Сочетание клавиш | Действие |
|---|---|
| `SUPER` или `SUPER + Space` | Лаунчер приложений |
| `SUPER + I` | Центр управления Zephyrine |
| `SUPER + N` | Центр уведомлений и календарь |
| `SUPER + L` | Блокировка экрана (Hyprlock с видео) |
| `SUPER + Escape` | Меню питания (выключение, перезагрузка, сон) |
| `SUPER + Q` | Терминал Kitty |
| `SUPER + E` | Файловый менеджер Thunar |
| `SUPER + C` | Закрыть активное окно |
| `SUPER + V` | Переключить режим плавающего окна |
| `SUPER + 1..9` | Переключение рабочих столов |
| `SUPER + SHIFT + 1..9` | Перемещение окна на рабочий стол |

---

## Структура проекта

```
zephyrine-shell/
├── bin/                 # Бинарники сессии и обертки CLI (zephyrine-session, zephyrine-settings)
├── desktop/             # Файлы сессии Wayland и десктоп-записи
├── quickshell/          # Исходный код интерфейса (бар, попапы, лаунчер, центр настроек)
├── settings/            # Модули бекенда настроек zsettings, шаблоны тем, targets.json
├── hypr/                # Конфигурация Hyprland, hypridle, hyprlock
├── themes/              # Темы приложений (GTK, Qt6, Kitty, Zed, Zathura, Obsidian, Zen)
├── sddm/                # Тема экрана входа SDDM
├── scripts/             # Внутренние скрипты (видеообои, блокировка, виджеты)
├── assets/              # Медиа-ресурсы и дефолтные обои
├── Makefile             # Системная сборка и установка
├── install.sh           # Интерактивный установщик
└── PKGBUILD             # Пакет для Arch Linux / AUR
```

---

## Удаление

### Через install.sh:

```bash
# Стандартное удаление:
./install.sh --uninstall

# Полное удаление с очисткой настроек (~/.config/zephyrine) и кэша:
./install.sh --uninstall --purge

# Если была установлена тема SDDM — откат темы:
./install.sh --uninstall --sddm
```

### Через Makefile:

```bash
# Удаление системной установки:
sudo make uninstall

# Удаление пользовательской установки:
make user-uninstall
```

---

## Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
