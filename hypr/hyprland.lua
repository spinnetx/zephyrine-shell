-- Migrated from hyprland.conf (hyprlang) to Lua on 2026-09-06.
-- Original preserved at hyprland.conf.pre-lua-migration-2026-09-06.bak
-- See https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

-- Универсальное автоопределение любого подключенного монитора с родным разрешением и автопозиционированием
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })


---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
-- Thunar вместо Nemo: он чище берёт GTK-тему без Cinnamon-специфичных
-- надстроек, поэтому лучше сливается с Material You палитрой,
-- чем Nemo. См. .config/Thunar/ и theme/gtk-adw-papirus.
local fileManager = "thunar"
-- Лаунчер и меню питания — свои, на Quickshell (my_zephyrine_conf/quickshell/{launcher,powermenu}),
-- вызываются через IPC: qs ... ipc call <launcher|powermenu|notifs> <toggle|open|close>.
local qsIpc       = "qs -p ${ZEPHYRINE_QS_DIR:-/usr/share/zephyrine/quickshell} ipc call "


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Плагин hyprglass (Liquid Glass вместо блюра на окнах; hyprnux/hyprglass v0.8.0,
    -- собран под Hyprland 0.56.2 вручную — после обновления hyprland пересобрать:
    -- git checkout <пин из hyprpm.toml> && make). Настройки — блок ниже; ключи плагина
    -- появляются только после загрузки, поэтому через пару секунд перечитываем конфиг.
    hl.exec_cmd("sh -c 'test -f $HOME/.local/share/hyprland/plugins/libhyprglass.so && hyprctl plugin load $HOME/.local/share/hyprland/plugins/libhyprglass.so && sleep 2 && hyprctl reload'")

    hl.exec_cmd("systemctl --user start hyprpolkitagent.service 2>/dev/null || true")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets,pkcs11,ssh 2>/dev/null || true")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user start xdg-desktop-portal-hyprland.service xdg-desktop-portal.service 2>/dev/null || true")

    -- hypridle с автоматическим поиском конфигурации
    hl.exec_cmd("sh -c 'if [ -f $HOME/.config/hypr/hypridle.conf ]; then hypridle; elif [ -f /usr/share/zephyrine/hypr/hypridle.conf ]; then hypridle -c /usr/share/zephyrine/hypr/hypridle.conf; fi'")

    -- Панель — собственный бар на Quickshell (quickshell/zephyrine). Лаунчер/меню питания — свои (IPC, см. binds).
    -- Обои — видео через mpvpaper (ниже).
    hl.exec_cmd("qs -p ${ZEPHYRINE_QS_DIR:-/usr/share/zephyrine/quickshell}")

    -- Лимиты Claude Code/Antigravity и свободное место на / и /mnt/data
    -- показывает бар (quickshell/components/Limits.qml, DiskSpace.qml,
    -- скрипт scripts/ai-usage-widget.sh).
    -- hl.exec_cmd("bluemon")

    -- Обои рабочего стола: скрипт берёт файл из симлинка центра настроек (~/.local/state/zephyrine/wallpaper-desktop),
    -- нет симлинка — прежнее japanese-night-village; mpvpaper внутри скрипта (exec), на всех мониторах.
    hl.exec_cmd("zephyrine-wallpaper-desktop")
    -- hl.exec_cmd("mpvpaper -l overlay -o \"no-audio --loop-playlist --hwdec=auto\" '*' \"$WALLPAPER\" &")


    -- adw-gtk3-dark + Papirus вместо Orchis: adw-gtk3 — порт GTK4/libadwaita
    -- стиля на GTK3, визуально гораздо ближе к скруглённому Material You виду,
    -- чем более старые темы вроде Orchis.
    -- Значения для dconf (тема GTK по режиму, иконки, курсор, шрифты) выставляет центр настроек: так выбранные там
    -- иконки не сбрасываются при каждом входе. Если CLI не отработал — прежние значения.
    hl.exec_cmd("zephyrine-settings apply --targets gsettings || { "
        .. "gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'; "
        .. "gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'; }")
    -- hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font 11'")
    -- hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'Inter 11'")

end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Укажите название вашей темы (например, Adwaita, Breeze, Bibata)
hl.env("XCURSOR_THEME", "Qogir")
hl.env("GTK_THEME", "adw-gtk3-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Confirmed against https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/ :
-- hl.env does NOT expand $VARNAME like the old env= directive did; os.getenv() is required instead.
-- SSH-агент: берем существующий SSH_AUTH_SOCK, либо проверяем сокет gpg-agent
if not os.getenv("SSH_AUTH_SOCK") then
    local gpg_sock = (os.getenv("XDG_RUNTIME_DIR") or "") .. "/gnupg/S.gpg-agent.ssh"
    local f = io.open(gpg_sock, "r")
    if f then
        f:close()
        hl.env("SSH_AUTH_SOCK", gpg_sock)
    end
end

-- Аппаратное ускорение видеокарт NVIDIA (наследуется из окружения, если активно)
if os.getenv("LIBVA_DRIVER_NAME") then
    hl.env("LIBVA_DRIVER_NAME", os.getenv("LIBVA_DRIVER_NAME"))
end
if os.getenv("__GLX_VENDOR_LIBRARY_NAME") then
    hl.env("__GLX_VENDOR_LIBRARY_NAME", os.getenv("__GLX_VENDOR_LIBRARY_NAME"))
end
if os.getenv("NVD_BACKEND") then
    hl.env("NVD_BACKEND", os.getenv("NVD_BACKEND"))
end

-- Multi-GPU (Aquamarine): если задана переменная AQ_DRM_DEVICES, передаем в композитор
if os.getenv("AQ_DRM_DEVICES") then
    hl.env("AQ_DRM_DEVICES", os.getenv("AQ_DRM_DEVICES"))
end
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("LIBVIRT_DEFAULT_URI", "qemu:///system") -- virsh/virt-install по умолчанию к системному libvirt


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 7,

        border_size = 2,

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#variable-types for info about colors
        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#blur
        blur = {
            enabled        = true,
            size           = 3,
            passes         = 1,

            ignore_opacity = true,
            vibrancy       = 0.1696,
        },
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
    animations = {
        enabled = true, -- yes, please :)
    },
})

-- Default curves, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/#curves
--        NAME,           X0,   Y0,   X1,   Y1
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Overshoot: eases past the target and settles back — gives windows/workspaces a livelier, "bouncy" feel.
-- Tweak the two middle points to taste; a good playground is https://cubic-bezier.com or easings.net.
hl.curve("overshoot", { type = "bezier", points = { {0.34, 1.56}, {0.64, 1} } })

-- Default animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
--          NAME,          ONOFF,        SPEED, CURVE,        [STYLE]
hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
-- Window open/close: popin with a slight overshoot bounce instead of a flat ease-out.
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "overshoot" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.5,  bezier = "overshoot", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2.6,  bezier = "quick",     style = "popin 85%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
-- Workspace switch: slide + cross-fade ("page flip" feel) with the same overshoot bounce.
-- The "20%" is how far windows travel before the destination workspace fully takes over — raise/lower to taste.
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3.8,  bezier = "overshoot", style = "slidefade 20%" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 3.8,  bezier = "overshoot", style = "slidefade 20%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3.2,  bezier = "overshoot", style = "slidefade 20%" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-- hyprglass: «стекло» вместо блюра. Значения ослаблены относительно дефолтов
-- (glass_opacity 1.0, dark.brightness 0.82, adaptive_dim 0.4), иначе окна kitty
-- выглядят тёмными и почти непрозрачными. Слои (Quickshell-бар) не трогаем.
if hl.plugin and hl.plugin.hyprglass then
    hl.plugin.hyprglass.config({
        glass_opacity = 0.7,
        dark = { brightness = 1.0, adaptive_dim = 0.1, saturation = 1.0 },
    })
end

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        -- pseudotile = true, -- Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#misc
hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
        session_lock_xray       = true,  -- рисовать слои под экраном блокировки (видео за hyprlock)
    },
})


---------------
---- INPUT ----
---------------

-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "pl,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:alt_shift_toggle",
        -- kb_options = "grp:win_space_toggle",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            disable_while_typing = true,
            natural_scroll       = true,
            scroll_factor        = 1.0,
            tap_and_drag         = true,
            -- tap_to_click      = false,
            clickfinger_behavior = true,
        },
    },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- KEYBINDINGS ----
---------------------

-- Submap для захвата сочетаний в центре настроек (settings/zsettings/binds.py): без биндов, поэтому клавиши идут в окно
-- настроек, а не перехватываются Hyprland. Включается/сбрасывается `zephyrine-settings binds capture|release`.
-- В submap один заведомо ничейный бинд (пустой submap Hyprland может не зарегистрировать); он же сбрасывает режим.
do
    local ok, err = pcall(hl.define_submap, "zp_capture", function()
        hl.bind("XF86Launch9", hl.dsp.submap("reset"))
    end)
    if not ok then
        hl.notification.create({ text = "Zephyrine: submap zp_capture не создан: " .. tostring(err), timeout = 15000 })
    end
end

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Экран блокировки — hyprlock с прозрачным фоном + видео-обои на слое overlay (scripts/lock-with-video.sh);
-- без misc.session_lock_xray (ниже) видео под lock-сюрфейсом не рисуется.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("zephyrine-lock"), { description = "zp:lock · Блокировка экрана" })

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal), { description = "zp:terminal · Терминал" })
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "zp:close · Закрыть окно" })
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"), { description = "Выйти из Hyprland" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "zp:files · Файловый менеджер" })
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "zp:float · Плавающее окно" })
-- Лаунчер: одиночное нажатие SUPER (по отпусканию), SUPER+Space и SUPER+R.
-- РИСК (не проверено с живой клавиатурой): если после SUPER+<клавиша> отпускание Super тоже
-- открывает лаунчер, закомментируй бинд Super_L — остаются SUPER+Space / SUPER+R.
hl.bind(mainMod .. " + Super_L", hl.dsp.exec_cmd(qsIpc .. "launcher toggle"), { release = true, description = "zp:launcher · Лаунчер" })
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(qsIpc .. "launcher toggle"), { description = "zp:launcher · Лаунчер" })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(qsIpc .. "launcher toggle"), { description = "zp:launcher · Лаунчер" })
-- Меню питания.
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(qsIpc .. "powermenu toggle"), { description = "zp:powermenu · Меню питания" })
-- Панель уведомлений/календарь (IPC-таргет notifs).
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(qsIpc .. "notifs toggle"), { description = "zp:notifs · Уведомления и календарь" })
-- Центр настроек Zephyrine (IPC-таргет settings). Бинд живёт здесь, а не в settings.lua:
-- должен работать, даже если сгенерированный файл сломан.
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(qsIpc .. "settings toggle"), { description = "zp:settings · Центр настроек" })
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty --class torrents -e tremc"), { description = "zp:torrents · Торренты" }) -- Торрент-клиент (tremc + transmission-daemon)
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Pseudo-тайлинг (dwindle)" }) -- dwindle
-- hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Сменить направление разделения (dwindle)" })

hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" }), { description = "Во весь экран" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }), { description = "Развернуть окно" })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }), { description = "Фокус влево" })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Фокус вправо" })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "Фокус вверх" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "Фокус вниз" })

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }), { description = "Рабочий стол " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Окно на рабочий стол " .. i })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "Скрытый рабочий стол (magic)" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Окно на скрытый рабочий стол" })

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Следующий рабочий стол (колесо)" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Предыдущий рабочий стол (колесо)" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true }, { description = "Перетащить окно мышью" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Изменить размер окна мышью" })

-- Имитация Cmd + Ctrl + 4 (выбор области и переход в редактор)
hl.bind(mainMod .. " + CTRL + 4", hl.dsp.exec_cmd("grim -g \"$(slurp)\" -t ppm - | satty --filename - --fullscreen"), { description = "zp:shot-area · Скриншот области" })

-- Имитация Cmd + Ctrl + 3 (весь экран и переход в редактор)
hl.bind(mainMod .. " + CTRL + 3", hl.dsp.exec_cmd("grim -t ppm - | satty --filename - --fullscreen"), { description = "zp:shot-full · Скриншот экрана" })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Громкость +" })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true }, { description = "Громкость −" })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, repeating = true }, { description = "Выключить звук" })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true, repeating = true }, { description = "Выключить микрофон" })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                   { locked = true, repeating = true }, { description = "Яркость экрана +" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                   { locked = true, repeating = true }, { description = "Яркость экрана −" })

-- Управление подсветкой клавиатуры
hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -d \":white:kbd_backlight\" set 33%+"), { locked = true, repeating = true, description = "Подсветка клавиатуры +" })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d \":white:kbd_backlight\" set 33%-"), { locked = true, repeating = true, description = "Подсветка клавиатуры −" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true }, { description = "Следующий трек" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Пауза / воспроизведение" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Пауза / воспроизведение" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true }, { description = "Предыдущий трек" })

-- Кнопка питания открывает собственное меню питания (Quickshell, IPC powermenu).
hl.bind("XF86PowerOff", hl.dsp.exec_cmd(qsIpc .. "powermenu toggle"), { locked = true, description = "Меню питания (кнопка питания)" })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/ for workspace rules

-- Example window rules that are useful

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Прозрачность приложений теперь по умолчанию делается средствами самого
-- приложения (GTK-тема/gtk.css для Nemo, CSS-сниппет + флаги Electron для
-- Obsidian), а не общим Hyprland window-rule opacity — так меньше разъезжается
-- рендер (тени/скролл/видео внутри приложения). Исключение — Claude Desktop и
-- Antigravity: это закрытые Electron-приложения без пользовательских
-- CSS-хуков, поэтому для них window-rule остаётся единственным рычагом.

-- Claude Desktop
hl.window_rule({
    name    = "claude-transparency",
    match   = { class = "com.anthropic.Claude" },
    opacity = "0.90 override 0.85 override",
})

-- Antigravity IDE
hl.window_rule({
    name    = "antigravity-transparency",
    match   = { class = "(?i)(antigravity.*)" },
    opacity = "0.92 override 0.86 override",
})

-- Thunar (файловый менеджер): основная прозрачность — через
-- ~/.config/gtk-3.0/gtk.css + тема adw-gtk3-dark. GTK-alpha в теме не всегда
-- покрывает 100% поверхностей (тени, рамки), поэтому здесь лёгкая подстраховка
-- почти без визуального эффекта, а не полноценная прозрачность.
hl.window_rule({
    name    = "thunar-transparency-fallback",
    match   = { class = "[Tt]hunar" },
    opacity = "0.95 override 0.92 override",
})

-- Окно центра настроек Zephyrine (FloatingWindow из Quickshell, DESIGN §2.8): плавающее,
-- по центру, стартовый размер 1040x700. Заголовок окна — "Zephyrine · Настройки".
hl.window_rule({
    name  = "zephyrine-settings",
    match = { title = "^Zephyrine · Настройки$" },

    float  = true,
    size   = "1040 700",
    center = true,
})

-- Отключает принудительное масштабирование для XWayland приложений
hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

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
