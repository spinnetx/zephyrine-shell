import QtQuick
import "../"
import "../services"

// Лимиты ИИ (Claude / Gemini через agy): цвет по class из скрипта.
Row {
    id: root

    spacing: Config.spacing

    function tint(cls) {
        return cls === "critical" ? Colors.error : cls === "warning" ? Colors.tertiary : Colors.fg;
    }

    Pill {
        tooltip: AiUsage.claude.tooltip
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: AiUsage.claude.text
            color: root.tint(AiUsage.claude.cls)
        }
    }
    Pill {
        tooltip: AiUsage.agy.tooltip
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: AiUsage.agy.text
            color: root.tint(AiUsage.agy.cls)
        }
    }
}
