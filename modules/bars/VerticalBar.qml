import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: verticalBar
    
    property var rootShell: null
    property var targetScreen: null
    property string edge: "left"

    screen: targetScreen
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: WlrLayershell.Exclusive
    exclusiveZone: 36 * rootShell.verticalBarProgress
    color: "transparent"
    
    anchors.left: edge === "left"
    anchors.right: edge === "right"
    anchors.top: true
    anchors.bottom: true
    
    implicitWidth: 44.0 * rootShell.verticalBarProgress
    implicitHeight: screen ? screen.height : 0

    Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
    
    Item { 
        anchors.fill: parent

        // Top Main Controls Stack
        Column {
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: edge === "left" ? 1 : -1
            spacing: 12
            width: parent.width
            
            MouseArea {
                id: clockMouse
                width: 36; height: clockCol.implicitHeight + 8
                anchors.horizontalCenter: parent.horizontalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (rootShell.calendarRef.calendarActive) {
                        rootShell.calendarRef.forceDismiss();
                    } else {
                        rootShell.calendarRef.showCalendar();
                    }
                }

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: clockMouse.containsMouse ? 0.3 : 0.0
                }
                Column {
                    id: clockCol
                    anchors.centerIn: parent; spacing: 2; width: parent.width
                    Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 10; font.bold: true; color: rootShell.colorAccent; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    Text { 
                        text: { 
                            let hours = rootShell.clockRef.currentTime.getHours() % 12
                            hours = hours === 0 ? 12 : hours
                            return hours + ":" + rootShell.clockRef.currentTime.getMinutes().toString().padStart(2, '0')
                        } 
                        font.family: rootShell.shellFont; font.pixelSize: 11; font.bold: true; color: rootShell.colorText; horizontalAlignment: Text.AlignHCenter; width: parent.width 
                    }
                    Text { text: rootShell.clockRef.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 9; font.bold: false; color: rootShell.colorSubtext; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                }
            }
            
            Workspaces { 
                width: 32 
                anchors.horizontalCenter: parent.horizontalCenter; 
                
                shellTarget: rootShell; 
                parentBarWindow: verticalBar; 
                previewWindowInstance: rootShell.workspaceRef 
            }
        }

        // --- Center Dashboard Trigger Icon Module ---
        Rectangle {
            id: dashIconWrapper
            anchors.centerIn: parent
            width: 32
            height: 32
            radius: 8
            color: dashMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: dashIconText
                anchors.centerIn: parent
                text: "space_dashboard"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22
                color: (dashMouse.containsMouse || rootShell.dashboardRef.dashboardActive) ? rootShell.colorAccent : rootShell.colorSubtext
                Behavior on color { ColorAnimation { duration: 150 } }
                
                // Spring scaling mechanics transformation anchors
                transform: Scale {
                    id: iconScale
                    origin.x: dashIconText.width / 2
                    origin.y: dashIconText.height / 2
                    xScale: 1.0
                    yScale: 1.0
                }

                states: State {
                    name: "hovered"; 
                    // 🎯 FIX: Track the active state toggle instead of the visual transition progress rail
                    when: dashMouse.containsMouse || rootShell.dashboardRef.dashboardActive
                    PropertyChanges { target: iconScale; xScale: 1.18; yScale: 1.18 }
                }

                transitions: [
                    Transition {
                        from: "*"; to: "hovered"
                        NumberAnimation { properties: "xScale,yScale"; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    },
                    Transition {
                        from: "hovered"; to: "*"
                        NumberAnimation { properties: "xScale,yScale"; duration: 250; easing.type: Easing.OutBounce }
                    }
                ]
            }

            MouseArea {
                id: dashMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                
                onEntered: {
                    // Hook directly into the decoupled window connection layers inside shell.qml
                    if (rootShell.dashboardRef.dashboardActive) {
                        rootShell.dashboardRef.cancelDismiss();
                    } else {
                        rootShell.dashboardRef.showDashboard();
                    }
                }
                onExited: rootShell.startDashboardDismissTimer()
            }
        }

        // Bottom Controls Container (SysTray + Navigation Modules)
        Column {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: edge === "left" ? 1 : -1
            spacing: 10
            width: parent.width

            // Mount the new unified hardware modules wrapper card
            SysTray {
                width: 32
                anchors.horizontalCenter: parent.horizontalCenter
                shellTarget: rootShell
                parentBarWindow: verticalBar
            }
        }
    }
}
