import QtQuick
import Quickshell.Io

Row {
    spacing: 0

    StylixColors { id: colors }

    Process { id: menuProc; command: ["activity-menu"] }

    // Space chip — which space this workspace band belongs to
    Rectangle {
        visible: ActivityState.available
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
            text: ActivityState.currentLabel
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: menuProc.running = true
        }
    }

    Text {
        visible: ActivityState.available
        anchors.verticalCenter: parent.verticalCenter
        color: colors.base03
        font.family: colors.fontFamily
        font.pointSize: 9
        text: "  "
    }

    Repeater {
        model: BarState.workspaceModel

        Row {
            property int ordinal: ActivityState.memberOrdinals[model.wsId] || 0
            property bool floating: ActivityState.floatingIds[model.wsId] || false
            // Other activities retain their Niri workspaces without occupying this activity's row.
            visible: !ActivityState.available || ordinal > 0 || floating
            spacing: 0

            Text {
                visible: ActivityState.available ? (ordinal > 1 || (floating && ActivityState.memberCount > 0)) : model.index > 0
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
                        // Floating = not yet adopted; show the ordinal it will take on adoption.
                        if (floating) return String(ActivityState.memberCount + 1)
                        let label = String(ActivityState.available ? ordinal : model.idx)
                        if (model.name) label += "  " + model.name
                        return label
                    }
                }
            }
        }
    }
}
