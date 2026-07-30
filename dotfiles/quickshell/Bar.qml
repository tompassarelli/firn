import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: BarState.pinned ? 0 : LayoutConfig.gap
        left: BarState.pinned ? 0 : LayoutConfig.gap
        right: BarState.pinned ? 0 : LayoutConfig.gap
    }

    implicitHeight: BarState.pinned ? 24 : 30
    exclusionMode: BarState.pinned ? ExclusionMode.Normal : ExclusionMode.Ignore
    color: BarState.pinned ? Qt.rgba(colors.base00.r, colors.base00.g, colors.base00.b, 0.9) : "transparent"

    mask: Region {
        regions: BarState.pinned || BarState.overviewOpen ? [barMask] : []
    }
    Region { id: barMask; item: barContent }

    StylixColors { id: colors }

    Item {
        id: barContent
        anchors.fill: parent
        opacity: BarState.pinned || BarState.overviewOpen ? 1 : 0

        // Left: clock
        Text {
            id: clock
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            color: colors.base05
            font.family: colors.fontFamily
            font.pointSize: 10

            Timer {
                interval: 1000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clock.text = Qt.formatDateTime(new Date(), "h:mm AP")
            }
        }

        // Center: workspaces
        WorkspaceRow {
            id: workspaceRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        // Notification (inline, to the left of status icons)
        Row {
            id: notifRow
            visible: BarState.notifVisible
            anchors.right: statusRow.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: "\u{f0156}"
                color: colors.base04
                font.family: colors.fontFamily
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BarState.dismissNotification()
                }
            }

            Text {
                property real maxWidth: statusRow.x - (workspaceRow.x + workspaceRow.width) - 50
                text: BarState.notifSummary + (BarState.notifBody !== "" ? "  " + BarState.notifBody : "")
                color: colors.base04
                font.family: colors.fontFamily
                font.pointSize: 9
                elide: Text.ElideRight
                width: maxWidth > 0 ? Math.min(implicitWidth, maxWidth) : 0
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BarState.invokeDefaultAction()
                }
            }
        }

        // Right: wifi + battery
        Row {
            id: statusRow
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            onWidthChanged: BarState.rightBarWidth = width + 26
            spacing: 14

            Text {
                id: wifiText
                anchors.verticalCenter: parent.verticalCenter
                color: colors.base05
                font.family: colors.fontFamily
                font.pointSize: 10

                Timer {
                    interval: 5000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: wifiProc.running = true
                }

                Process {
                    id: wifiProc
                    command: ["nmcli", "-t", "-f", "SIGNAL,ACTIVE,SSID", "dev", "wifi"]
                    stdout: SplitParser {
                        onRead: data => {
                            const parts = data.split(":")
                            if (parts[1] === "yes") {
                                wifiText.text = "\u{f0928} " + parts[0] + "%"
                            }
                        }
                    }
                    onExited: (code, status) => {
                        if (code !== 0) wifiText.text = "\u{f092d}"
                    }
                }
            }

            Text {
                id: batteryText
                anchors.verticalCenter: parent.verticalCenter
                color: colors.base05
                font.family: colors.fontFamily
                font.pointSize: 10

                property string batteryCapacity: ""
                property string batteryStatus: ""

                function updateDisplay() {
                    if (batteryCapacity === "" || batteryStatus === "") return;
                    let cap = parseInt(batteryCapacity);
                    let icon;
                    if (batteryStatus === "Charging" || batteryStatus === "Full") {
                        icon = "\u{f0084}"; // battery-charging
                    } else if (cap >= 90) {
                        icon = "\u{f0079}"; // battery full
                    } else if (cap >= 60) {
                        icon = "\u{f0082}"; // battery-70
                    } else if (cap >= 40) {
                        icon = "\u{f007e}"; // battery-50
                    } else if (cap >= 15) {
                        icon = "\u{f007a}"; // battery-30
                    } else {
                        icon = "\u{f008e}"; // battery-alert-variant-outline
                    }
                    batteryText.text = icon + " " + batteryCapacity + "%";
                }

                Timer {
                    interval: 5000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        batteryCapacityProc.running = true;
                        batteryStatusProc.running = true;
                    }
                }

                Process {
                    id: batteryCapacityProc
                    command: ["cat", "/sys/class/power_supply/BAT1/capacity"]
                    stdout: SplitParser {
                        onRead: data => {
                            batteryText.batteryCapacity = data.trim();
                            batteryText.updateDisplay();
                        }
                    }
                }

                Process {
                    id: batteryStatusProc
                    command: ["cat", "/sys/class/power_supply/BAT1/status"]
                    stdout: SplitParser {
                        onRead: data => {
                            batteryText.batteryStatus = data.trim();
                            batteryText.updateDisplay();
                        }
                    }
                }
            }
        }
    }
}
