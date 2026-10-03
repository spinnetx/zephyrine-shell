pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Сеть через nmcli (LC_ALL=C — иначе состояния локализованы). kind: wifi | ethernet | none.
Singleton {
    id: root

    property string kind: "none"
    property string ssid: ""
    property int signal: 0

    // Внеочередное обновление (после подключения/переключения радио).
    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    function parse(text) {
        const parts = text.split("---");
        let wifiUp = false, ethUp = false;
        for (const line of parts[0].split("\n")) {
            const f = line.split(":");
            if (f.length < 2 || !f[1].startsWith("connected"))
                continue;
            if (f[0] === "wifi")
                wifiUp = true;
            else if (f[0] === "ethernet")
                ethUp = true;
        }
        let name = "", sig = 0;
        if (wifiUp && parts.length > 1) {
            for (const line of parts[1].split("\n")) {
                const m = line.match(/^(.):(\d+):(.*)$/);
                if (m && m[1] === "*") {
                    sig = Number(m[2]);
                    name = m[3].replace(/\\:/g, ":");
                    break;
                }
            }
        }
        // Приоритет: wifi, если подключён; иначе ethernet.
        kind = wifiUp ? "wifi" : ethUp ? "ethernet" : "none";
        ssid = name;
        signal = sig;
    }

    Process {
        id: proc
        environment: ({ LC_ALL: "C" })
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,DEVICE device status; echo '---'; nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: Config.netPollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }
}
