import QtQuick
import "../../"
import "../../components"

// Сетка тем иконок/курсора: плитка = имя + до пяти образцов (файлы-превью готовит CLI `zephyrine-settings themes`),
// выбранная — с рамкой акцента и галочкой. Ничего не пишет: клик по плитке — сигнал picked(value).
// items: [{ name, value, samples: [путь…], note? }]; value "" — «по умолчанию» (иконки по режиму темы);
// current — value выбранной темы; sample — сторона образца в пикселях.
Item {
    id: root

    property var items: []
    property string current: ""
    property int sample: 32
    property bool loading: false
    property string emptyText: "Темы не найдены"
    signal picked(string value)

    readonly property int gap: 10
    readonly property int minTile: 210
    readonly property int cols: Math.max(1, Math.floor((width + gap) / (minTile + gap)))
    readonly property real tileW: (width - (cols - 1) * gap) / cols
    readonly property real tileH: sample + 52
    readonly property int rows: Math.ceil(items.length / cols)

    implicitHeight: items.length > 0 ? rows * tileH + (rows - 1) * gap : 40

    Txt {
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: root.loading ? "Загрузка списка тем…" : root.emptyText
        color: Colors.fgVariant
    }

    Flow {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.items

            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property bool selected: modelData.value === root.current

                width: root.tileW
                height: root.tileH
                radius: 10
                color: selected ? Qt.alpha(Colors.primaryContainer, 0.45) : Qt.alpha(Colors.surfaceContainerHigh, 0.7)
                border.width: selected ? 2 : 1
                border.color: selected ? Colors.primary
                    : (hover.hovered || activeFocus) ? Qt.alpha(Colors.primary, 0.65)
                    : Qt.alpha(Colors.outline, 0.4)
                activeFocusOnTab: true

                Behavior on border.color {
                    ColorAnimation { duration: 120; easing.type: Config.animEasing }
                }

                Row {
                    id: samples
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 36
                        top: parent.top
                        topMargin: 10
                    }
                    height: root.sample
                    spacing: 8

                    Repeater {
                        model: tile.modelData.samples ?? []
                        delegate: Image {
                            required property string modelData
                            width: root.sample
                            height: root.sample
                            source: "file://" + modelData
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            sourceSize.width: root.sample * 2
                            sourceSize.height: root.sample * 2
                        }
                    }
                    Txt {   // у темы нет образцов (или это «по умолчанию»)
                        visible: (tile.modelData.samples ?? []).length === 0
                        height: root.sample
                        verticalAlignment: Text.AlignVCenter
                        text: tile.modelData.note ?? ""
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                    }
                }

                Txt {
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 12
                        bottom: parent.bottom
                        bottomMargin: 10
                    }
                    text: tile.modelData.name
                    elide: Text.ElideRight
                    font.bold: tile.selected
                }

                Rectangle {   // галочка выбранной плитки
                    visible: tile.selected
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    width: 22
                    height: 22
                    radius: 11
                    color: Colors.primary
                    Txt {
                        anchors.centerIn: parent
                        text: Config.icons.check
                        color: Colors.primaryText
                        font.pixelSize: Config.iconSize - 4
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: if (!tile.selected) root.picked(tile.modelData.value)
                }
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && !tile.selected) {
                        root.picked(tile.modelData.value);
                        event.accepted = true;
                    }
                }
            }
        }
    }
}
