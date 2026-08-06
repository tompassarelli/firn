import QtQuick
import Quickshell.Io

Row {
    spacing: 0

    StylixColors { id: colors }

    Process { id: menuProc; command: ["spaces-menu"] }

    // Space chip — which space this workspace band belongs to
    Rectangle {
        visible: SpacesState.available
        anchors.verticalCenter: parent.verticalCenter
        width: chipText.implicitWidth + 16
        height: chipText.implicitHeight + 6
        radius: 4
        color: colors.base0E

        Text {
            id: chipText
            anchors.centerIn: parent
            color: colors.base00
            font.family: colors.fontFamily
            font.pointSize: 10
            font.bold: true
            text: SpacesState.currentLabel
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: menuProc.running = true
        }
    }

    Text {
        visible: SpacesState.available
        anchors.verticalCenter: parent.verticalCenter
        color: colors.base03
        font.family: colors.fontFamily
        font.pointSize: 9
        text: "  "
    }

    Repeater {
        model: BarState.workspaceModel

        Row {
            property int ordinal: SpacesState.memberOrdinals[model.wsId] || 0
            property bool floating: SpacesState.floatingIds[model.wsId] || false
            // The trailing empty workspace earns a pill only while you stand on it.
            visible: !SpacesState.available || ordinal > 0 || (floating && model.isActive)
            spacing: 0

            Text {
                visible: SpacesState.available ? ordinal > 1 : model.index > 0
                anchors.verticalCenter: parent.verticalCenter
                color: colors.base03
                font.family: colors.fontFamily
                font.pointSize: 9
                text: " / "
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: wsText.implicitWidth + 16
                height: wsText.implicitHeight + 6
                radius: 4
                color: model.isActive ? colors.base0B : "transparent"

                Text {
                    id: wsText
                    anchors.centerIn: parent
                    color: model.isActive ? colors.base00 : (floating ? colors.base03 : colors.base04)
                    font.family: colors.fontFamily
                    font.pointSize: 10
                    text: {
                        if (floating) return "+"
                        let label = String(SpacesState.available ? ordinal : model.idx)
                        if (model.name) label += "  " + model.name
                        return label
                    }
                }
            }
        }
    }
}
