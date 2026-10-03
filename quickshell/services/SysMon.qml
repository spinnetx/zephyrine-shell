pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Мониторинг системы: CPU по ядрам, память, сеть. Один опрос на все мониторы (синглтон),
// раз в Config.sysMonPollMs, читаются /proc/stat, /proc/meminfo, /proc/net/dev (+ частота,
// температура, loadavg). Видеокарту (NVIDIA) отложили: позже — отдельный сервис Gpu.qml
// и компонент в баре, SysMon трогать не придётся.
Singleton {
    id: root

    // --- CPU ---
    property var cores: []            // загрузка каждого логического ядра, 0..1
    property real cpuTotal: 0         // суммарная загрузка, 0..1
    property real cpuFreqMHz: 0       // средняя текущая частота
    property real cpuTempC: -1        // k10temp Tctl, -1 если нет
    property var loadAvg: [0, 0, 0]
    property var _cpuPrev: null       // прошлые { total, idle } по строкам cpu, cpu0..

    // --- Память (байты) ---
    property real memTotal: 0
    property real memUsed: 0          // MemTotal - MemAvailable
    property real memCached: 0        // Cached + Buffers + SReclaimable
    property real memFree: 0
    property real swapTotal: 0
    property real swapUsed: 0
    readonly property real memFrac: memTotal > 0 ? memUsed / memTotal : 0

    // --- Сеть (байт/с; суммы по физическим интерфейсам, без lo/docker/veth/virbr/br-) ---
    property real rxRate: 0
    property real txRate: 0
    property real rxSession: 0        // всего за сессию шелла
    property real txSession: 0
    property var ifaces: []           // [{ name, rx, tx, rxTotal, txTotal }]
    property var rxHist: []           // последние Config.netHistorySize значений
    property var txHist: []
    property var _netPrev: null       // { t, map: name -> [rx, tx] }
    property var _netBase: ({})       // name -> [rx, tx] при первом наблюдении

    // Одна строка /proc/stat (числа без имени) → { total, idle }
    function _cpuLine(f) {
        let total = 0;
        for (let i = 0; i < Math.min(f.length, 8); i++)
            total += f[i];
        return { total: total, idle: f[3] + (f[4] ?? 0) };
    }

    function parseStat(text) {
        const cur = [];
        for (const line of text.split("\n")) {
            if (!line.startsWith("cpu"))
                break;
            // [0] = "cpu" | "cpuN"
            cur.push(_cpuLine(line.split(/\s+/).slice(1).map(Number)));
        }
        const prev = _cpuPrev;
        _cpuPrev = cur;
        if (!prev || prev.length !== cur.length)
            return;
        const frac = cur.map((c, i) => {
            const dt = c.total - prev[i].total;
            return dt > 0 ? Math.max(0, Math.min(1, 1 - (c.idle - prev[i].idle) / dt)) : 0;
        });
        cpuTotal = frac[0];
        cores = frac.slice(1);
    }

    function parseMem(text) {
        const m = {};
        for (const line of text.split("\n")) {
            const r = line.match(/^(\w+):\s+(\d+)/);
            if (r)
                m[r[1]] = Number(r[2]) * 1024;
        }
        memTotal = m.MemTotal ?? 0;
        memUsed = memTotal - (m.MemAvailable ?? 0);
        memCached = (m.Cached ?? 0) + (m.Buffers ?? 0) + (m.SReclaimable ?? 0);
        memFree = m.MemFree ?? 0;
        swapTotal = m.SwapTotal ?? 0;
        swapUsed = swapTotal - (m.SwapFree ?? 0);
    }

    function ignoredIface(n) {
        return n === "lo" || /^(docker|veth|virbr|br-)/.test(n);
    }

    function parseNet(text) {
        const now = Date.now();
        const map = {};
        for (const line of text.split("\n")) {
            // iface: rx_bytes + 7 полей, затем tx_bytes
            const r = line.match(/^\s*([^:\s]+):\s*(\d+)(?:\s+\d+){7}\s+(\d+)/);
            if (r && !ignoredIface(r[1]))
                map[r[1]] = [Number(r[2]), Number(r[3])];
        }
        const prev = _netPrev;
        _netPrev = { t: now, map: map };
        for (const n in map)
            if (!(n in _netBase))
                _netBase[n] = map[n];
        if (!prev)
            return;
        const dt = Math.max(0.2, (now - prev.t) / 1000);
        const list = [];
        let rx = 0, tx = 0, rxS = 0, txS = 0;
        for (const n in map) {
            const p = prev.map[n] ?? map[n];
            const r = Math.max(0, (map[n][0] - p[0]) / dt);
            const t = Math.max(0, (map[n][1] - p[1]) / dt);
            const rt = map[n][0] - _netBase[n][0];
            const tt = map[n][1] - _netBase[n][1];
            list.push({ name: n, rx: r, tx: t, rxTotal: rt, txTotal: tt });
            rx += r;
            tx += t;
            rxS += rt;
            txS += tt;
        }
        ifaces = list;
        rxRate = rx;
        txRate = tx;
        rxSession = rxS;
        txSession = txS;
        const cap = Config.netHistorySize;
        rxHist = rxHist.concat([rx]).slice(-cap);
        txHist = txHist.concat([tx]).slice(-cap);
    }

    function parseFreq(text) {
        let sum = 0, n = 0;
        const re = /^cpu MHz\s*:\s*([\d.]+)/gm;
        let m;
        while ((m = re.exec(text)) !== null) {
            sum += Number(m[1]);
            n++;
        }
        cpuFreqMHz = n > 0 ? sum / n : 0;
    }

    // --- Форматирование (общее для бара и попапов) ---
    // Скорость: короткая запись B/K/M/G (степени 1024), не длиннее 4 символов.
    function fmtRate(bps) {
        const units = ["B", "K", "M", "G"];
        let v = bps, u = 0;
        while (v >= 1000 && u < units.length - 1) {
            v /= 1024;
            u++;
        }
        return (u > 0 && v < 10 ? v.toFixed(1) : Math.round(v).toString()) + units[u];
    }
    function fmtBytes(b) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let v = b, u = 0;
        while (v >= 1024 && u < units.length - 1) {
            v /= 1024;
            u++;
        }
        return (u < 2 ? Math.round(v) : v.toFixed(1)) + " " + units[u];
    }
    function fmtGiB(b) {
        return (b / (1024 * 1024 * 1024)).toFixed(1) + "G";
    }
    // Цвет нагрузки 0..1: primary → tertiary → error.
    function loadColor(f) {
        return f >= Config.cpuCrit ? Colors.error : f >= Config.cpuWarn ? Colors.tertiary : Colors.primary;
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: root.parseStat(text())
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: root.parseMem(text())
    }
    FileView {
        id: netFile
        path: "/proc/net/dev"
        onLoaded: root.parseNet(text())
    }
    FileView {
        id: freqFile
        path: "/proc/cpuinfo"
        onLoaded: root.parseFreq(text())
    }
    FileView {
        id: loadFile
        path: "/proc/loadavg"
        onLoaded: root.loadAvg = text().split(" ").slice(0, 3).map(Number)
    }
    FileView {
        id: tempFile
        path: tempProc.path
        onLoaded: root.cpuTempC = Number(text()) / 1000
    }

    // Путь к температуре k10temp (номер hwmonN меняется между загрузками) — ищем один раз.
    Process {
        id: tempProc
        property string path: ""
        running: true
        command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do [ \"$(cat $d/name 2>/dev/null)\" = k10temp ] && echo $d/temp1_input && break; done"]
        stdout: StdioCollector {
            onStreamFinished: tempProc.path = text.trim()
        }
    }

    Timer {
        interval: Config.sysMonPollMs
        running: Quickshell.screens.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            netFile.reload();
            freqFile.reload();
            loadFile.reload();
            if (tempProc.path !== "")
                tempFile.reload();
        }
    }
}
