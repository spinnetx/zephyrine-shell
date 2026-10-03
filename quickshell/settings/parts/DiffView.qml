import QtQuick
import "../../"
import "../../components"

// Блок различий для цели «изменён вручную» (DESIGN §6.3): unified diff «сгенерировано vs на диске»
// из `zephyrine-settings diff ID`, моноширинный, прокручиваемый; закрывается кнопкой.
// results: id цели -> ответ diff ({files:[{path, diff, binary, truncated, added, removed, note}]}).
Rectangle {
    id: root

    property bool loading: false
    property string error: ""
    property var ids: []
    property var results: ({})
    signal closed

    readonly property var entries: {
        const out = [];
        for (const id of ids) {
            const r = results[id];
            if (!r)
                continue;
            for (const f of (r.files ?? []))
                out.push(f);
        }
        return out;
    }

    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function hex(c) {
        return "#" + [c.r, c.g, c.b].map(v => ("0" + Math.round(v * 255).toString(16)).slice(-2)).join("");
    }
    // Раскраска строк: + зелёный, - красный, @@ и заголовки приглушены. Пробелы/переносы сохраняются.
    function html(text) {
        const add = hex(Colors.success), del = hex(Colors.error), dim = hex(Colors.fgVariant);
        return text.split("\n").map(l => {
            let c = "";
            if (l.startsWith("+++") || l.startsWith("---") || l.startsWith("@@"))
                c = dim;
            else if (l.startsWith("+"))
                c = add;
            else if (l.startsWith("-"))
                c = del;
            const e = esc(l).replace(/ /g, "&nbsp;").replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;");
            return c ? "<font color=\"" + c + "\">" + e + "</font>" : e;
        }).join("<br>");
    }

    implicitHeight: body.implicitHeight + 20
    radius: 10
    color: Qt.alpha(Colors.surfaceContainerLowest, 0.7)
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.3)

    Column {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        Item {
            width: parent.width
            height: 28
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Различия: сгенерировано (−) и на диске (+)"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
            }
            SetButton {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                text: "Закрыть"
                onClicked: root.closed()
            }
        }

        Txt {
            visible: root.loading
            text: "загрузка…"
            color: Colors.fgVariant
        }
        Txt {
            visible: root.error.length > 0
            width: parent.width
            text: root.error
            color: Colors.error
            wrapMode: Text.WordWrap
        }
        Txt {
            visible: !root.loading && root.error.length === 0 && root.entries.length === 0
            width: parent.width
            text: "Различий в содержимом нет (расхождение, например, в правах или в служебных данных)."
            color: Colors.fgVariant
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.entries
            delegate: Column {
                id: fileBox
                required property var modelData
                width: body.width
                spacing: 4

                Txt {
                    width: parent.width
                    text: fileBox.modelData.path + (fileBox.modelData.exists === false ? "  (файла нет)" : "")
                          + (fileBox.modelData.binary ? "" : "   +" + fileBox.modelData.added + " −" + fileBox.modelData.removed)
                    font.pixelSize: Config.fontSize - 1
                    elide: Text.ElideMiddle
                }
                Txt {
                    visible: (fileBox.modelData.note ?? "").length > 0
                    width: parent.width
                    text: fileBox.modelData.note ?? ""
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                    wrapMode: Text.WordWrap
                }
                Txt {
                    visible: fileBox.modelData.binary
                    width: parent.width
                    text: "Бинарный файл — построчные различия недоступны."
                    color: Colors.fgVariant
                    wrapMode: Text.WordWrap
                }
                Item {
                    visible: !fileBox.modelData.binary && fileBox.modelData.diff.length > 0
                    width: parent.width
                    height: visible ? Math.min(diffText.implicitHeight, 300) : 0

                    Flickable {
                        id: diffFlick
                        anchors.fill: parent
                        contentWidth: Math.max(width, diffText.implicitWidth)
                        contentHeight: diffText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: diffText
                            textFormat: Text.RichText
                            text: root.html(fileBox.modelData.diff)
                            color: Colors.fg
                            font.family: "monospace"
                            font.pixelSize: Config.fontSize - 2
                            wrapMode: Text.NoWrap
                            renderType: Text.NativeRendering
                        }
                    }

                    ScrollBar {
                        target: diffFlick
                    }
                }
                Txt {
                    visible: fileBox.modelData.truncated
                    width: parent.width
                    text: "Вывод усечён: показано только начало различий."
                    color: Colors.tertiary
                    font.pixelSize: Config.fontSize - 2
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
