import QtQuick
import "../../"
import "../../components"

// Превью рамки окна (DESIGN §5, hypr.borders.custom): слева «активное» окно с градиентной рамкой под углом,
// справа «неактивное» с однотонной. Только рисует; значения берёт из свойств.
// Угол — как CSS/Hyprland: 0° = слева направо, дальше по часовой стрелке (ось Y вниз). Это приближение:
// Hyprland растягивает градиент по диагонали окна иначе, чем Canvas, но направление и порядок цветов те же.
Item {
    id: root

    property var colors: ["#33ccff", "#00ff99"]   // строки CSS: "#rrggbbaa" не годится — Qt читает как #aarrggbb, поэтому цвета готовим снаружи
    property real angle: 45
    property color inactiveColor: "#595959"
    property int borderSize: 2
    property int rounding: 10

    implicitHeight: 96
    implicitWidth: 320

    onColorsChanged: active.requestPaint()
    onAngleChanged: active.requestPaint()
    onBorderSizeChanged: active.requestPaint()
    onRoundingChanged: active.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.alpha(Colors.background, 0.6)
        border.width: 1
        border.color: Qt.alpha(Colors.outline, 0.25)
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 16

        Canvas {
            id: active
            width: (parent.width - parent.spacing) / 2
            height: parent.height
            antialiasing: true

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width, h = height;
                const bw = Math.max(root.borderSize, 0);
                const r = root.rounding;
                // тело окна
                ctx.fillStyle = Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.9);
                ctx.beginPath();
                ctx.roundedRect(0, 0, w, h, r, r);
                ctx.fill();
                if (bw <= 0)
                    return;
                const a = root.angle * Math.PI / 180;
                const dx = Math.cos(a), dy = Math.sin(a);
                const half = Math.abs(dx) * w / 2 + Math.abs(dy) * h / 2;
                const g = ctx.createLinearGradient(w / 2 - dx * half, h / 2 - dy * half, w / 2 + dx * half, h / 2 + dy * half);
                const n = root.colors.length;
                for (let i = 0; i < n; i++)
                    g.addColorStop(n === 1 ? 0 : i / (n - 1), root.colors[i]);
                if (n === 1)
                    g.addColorStop(1, root.colors[0]);
                ctx.strokeStyle = g;
                ctx.lineWidth = bw * 2;   // видна внутренняя половина: рисуем по краю и обрезаем
                ctx.save();
                ctx.beginPath();
                ctx.roundedRect(0, 0, w, h, r, r);
                ctx.clip();
                ctx.beginPath();
                ctx.roundedRect(0, 0, w, h, r, r);
                ctx.stroke();
                ctx.restore();
            }

            Txt {
                anchors.centerIn: parent
                text: "активное"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
        }

        Item {
            width: (parent.width - parent.spacing) / 2
            height: parent.height

            Rectangle {
                anchors.fill: parent
                radius: root.rounding
                color: Qt.alpha(Colors.surfaceContainer, 0.9)
                border.width: root.borderSize
                border.color: root.inactiveColor
            }
            Txt {
                anchors.centerIn: parent
                text: "неактивное"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
        }
    }
}
