import QtQuick
import "../../"
import "../../components"
import "../logic.js" as Logic

// Карточка одного монитора (DESIGN §4.3, §6.5):
// - Имя (eDP-1) и описание.
// - Переключатель Вкл/Выкл (нельзя отключить последний активный монитор).
// - Режим (разрешение @ частота), масштаб, поворот, относительное положение, зеркалирование.
Rectangle {
    id: root

    property var monitor: ({})
    property var allMonitors: []
    property int activeMonitorCount: 1

    signal updated(var newMon)

    implicitWidth: 440
    implicitHeight: col.implicitHeight + 20
    radius: Config.popoutRadius - 2
    color: Qt.alpha(Colors.surfaceContainerHigh, 0.6)
    border.width: 1
    border.color: root.monitor.focused ? Qt.alpha(Colors.primary, 0.6) : Qt.alpha(Colors.outline, 0.25)

    readonly property var otherMonitors: {
        const list = [];
        for (let i = 0; i < allMonitors.length; i++) {
            if (allMonitors[i].name !== root.monitor.name)
                list.push(allMonitors[i]);
        }
        return list;
    }

    readonly property string currentModeStr: {
        if (root.monitor.mode)
            return root.monitor.mode;
        if (root.monitor.availableModes && root.monitor.availableModes.length > 0) {
            const w = root.monitor.width || 1920;
            const h = root.monitor.height || 1080;
            const r = root.monitor.refreshRate || 60;
            for (let i = 0; i < root.monitor.availableModes.length; i++) {
                const parsed = Logic.parseMode(root.monitor.availableModes[i]);
                if (parsed.width === w && parsed.height === h && Math.abs(parsed.refresh - r) < 1.0) {
                    return root.monitor.availableModes[i];
                }
            }
        }
        return (root.monitor.width || 1920) + "x" + (root.monitor.height || 1080) + "@" + Math.round(root.monitor.refreshRate || 60) + "Hz";
    }

    function clone() {
        return Object.assign({}, root.monitor);
    }

    function updateField(key, val) {
        const m = clone();
        m[key] = val;
        root.updated(m);
    }

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        // Шапка монитора
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Txt {
                    text: root.monitor.name || "Экран"
                    font.bold: true
                    font.pixelSize: Config.fontSize + 1
                }

                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: root.monitor.focused ? "info" : "neutral"
                    text: root.monitor.focused ? "активный" : (root.monitor.disabled ? "выключен" : "подключен")
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.monitor.disabled ? "Выключен" : "Включен"
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                }

                PopSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: !root.monitor.disabled
                    enabled: root.monitor.disabled || root.activeMonitorCount > 1
                    onToggled: root.updateField("disabled", !checked)
                }
            }
        }

        Txt {
            width: parent.width
            text: root.monitor.description || "Дисплей"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.2)
        }

        // Параметры активного монитора
        Column {
            width: parent.width
            spacing: 6
            opacity: root.monitor.disabled ? 0.4 : 1.0
            enabled: !root.monitor.disabled

            // Режим экрана (разрешение @ частота)
            SetRow {
                width: parent.width
                label: "Режим"
                hint: "Разрешение и частота обновления"

                SetDropdown {
                    width: 220
                    options: (root.monitor.availableModes && root.monitor.availableModes.length > 0)
                        ? root.monitor.availableModes.map(m => ({ value: m, label: m }))
                        : [{ value: root.currentModeStr, label: root.currentModeStr }]
                    current: root.currentModeStr
                    onSelected: v => {
                        const parsed = Logic.parseMode(v);
                        const m = root.clone();
                        m.mode = v;
                        m.width = parsed.width;
                        m.height = parsed.height;
                        m.refreshRate = parsed.refresh;
                        root.updated(m);
                    }
                }
            }

            // Масштабирование
            SetRow {
                width: parent.width
                label: "Масштаб"
                hint: "Размер элементов интерфейса"

                SetSegmented {
                    options: [
                        { value: 1.0, label: "1" },
                        { value: 1.25, label: "1.25" },
                        { value: 1.5, label: "1.5" },
                        { value: 1.75, label: "1.75" },
                        { value: 2.0, label: "2" }
                    ]
                    current: root.monitor.scale || 1.0
                    onSelected: v => root.updateField("scale", v)
                }
            }

            // Ориентация / поворот
            SetRow {
                width: parent.width
                label: "Поворот"
                hint: "Ориентация дисплея"

                SetDropdown {
                    width: 180
                    options: [
                        { value: 0, label: "0° (альбомная)" },
                        { value: 1, label: "90° (портретная)" },
                        { value: 2, label: "180° (перевёрнутая)" },
                        { value: 3, label: "270° (портретная)" }
                    ]
                    current: root.monitor.transform || 0
                    onSelected: v => root.updateField("transform", v)
                }
            }

            // Относительное положение (если мониторов больше одного)
            SetRow {
                visible: root.otherMonitors.length > 0
                width: parent.width
                label: "Положение"
                hint: "Координаты на рабочем столе"

                SetDropdown {
                    width: 160
                    options: [
                        { value: "origin", label: "0,0 (начало)" },
                        { value: "right-of", label: "Справа от" },
                        { value: "left-of", label: "Слева от" },
                        { value: "above", label: "Над" },
                        { value: "below", label: "Под" }
                    ]
                    current: root.monitor.relPos || (root.monitor.x === 0 && root.monitor.y === 0 ? "origin" : "origin")
                    onSelected: v => {
                        const m = root.clone();
                        m.relPos = v;
                        if (!m.relTarget && root.otherMonitors.length > 0)
                            m.relTarget = root.otherMonitors[0].name;

                        const map = {};
                        for (let i = 0; i < root.allMonitors.length; i++)
                            map[root.allMonitors[i].name] = root.allMonitors[i];

                        const pos = Logic.calcRelativePosition(v, m.relTarget, m, map);
                        m.x = pos.x;
                        m.y = pos.y;
                        m.position = pos.str;
                        root.updated(m);
                    }
                }

                SetDropdown {
                    visible: !!(root.monitor && root.monitor.relPos && root.monitor.relPos !== "origin" && root.otherMonitors && root.otherMonitors.length > 0)
                    width: 110
                    options: root.otherMonitors.map(om => ({ value: om.name, label: om.name }))
                    current: root.monitor.relTarget || (root.otherMonitors.length > 0 ? root.otherMonitors[0].name : "")
                    onSelected: v => {
                        const m = root.clone();
                        m.relTarget = v;
                        const map = {};
                        for (let i = 0; i < root.allMonitors.length; i++)
                            map[root.allMonitors[i].name] = root.allMonitors[i];

                        const pos = Logic.calcRelativePosition(m.relPos, v, m, map);
                        m.x = pos.x;
                        m.y = pos.y;
                        m.position = pos.str;
                        root.updated(m);
                    }
                }
            }

            // Зеркалирование
            SetRow {
                visible: root.otherMonitors.length > 0
                width: parent.width
                label: "Зеркало"
                hint: "Дублировать изображение с другого экрана"

                SetDropdown {
                    width: 160
                    options: [{ value: null, label: "нет" }].concat(root.otherMonitors.map(om => ({ value: om.name, label: om.name })))
                    current: root.monitor.mirror || null
                    onSelected: v => root.updateField("mirror", v)
                }
            }
        }
    }
}
