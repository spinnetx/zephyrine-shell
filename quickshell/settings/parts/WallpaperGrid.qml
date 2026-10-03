import QtQuick
import QtQuick.Effects
import "../../"
import "../../components"

// Сетка обоев (DESIGN §6.2): плитки с превью-кадром (ffmpeg, готовит CLI `wallpaper list`), выбранная — с рамкой
// акцентного цвета и галочкой. Ничего не пишет: клик по плитке — сигнал picked(value), решает карточка/страница.
// items: [{ name, kind: "video"|"image", thumb: путь|null, value, desktop: bool }], pending — value, выбранный
// кликом, но ещё не подтверждённый списком (мгновенный отклик).
Item {
    id: root

    property var items: []
    property string pending: ""
    property bool loading: false
    signal picked(string value)

    readonly property int gap: 10
    readonly property int minTile: 170
    readonly property int cols: Math.max(1, Math.floor((width + gap) / (minTile + gap)))
    readonly property real tileW: (width - (cols - 1) * gap) / cols
    readonly property real tileH: Math.round(tileW * 9 / 16)
    readonly property int rows: Math.ceil(items.length / cols)

    implicitHeight: items.length > 0 ? rows * tileH + (rows - 1) * gap : 48

    function isSelected(it) {
        return pending !== "" ? it.value === pending : it.desktop === true;
    }

    Txt {
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: root.loading ? "Загрузка списка обоев…" : "В каталоге wallpapers/ нет видео и картинок"
        color: Colors.fgVariant
    }

    Flow {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.items

            delegate: Item {
                id: tile
                required property var modelData
                readonly property bool selected: root.isSelected(modelData)

                width: root.tileW
                height: root.tileH
                activeFocusOnTab: true

                // Превью со скруглёнными углами (маска), либо заглушка, если кадра нет.
                Image {
                    id: img
                    anchors.fill: parent
                    visible: false
                    source: tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(root.tileW * 2)
                }
                Rectangle {
                    id: mask
                    anchors.fill: parent
                    radius: 10
                    visible: false
                    layer.enabled: true
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.alpha(Colors.surfaceContainerHigh, 0.9)
                    visible: img.status !== Image.Ready
                    Txt {
                        anchors.centerIn: parent
                        text: Config.icons.monitor
                        color: Colors.fgVariant
                        font.pixelSize: Config.iconSize * 2
                    }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: img
                    visible: img.status === Image.Ready
                    maskEnabled: true
                    maskSource: mask
                }

                // Подпись: имя файла и тип.
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 26
                    radius: 10
                    color: Qt.alpha(Colors.background, 0.74)
                    Rectangle {   // убираем скругление сверху
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                        }
                        height: 10
                        color: parent.color
                    }
                    Txt {
                        anchors {
                            left: parent.left
                            leftMargin: 9
                            right: kind.left
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        text: String(tile.modelData.name).replace(/\.\d+x\d+$/, "")   // «…1920x1080» в имени файла не нужно
                        font.pixelSize: Config.fontSize - 2
                        elide: Text.ElideRight
                    }
                    Txt {
                        id: kind
                        anchors {
                            right: parent.right
                            rightMargin: 9
                            verticalCenter: parent.verticalCenter
                        }
                        text: tile.modelData.kind === "image" ? "фото" : "видео"
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 3
                    }
                }

                // Рамка: выбранная — акцент, наведение — приглушённый акцент.
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: tile.selected ? 2 : 1
                    border.color: tile.selected ? Colors.primary
                        : (hover.hovered || tile.activeFocus) ? Qt.alpha(Colors.primary, 0.65)
                        : Qt.alpha(Colors.outline, 0.4)
                    Behavior on border.color {
                        ColorAnimation { duration: 120; easing.type: Config.animEasing }
                    }
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
