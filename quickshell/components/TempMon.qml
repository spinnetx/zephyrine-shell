import QtQuick
import "../"
import "../services"

// Температура: «🌡 54° 48°» — процессор и, если карта активна, видеокарта. Цвет по порогам Config.tempWarnC / tempCritC
// (для GPU — gpuTemp*). Скрыта, если датчиков нет. Без своего попапа (подробности — у «Процессора»): значения в подсказке.
Pill {
    id: root

    readonly property real cpu: SysMon.cpuTempC
    readonly property real gpu: Gpu.state === "active" ? Gpu.tempC : -1
    readonly property bool shown: cpu >= 0 || gpu >= 0

    function tint(t, warn, crit) {
        return t >= crit ? Colors.error : t >= warn ? Colors.tertiary : Colors.fg;
    }

    visible: shown
    spacing: 6
    tooltip: (cpu >= 0 ? "Процессор: " + Math.round(cpu) + " °C" : "") + (cpu >= 0 && gpu >= 0 ? "\n" : "") + (gpu >= 0 ? "Видеокарта: " + Math.round(gpu) + " °C" : "")

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.thermometer
        color: Math.max(root.cpu, root.gpu) >= Config.tempWarnC ? root.tint(Math.max(root.cpu, root.gpu), Config.tempWarnC, Config.tempCritC) : Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.cpu >= 0
        text: Math.round(root.cpu) + "°"
        color: root.tint(root.cpu, Config.tempWarnC, Config.tempCritC)
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.gpu >= 0
        text: Math.round(root.gpu) + "°"
        color: root.tint(root.gpu, Config.gpuTempWarnC, Config.gpuTempCritC)
    }
}
