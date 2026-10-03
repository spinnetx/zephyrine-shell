pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../"
import "../components"
import "../services"

// Сеть: график скорости за ~60 с (↓/↑) и список интерфейсов — скорость, итого за сессию, IPv4.
Item {
    id: root

    // Адреса по интерфейсам из `ip -j addr` (разовый вызов при открытии): { имя: "1.2.3.4/24" }
    property var addrs: ({})

    implicitWidth: 340
    implicitHeight: col.implicitHeight

    function parseAddrs(text) {
        const m = {};
        try {
            for (const i of JSON.parse(text)) {
                const v4 = (i.addr_info ?? []).find(a => a.family === "inet");
                if (v4)
                    m[i.ifname] = v4.local + "/" + v4.prefixlen;
            }
        } catch (e) {}
        addrs = m;
    }

    Process {
        id: ipProc
        command: ["ip", "-j", "addr"]
        stdout: StdioCollector {
            onStreamFinished: root.parseAddrs(text)
        }
    }
    Connections {
        target: PopoutState
        function onKindChanged() {
            if (PopoutState.kind === "net" && !ipProc.running)
                ipProc.running = true;
        }
    }
    Connections {
        target: SysMon
        function onRxHistChanged() { canvas.requestPaint(); }
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Row {
            spacing: 14
            Row {
                spacing: 4
                Txt {
                    text: Config.icons.arrowDown
                    color: Colors.tertiary
                    font.pixelSize: Config.iconSize + 2
                }
                Txt {
                    text: SysMon.fmtRate(SysMon.rxRate) + "/s"
                    font.bold: true
                    font.pixelSize: Config.fontSize + 3
                }
            }
            Row {
                spacing: 4
                Txt {
                    text: Config.icons.arrowUp
                    color: Colors.primary
                    font.pixelSize: Config.iconSize + 2
                }
                Txt {
                    text: SysMon.fmtRate(SysMon.txRate) + "/s"
                    font.bold: true
                    font.pixelSize: Config.fontSize + 3
                }
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "за " + Config.netHistorySize + " с"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
        }

        // График: общая шкала для ↓ и ↑ (минимум 10 КиБ/с, чтобы тишина не выглядела «шумом»).
        Rectangle {
            width: parent.width
            height: 64
            radius: 8
            color: Colors.surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colors.outlineVariant, 0.6)

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: 4
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height, n = Config.netHistorySize;
                    const rx = SysMon.rxHist, tx = SysMon.txHist;
                    const max = Math.max(10240, ...rx, ...tx);
                    const series = (data, color) => {
                        if (data.length < 2)
                            return;
                        const step = w / (n - 1);
                        const x0 = w - (data.length - 1) * step;
                        ctx.beginPath();
                        ctx.moveTo(x0, h);
                        for (let i = 0; i < data.length; i++)
                            ctx.lineTo(x0 + i * step, h - (data[i] / max) * (h - 2));
                        ctx.lineTo(w, h);
                        ctx.closePath();
                        ctx.fillStyle = Qt.alpha(color, 0.18);
                        ctx.fill();
                        ctx.beginPath();
                        for (let i = 0; i < data.length; i++) {
                            const x = x0 + i * step, y = h - (data[i] / max) * (h - 2);
                            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                        }
                        ctx.strokeStyle = color;
                        ctx.lineWidth = 1.5;
                        ctx.stroke();
                    };
                    series(rx, Colors.tertiary);
                    series(tx, Colors.primary);
                }
            }
            Txt {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                text: "макс " + SysMon.fmtRate(Math.max(10240, ...SysMon.rxHist, ...SysMon.txHist)) + "/s"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 3
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outlineVariant, 0.6)
        }

        Repeater {
            model: SysMon.ifaces

            Column {
                id: item
                required property var modelData
                width: col.width
                spacing: 1

                Item {
                    width: parent.width
                    height: nameTxt.implicitHeight
                    Txt {
                        id: nameTxt
                        text: item.modelData.name
                        font.bold: true
                    }
                    Txt {
                        anchors.right: parent.right
                        text: root.addrs[item.modelData.name] ?? "нет IPv4"
                        color: Colors.fgVariant
                    }
                }
                Txt {
                    text: Config.icons.arrowDown + " " + SysMon.fmtRate(item.modelData.rx) + "/s   " + Config.icons.arrowUp + " " + SysMon.fmtRate(item.modelData.tx) + "/s"
                }
                Txt {
                    text: "За сессию:  " + Config.icons.arrowDown + " " + SysMon.fmtBytes(item.modelData.rxTotal) + "   " + Config.icons.arrowUp + " " + SysMon.fmtBytes(item.modelData.txTotal)
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                }
            }
        }

        Txt {
            visible: SysMon.ifaces.length === 0
            text: "Нет активных интерфейсов"
            color: Colors.fgVariant
        }
    }
}
