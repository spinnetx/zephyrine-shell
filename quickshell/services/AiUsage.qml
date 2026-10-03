pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Лимиты ИИ: раз в Config.aiPollMs вызывает ai-usage-widget.sh (~2 с) для
// claude и agy. Один опрос на все мониторы. При ошибке остаётся прошлое значение.
Singleton {
    id: root

    property var claude: ({ text: "✳ ?", tooltip: "Нет данных", cls: "" })
    property var agy: ({ text: "✦ ?", tooltip: "Нет данных", cls: "" })

    component Source: QtObject {
        id: src
        required property string name
        signal parsed(var value)

        function parse(t) {
            try {
                const o = JSON.parse(t.trim());
                if (o && typeof o.text === "string")
                    src.parsed({ text: o.text, tooltip: o.tooltip || "", cls: o["class"] || "" });
            } catch (e) {
                // оставляем прошлое значение
            }
        }

        property Process proc: Process {
            command: [Config.aiScript, src.name]
            stdout: StdioCollector {
                onStreamFinished: src.parse(text)
            }
        }

        property Timer timer: Timer {
            interval: Config.aiPollMs
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: if (!src.proc.running) src.proc.running = true
        }
    }

    Source {
        name: "claude"
        onParsed: v => root.claude = v
    }
    Source {
        name: "agy"
        onParsed: v => root.agy = v
    }
}
