import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../"
import "../services"

// Единая выпадающая карточка рядом с баром (по одной на монитор; открыта максимум одна на весь шелл —
// состояние в PopoutState). PopupWindow вдоль бара (шириной/высотой в бар), прозрачный, с маской по самой карточке
// (чтобы не перехватывать клики мимо неё); карточка сама плавно растёт/сдвигается/меняет содержимое.
// Сторона раскрытия зависит от положения панели (Config.barPosition): под верхней, над нижней, справа от левой,
// слева от правой.
PopupWindow {
    id: pop

    // PanelWindow бара, к которому привязан попап.
    required property var bar

    readonly property bool mine: PopoutState.item !== null && PopoutState.item.QsWindow.window === bar
    readonly property bool shown: mine && PopoutState.open
    // Последний открытый вид — чтобы содержимое не исчезало раньше, чем доиграет анимация закрытия.
    property string shownKind: ""

    Binding {
        target: pop
        property: "shownKind"
        value: PopoutState.kind
        when: pop.shown
        restoreMode: Binding.RestoreNone
    }

    readonly property var sources: ({
        wifi: "../popouts/WifiPopout.qml",
        bluetooth: "../popouts/BluetoothPopout.qml",
        audio: "../popouts/AudioPopout.qml",
        battery: "../popouts/BatteryPopout.qml",
        tray: "../popouts/TrayPopout.qml",
        clock: "../popouts/ClockPopout.qml",
        cpu: "../popouts/CpuPopout.qml",
        gpu: "../popouts/GpuPopout.qml",
        mem: "../popouts/MemPopout.qml",
        net: "../popouts/NetPopout.qml",
        timer: "../popouts/TimerPopout.qml",
        weather: "../popouts/WeatherPopout.qml",
        apps: "../popouts/AppsPopout.qml" // KDE Plasma style two-panel app menu
    })

    // Центр триггера в координатах окна бара → целевой x карточки (с прижатием к краям).
    property real anchorX: 0
    property real anchorY: 0
    function recalc() {
        if (!mine)
            return;
        const p = bar.contentItem.mapFromItem(PopoutState.item, PopoutState.item.width / 2, PopoutState.item.height / 2);
        anchorX = p.x;
        anchorY = p.y;
    }

    readonly property string side: Config.barPosition      // top | bottom | left | right
    readonly property bool vert: Config.barVertical
    Connections {
        target: PopoutState
        function onItemChanged() { pop.recalc(); }
        function onKindChanged() { pop.recalc(); }
    }
    // Триггеры могут сдвигаться (ширины пилюль анимируются) — пока открыто, подстраиваемся.
    Timer {
        interval: 100
        running: pop.shown
        repeat: true
        onTriggered: pop.recalc()
    }

    anchor.window: bar
    // Точка привязки окна-носителя на окне бара и направление роста:
    //   top    — под баром (левый верхний угол носителя в левом нижнем углу бара);
    //   bottom — над баром (левый нижний угол носителя в левом верхнем углу бара);
    //   left   — справа от бара; right — слева от бара.
    anchor.rect.x: side === "left" ? bar.width : 0
    anchor.rect.y: side === "top" ? bar.height : 0
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: side === "top" ? (Edges.Bottom | Edges.Left)
        : side === "bottom" ? (Edges.Top | Edges.Left)
        : side === "left" ? (Edges.Right | Edges.Top) : (Edges.Left | Edges.Top)
    anchor.gravity: side === "top" ? (Edges.Bottom | Edges.Right)
        : side === "bottom" ? (Edges.Top | Edges.Right)
        : side === "left" ? (Edges.Right | Edges.Bottom) : (Edges.Left | Edges.Bottom)

    implicitWidth: vert ? Config.popoutMaxWidth : bar.width
    implicitHeight: vert ? bar.height : Config.popoutMaxHeight
    color: "transparent"
    visible: shown || card.opacity > 0.01
    // Ввод — только в пределах карточки (остальное окно прозрачное и не должно перехватывать клики).
    // Region { item: card } в 0.3.1 оставлял пустую область ввода, поэтому границы заданы явно.
    mask: Region {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
    }

    // Закреплённая карточка (IPC notifs toggle): клик вне карточки снимает закрепление,
    // Esc — тоже (ниже, Keys на карточке).
    HyprlandFocusGrab {
        windows: [pop]
        active: pop.shown && PopoutState.pinned
        onCleared: PopoutState.close()
    }

    Rectangle {
        id: card

        readonly property real pad: Config.popoutPadding
        readonly property real wantW: loader.item ? loader.item.implicitWidth + pad * 2 : 0
        readonly property real wantH: loader.item ? Math.min(loader.item.implicitHeight + pad * 2, (pop.vert ? pop.height : Config.popoutMaxHeight) - Config.popoutGap) : 0

        // Анимации x/ширины включены, только пока карточка уже раскрыта (при открытии — прыжок на место).
        readonly property bool settled: height > 2

        // Вдоль бара — центрируется на триггере с прижатием к краям; поперёк — рядом с баром (зазор popoutGap).
        x: pop.vert ? (pop.side === "left" ? Config.popoutGap : pop.width - width - Config.popoutGap)
            : Math.max(8, Math.min(pop.anchorX - width / 2, pop.width - width - 8))
        y: pop.vert ? Math.max(8, Math.min(pop.anchorY - height / 2, pop.height - height - 8))
            : (pop.side === "bottom" ? pop.height - height - Config.popoutGap : Config.popoutGap)
        width: wantW
        height: pop.shown ? wantH : 0
        opacity: pop.shown ? 1 : 0
        radius: Config.popoutRadius
        clip: true
        // Фон как у бара, но плотнее: карточка может оказаться над чем угодно, не только над обоями.
        color: Qt.alpha(Colors.background, 0.96)
        border.width: 1
        border.color: Qt.alpha(Colors.outline, 0.45)

        focus: PopoutState.pinned
        Keys.onEscapePressed: PopoutState.close()

        Behavior on x {
            enabled: card.settled
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
        Behavior on y {
            enabled: card.settled
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
        Behavior on width {
            enabled: card.settled
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
        Behavior on height {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
        Behavior on opacity {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }

        HoverHandler {
            onHoveredChanged: hovered ? PopoutState.popupEnter() : PopoutState.popupLeave()
        }

        Loader {
            id: loader
            x: card.pad
            y: card.pad
            source: pop.sources[pop.shownKind] ?? ""
            onLoaded: fade.restart()

            NumberAnimation {
                id: fade
                target: loader
                property: "opacity"
                from: 0
                to: 1
                duration: Config.animMs
                easing.type: Config.animEasing
            }
        }
    }
}
