import QtQuick
import QtQuick.Shapes

// Круглый аватар: картинка пользователя, а если её нет/не читается
// (greeter от имени sddm часто не видит ~/.face) — круг с первой буквой.
// Круглое отсечение без QtGraphicalEffects/MultiEffect: картинка используется
// как fillItem круглого Shape (Qt Quick Shapes, Qt >= 6.8).
Item {
    id: root

    property string source: ""
    property string name: ""
    property int size: 84

    width: size
    height: size

    // Подложка с первой буквой (всегда под картинкой)
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.primaryContainer

        Txt {
            anchors.centerIn: parent
            text: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : ""
            color: Theme.fg
            font.pixelSize: root.size * 0.42
            font.bold: true
        }
    }

    // Исходный размер картинки (для расчёта «покрытия» круга).
    Image {
        id: probe
        source: root.source
        visible: false
        asynchronous: true
    }

    // ВАЖНО: Shape накладывает fillItem по пиксельным координатам пути — текстура должна быть
    // того же масштаба, что и круг (раньше sourceSize ×2 давал только левую верхнюю четверть).
    // Грузим картинку так, чтобы её МЕНЬШАЯ сторона равнялась size (cover); лишнее по длинной
    // стороне срезается снизу/справа (для портретных аватаров это нижняя часть).
    Image {
        id: img
        readonly property real pw: probe.implicitWidth > 0 ? probe.implicitWidth : root.size
        readonly property real ph: probe.implicitHeight > 0 ? probe.implicitHeight : root.size
        readonly property real cover: root.size / Math.min(pw, ph)
        source: probe.status === Image.Ready ? root.source : ""
        sourceSize.width: Math.ceil(pw * cover)
        sourceSize.height: Math.ceil(ph * cover)
        fillMode: Image.Stretch
        asynchronous: true
        smooth: true
        visible: false
    }

    Shape {
        anchors.fill: parent
        visible: img.status === Image.Ready
        ShapePath {
            strokeWidth: -1
            fillItem: img
            startX: root.size / 2
            startY: 0
            PathArc {
                x: root.size / 2
                y: root.size
                radiusX: root.size / 2
                radiusY: root.size / 2
            }
            PathArc {
                x: root.size / 2
                y: 0
                radiusX: root.size / 2
                radiusY: root.size / 2
            }
        }
    }

    // Кольцо поверх
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.alpha(Theme.primary, 0.7)
    }
}
