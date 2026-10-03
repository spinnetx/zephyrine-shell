import QtQuick
import "../services"

// Вешается ВНУТРИ иконки/группы: при наведении открывает попап `kind` под родительским Item.
//   PopoutTrigger { kind: "wifi" }
// payload — произвольные данные для содержимого (например, SystemTrayItem).
HoverHandler {
    id: root

    property string kind: ""
    property var payload: null

    onHoveredChanged: {
        if (!kind)
            return;
        if (hovered)
            PopoutState.enter(kind, root.parent, payload);
        else
            PopoutState.leave(root.parent);
    }
}
