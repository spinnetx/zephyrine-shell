pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Видеокарта NVIDIA (гибридный ноутбук, muxless). ГЛАВНОЕ ПРАВИЛО: НЕ БУДИТЬ КАРТУ.
// Раз в Config.gpuStatusPollMs читаем ТОЛЬКО sysfs: power/runtime_status и симлинк driver
// (их чтение не вызывает runtime resume; vendor/class кэшируются ядром). К драйверу
// (nvidia-smi, /proc/driver/nvidia, /dev/nvidia*, hwmon) обращаемся лишь когда статус "active"
// и драйвер nvidia; как только статус стал suspended/suspending — запросы прекращаются, значения сброшены.
// Синглтон: один опрос на все мониторы.
//
// state: "none" (карты/драйвера/nvidia-smi нет — пилюлю скрываем) | "sleep" (runtime suspend) |
//        "vfio" (проброшена в ВМ) | "active" | "error" (nvidia-smi не ответил, повтор с паузой)
Singleton {
    id: root

    // --- Состояние из sysfs ---
    property string addr: ""              // PCI-адрес, напр. 0000:01:00.0
    property string powerStatus: ""       // active | suspended | suspending | resuming | unsupported
    property string driver: ""            // nvidia | vfio-pci | "" ...
    property bool smiPresent: false       // есть ли nvidia-smi в PATH
    property bool smiError: false

    readonly property string state: {
        if (addr === "" || !smiPresent && driver !== "vfio-pci")
            return "none";
        if (driver === "vfio-pci")
            return "vfio";
        if (driver !== "nvidia")
            return "none";
        if (powerStatus === "active")
            return smiError ? "error" : "active";
        if (powerStatus === "suspended" || powerStatus === "suspending" || powerStatus === "resuming")
            return "sleep";
        return "none";
    }

    // --- Метрики (только в state active; иначе сброшены) ---
    property string name: ""              // имя держим и во сне (в sysfs его нет)
    property bool loaded: false           // пришёл хотя бы один ответ nvidia-smi
    property real util: 0                 // загрузка GPU, 0..1
    property real memUtil: 0              // загрузка контроллера памяти, 0..1
    property real memUsedMiB: 0
    property real memTotalMiB: 0
    property real tempC: -1
    property real powerW: -1
    property real clockMHz: -1
    property real clockMaxMHz: -1
    property real fanPct: -1              // -1 = [N/A] (на ноутбуках обычно так)
    property string pstate: ""
    property var apps: []                 // [{ pid, name, memMiB }], только при открытом попапе
    readonly property real memFrac: memTotalMiB > 0 ? memUsedMiB / memTotalMiB : 0

    property double _lastSmi: 0
    property double _lastApps: 0
    property double _errorAt: 0

    // --- Разбор ---
    function num(s) {
        const v = parseFloat(s);
        return isFinite(v) ? v : -1;
    }

    // "0000:01:00.0 active nvidia 1" → поля состояния; пустой вывод = карты нет.
    function parseStatus(text) {
        const f = text.trim().split(/\s+/);
        if (f.length < 1 || f[0] === "") {
            addr = "";
            powerStatus = "";
            driver = "";
            return;
        }
        addr = f[0];
        powerStatus = f[1] ?? "";
        driver = (f[2] ?? "") === "-" ? "" : f[2] ?? "";
        smiPresent = (f[3] ?? "0") === "1";
    }

    // Одна строка csv (noheader,nounits) → true, если разобралась.
    function parseSmi(text) {
        const line = text.trim().split("\n")[0] ?? "";
        const p = line.split(",").map(s => s.trim());
        if (p.length < 11)
            return false;
        const util = num(p[1]);
        if (util < 0)
            return false;
        name = p[0];
        root.util = util / 100;
        memUtil = Math.max(0, num(p[2])) / 100;
        memUsedMiB = Math.max(0, num(p[3]));
        memTotalMiB = Math.max(0, num(p[4]));
        tempC = num(p[5]);
        powerW = num(p[6]);
        clockMHz = num(p[7]);
        clockMaxMHz = num(p[8]);
        fanPct = num(p[9]);
        pstate = /^P\d+$/.test(p[10]) ? p[10] : "";
        loaded = true;
        return true;
    }

    // "pid, process_name, used_memory" по строке.
    function parseApps(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const p = line.split(",").map(s => s.trim());
            if (p.length < 3 || !/^\d+$/.test(p[0]))
                continue;
            const nm = p.slice(1, -1).join(",");
            out.push({ pid: Number(p[0]), name: nm.split("/").pop(), memMiB: Math.max(0, num(p[p.length - 1])) });
        }
        out.sort((a, b) => b.memMiB - a.memMiB);
        apps = out;
    }

    function resetMetrics() {
        loaded = false;
        util = 0;
        memUtil = 0;
        memUsedMiB = 0;
        memTotalMiB = 0;
        tempC = -1;
        powerW = -1;
        clockMHz = -1;
        clockMaxMHz = -1;
        fanPct = -1;
        pstate = "";
        apps = [];
        smiError = false;
    }

    // --- Форматирование ---
    function loadColor(f) {
        return f >= Config.gpuCrit ? Colors.error : f >= Config.gpuWarn ? Colors.tertiary : Colors.primary;
    }
    function tempColor(c) {
        return c >= Config.gpuTempCritC ? Colors.error : c >= Config.gpuTempWarnC ? Colors.tertiary : Colors.fg;
    }
    function fmtMiB(m) {
        return (m / 1024).toFixed(1) + " ГиБ";
    }

    // Состояние ушло из active: гасим запросы и сбрасываем значения.
    onStateChanged: {
        if (state !== "active" && state !== "error") {
            smiProc.running = false;
            appsProc.running = false;
            resetMetrics();
        }
    }

    // Вызывается после каждого чтения статуса (и при открытии попапа): не больше одного запроса
    // за раз, метрики — не чаще Config.gpuSmiMinMs, процессы — только при открытом попапе.
    function poll() {
        if (powerStatus !== "active" || driver !== "nvidia" || !smiPresent)
            return;
        const now = Date.now();
        if (smiProc.running || appsProc.running)
            return;
        if (smiError && now - _errorAt < Config.gpuErrorBackoffMs)
            return;
        if (now - _lastSmi >= Config.gpuSmiMinMs) {
            _lastSmi = now;
            smiProc.running = true;
        } else if (PopoutState.kind === "gpu" && !smiError && now - _lastApps >= Config.gpuAppsPollMs) {
            _lastApps = now;
            appsProc.running = true;
        }
    }

    Connections {
        target: PopoutState
        function onKindChanged() {
            if (PopoutState.kind === "gpu")
                root._lastApps = 0;
        }
    }

    // Статус: только sysfs. Адрес ищем динамически (vendor 0x10de, класс 0x03xxxx — VGA/3D, не аудио .1).
    Process {
        id: statusProc
        command: ["sh", "-c", `for d in /sys/bus/pci/devices/*; do
            [ "$(cat $d/vendor 2>/dev/null)" = 0x10de ] || continue
            case "$(cat $d/class 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
            s=$(cat $d/power/runtime_status 2>/dev/null)
            drv=$(basename "$(readlink $d/driver 2>/dev/null)")
            command -v nvidia-smi >/dev/null 2>&1 && smi=1 || smi=0
            echo "$(basename $d) \${s:-unsupported} \${drv:--} $smi"
            break
        done`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseStatus(text);
                root.poll();
            }
        }
    }

    Process {
        id: smiProc
        command: ["timeout", String(Config.gpuSmiTimeoutS), "nvidia-smi",
            "--query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,clocks.gr,clocks.max.gr,fan.speed,pstate",
            "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Результат, пришедший уже после ухода карты в сон, выбрасываем.
                if (root.powerStatus !== "active")
                    return;
                if (root.parseSmi(text)) {
                    root.smiError = false;
                } else {
                    root.smiError = true;
                    root._errorAt = Date.now();
                }
            }
        }
    }

    Process {
        id: appsProc
        command: ["timeout", String(Config.gpuSmiTimeoutS), "nvidia-smi",
            "--query-compute-apps=pid,process_name,used_memory", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.powerStatus === "active")
                    root.parseApps(text);
            }
        }
    }

    Timer {
        interval: Config.gpuStatusPollMs
        running: Quickshell.screens.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProc.running)
                statusProc.running = true;
        }
    }
}
