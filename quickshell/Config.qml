pragma Singleton

import QtQuick
import Quickshell

// Все константы в одном месте: команды, размеры, интервалы.
Singleton {
    id: root

    // --- Команды ---
    // Кнопка питания открывает своё меню (powermenu/PowerMenu.qml, состояние — services/Overlays.qml).
    // Блокировка экрана (видео-заставка hyprlock).
    readonly property var lockCommand: [Quickshell.env("HOME") + "/my_zephyrine_conf/scripts/lock-with-video.sh"]
    // Скрипт лимитов ИИ (аргумент: claude | agy), выдаёт JSON {text,tooltip,class}.
    readonly property string aiScript: Quickshell.env("HOME") + "/my_zephyrine_conf/scripts/ai-usage-widget.sh"
    // Точка монтирования второго диска (если не смонтирован — показываем «—»).
    readonly property string dataMount: "/mnt/data"

    // Центр настроек (settings/): корень репозитория и CLI — единственный писатель настроек.
    readonly property string zephyrineRoot: Quickshell.env("HOME") + "/my_zephyrine_conf"
    readonly property string settingsCli: zephyrineRoot + "/settings/bin/zephyrine-settings"

    // Переключение воркспейса: синтаксис Lua-dispatch Hyprland 0.56 (подтверждён).
    function workspaceCommand(n) {
        return ["hyprctl", "dispatch", "hl.dsp.focus({workspace=" + n + "})"];
    }

    // --- Размеры ---
    // Бар «плавающий»: отступ от верхнего/боковых краёв, скруглённый со всех
    // сторон (у Caelestia бар тоже отделён от края и имеет скруглённый фон).
    readonly property int barHeight: 40
    readonly property int barMargin: 6
    readonly property int barRadius: Prefs.radius + 2
    // Положение панели (Prefs: bar.position) и толщина вертикальной панели (слева/справа).
    readonly property string barPosition: Prefs.barPosition
    readonly property bool barVertical: barPosition === "left" || barPosition === "right"
    readonly property int barThickness: 48
    // Размер панели поперёк экрана вместе с отступом от края: столько резервируется у окон и отступают попапы/тосты.
    readonly property int barExtent: (barVertical ? barThickness : barHeight) + barMargin
    readonly property int pillHeight: 28
    readonly property int pillRadius: Prefs.radius
    readonly property int pillPadding: 10
    readonly property int spacing: 6
    readonly property int workspaceCount: 10
    readonly property int titleMaxWidth: 260
    readonly property int mediaMaxWidth: 280

    // --- Уведомления и календарь ---
    readonly property int notifMax: Prefs.historyMax           // максимум в истории
    readonly property int notifListMaxHeight: 240 // высота списка уведомлений в попапе часов (дальше — скролл)
    // Русская локаль для дат: системные LC_TIME в этой сессии — pl_PL, поэтому задаём явно.
    readonly property var locale: Qt.locale("ru_RU")

    // --- Тосты, DND, OSD ---
    readonly property int toastMax: 5             // максимум карточек в стеке
    readonly property int toastWidth: 380
    readonly property int toastGap: 8             // зазор между карточками и до бара
    readonly property int toastDefaultMs: Prefs.toastMs    // если отправитель не задал expireTimeout (0 / -1)
    readonly property int toastMessageMs: 3000    // тосты шелла (Toaster)
    readonly property bool dndAllowCritical: Prefs.dndAllowCritical // в режиме «не беспокоить» critical-тосты всё равно показываются
    readonly property int osdMs: 1500             // сколько висит OSD громкости/яркости
    readonly property int osdBottomMargin: 60
    readonly property int brightnessPollMs: 300   // опрос яркости (sysfs не шлёт надёжных событий)

    // --- Внешний вид ---
    readonly property string fontFamily: Prefs.shellFont
    readonly property int fontSize: Prefs.shellFontSize
    readonly property int iconSize: Prefs.shellFontSize + 3
    readonly property real barAlpha: Prefs.glassAlpha    // чуть плотнее, чем 0.82 у Caelestia: читаемость над яркими обоями
    readonly property real pillAlpha: Prefs.surfaceAlpha
    readonly property int animMs: 200
    readonly property int animEasing: Easing.OutCubic
    readonly property int tipDelayMs: 350
    // Выпадающие попапы (hover): задержка перед открытием/закрытием, размеры карточки.
    readonly property int popoutOpenDelayMs: 120
    readonly property int popoutCloseDelayMs: 250
    readonly property int popoutRadius: Prefs.radius + 2
    readonly property int popoutPadding: 12
    readonly property int popoutGap: 4         // зазор между баром и карточкой
    readonly property int popoutMaxHeight: 640 // высота окна-носителя (карточка внутри не выше)
    readonly property int popoutMaxWidth: 460  // ширина окна-носителя у вертикальной панели

    // --- Интервалы опроса (мс) ---
    readonly property int aiPollMs: 120000
    readonly property int diskPollMs: 30000
    readonly property int netPollMs: 8000
    readonly property int wifiListPollMs: 15000 // автообновление списка Wi-Fi, пока попап открыт
    readonly property int sysMonPollMs: 1000    // SysMon: CPU/память/сеть (один опрос на все мониторы)
    readonly property int gpuStatusPollMs: 2500 // Gpu: опрос ТОЛЬКО sysfs (runtime_status/driver) — карту не будит
    readonly property int gpuSmiMinMs: 2000     // Gpu: nvidia-smi не чаще (и только при runtime_status == active)
    readonly property int gpuSmiTimeoutS: 5     // таймаут nvidia-smi, сек
    readonly property int gpuAppsPollMs: 3000   // список процессов на карте — только при открытом попапе
    readonly property int gpuErrorBackoffMs: 30000 // после ошибки nvidia-smi пауза перед повтором
    readonly property int netHistorySize: 60    // точек истории скорости сети (≈ секунд)

    // --- Пороги ---
    readonly property real memWarn: 0.80        // память: доля «занято» — предупреждение / критично
    readonly property real memCrit: 0.90
    readonly property real cpuWarn: 0.60        // нагрузка ядра: primary → tertiary → error
    readonly property real cpuCrit: 0.85
    readonly property real tempWarnC: 80        // температура CPU, °C
    readonly property real tempCritC: 90
    readonly property real gpuWarn: 0.60        // загрузка GPU: primary → tertiary → error
    readonly property real gpuCrit: 0.85
    readonly property real gpuTempWarnC: 80     // температура GPU, °C
    readonly property real gpuTempCritC: 90
    readonly property real diskWarnGiB: 20
    readonly property real diskCritGiB: 10
    readonly property real batteryCritical: Prefs.batteryCritical
    readonly property real volumeMax: Prefs.volumeMax
    readonly property real volumeStep: Prefs.volumeStep

    // --- Иконки: Nerd Font (Material Design, U+F0xxx) ---
    function g(cp) { return String.fromCodePoint(cp); }
    readonly property var icons: ({
        power: g(0xF0425),
        music: g(0xF075A),
        keyboard: g(0xF030C),
        volHigh: g(0xF057E), volMed: g(0xF0580), volLow: g(0xF057F), volOff: g(0xF0581), volMute: g(0xF075F),
        wifi1: g(0xF091F), wifi2: g(0xF0922), wifi3: g(0xF0925), wifi4: g(0xF0928), wifiOff: g(0xF05AA),
        ethernet: g(0xF0200),
        bt: g(0xF00AF), btConnected: g(0xF00B1), btOff: g(0xF00B2),
        cpu: g(0xF061A), gpu: g(0xF08AE), memory: g(0xF035B), arrowDown: g(0xF0045), arrowUp: g(0xF005D),
        bell: g(0xF009A), bellOff: g(0xF009B), bellOutline: g(0xF009C), close: g(0xF0156), trash: g(0xF01B4),
        chevronLeft: g(0xF0141), thermometer: g(0xF050F), chip: g(0xF061A),
        lock: g(0xF033E), eye: g(0xF06D0), eyeOff: g(0xF06D1), refresh: g(0xF0450), check: g(0xF012C), settings: g(0xF0493),
        headphones: g(0xF02CB), speaker: g(0xF04C3), mic: g(0xF036C), micOff: g(0xF036D), chevronRight: g(0xF0142),
        search: g(0xF0349), logout: g(0xF0343), sleep: g(0xF0904), restart: g(0xF0709),
        info: g(0xF02FD), alert: g(0xF0026), alertCircle: g(0xF0028), checkCircle: g(0xF05E0), brightness: g(0xF00DF),
        palette: g(0xF03D8), monitor: g(0xF0379),
        apps: g(0xF003B), timer: g(0xF051B), play: g(0xF040A), pause: g(0xF03E4), stop: g(0xF04DB), weather: g(0xF0595),
        battery: g(0xF0079), batteryLow: g(0xF007A), batteryCharging: g(0xF0084), batteryOutline: g(0xF008E)
    })
}
