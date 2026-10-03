pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Свободное место на / и Config.dataMount через df (раз в Config.diskPollMs).
Singleton {
    id: root

    // { mounted, avail, size } в байтах
    property var rootFs: ({ mounted: false, avail: 0, size: 0 })
    property var dataFs: ({ mounted: false, avail: 0, size: 0 })

    readonly property real gib: 1024 * 1024 * 1024

    function fmt(bytes) {
        const g = bytes / gib;
        return g >= 1000 ? (g / 1024).toFixed(1) + "T" : Math.floor(g) + "G";
    }

    // "ok" | "warning" | "critical" | "none"
    function level(fs) {
        if (!fs.mounted)
            return "none";
        const g = fs.avail / gib;
        return g < Config.diskCritGiB ? "critical" : g < Config.diskWarnGiB ? "warning" : "ok";
    }

    function tip(fs, label) {
        if (!fs.mounted)
            return label + ": не смонтирован";
        const used = fs.size - fs.avail;
        return label + "\nЗанято: " + fmt(used) + " из " + fmt(fs.size) + " (" + Math.round(used * 100 / fs.size) + "%)\nСвободно: " + fmt(fs.avail);
    }

    function parse(text) {
        const entries = [];
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/);
            if (m)
                entries.push({ avail: Number(m[1]), size: Number(m[2]), target: m[3].trim() });
        }
        if (entries.length > 0)
            rootFs = { mounted: true, avail: entries[0].avail, size: entries[0].size };
        // Если /mnt/data не смонтирован, df печатает строку с целью "/" (или вообще ошибку).
        const d = entries.length > 1 ? entries[1] : null;
        dataFs = (d && d.target !== "/")
            ? { mounted: true, avail: d.avail, size: d.size }
            : { mounted: false, avail: 0, size: 0 };
    }

    Process {
        id: proc
        command: ["df", "-B1", "--output=avail,size,target", "/", Config.dataMount]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: Config.diskPollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }
}
