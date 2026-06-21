import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: horizontalBar
    
    // Injected dependencies
    property var rootShell: null
    property var targetScreen: null
    property string edge: "top" // "top" or "bottom"

    screen: targetScreen
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: WlrLayershell.Exclusive
    exclusiveZone: 36 * rootShell.horizontalBarProgress
    color: "transparent"
    
    // Dynamic anchors
    anchors.left: true
    anchors.right: true
    anchors.top: edge === "top"
    anchors.bottom: edge === "bottom"
    
    implicitWidth: screen ? screen.width : 0
    implicitHeight: 44.0 * rootShell.horizontalBarProgress

    Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
    
    Item { 
        anchors.fill: parent

        // --- Left-aligned Core Controls Stack ---
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: edge === "top" ? 1 : -1
            spacing: 12
            height: parent.height
            
            MouseArea {
                id: clockMouse
                width: clockRow.implicitWidth + 12; height: 32
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    let popup = rootShell.calendarRef;
                    if (popup.calendarActive) {
                        popup.forceDismiss();
                    } else {
                        popup.showCalendar();
                    }
                }

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: clockMouse.containsMouse ? 0.3 : 0.0
                }
                Row {
                    id: clockRow
                    spacing: 6; anchors.centerIn: parent
                    Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorAccent; verticalAlignment: Text.AlignVCenter }
                    Text { text: "•"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                    Text { 
                        text: { 
                            let hours = rootShell.clockRef.currentTime.getHours() % 12
                            hours = hours === 0 ? 12 : hours
                            return hours + ":" + rootShell.clockRef.currentTime.getMinutes().toString().padStart(2, '0')
                        } 
                        font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorText; verticalAlignment: Text.AlignVCenter 
                    }
                    Text { text: rootShell.clockRef.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                }
            }
            
            Workspaces { 
                anchors.verticalCenter: parent.verticalCenter; shellTarget: rootShell; 
                parentBarWindow: horizontalBar; previewWindowInstance: rootShell.workspaceRef 
            }
        }

        // --- Center Dashboard Trigger Icon Module (Hover Animated) ---
        Rectangle {
            id: dashIconWrapper
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: edge === "top" ? 1 : -1
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
                color: (dashMouse.containsMouse || (rootShell.dashboardRef && rootShell.dashboardRef.dashboardActive)) ? rootShell.colorAccent : rootShell.colorSubtext
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
                    when: dashMouse.containsMouse || (rootShell.dashboardRef && rootShell.dashboardRef.dashboardActive)
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
                    if (rootShell.dashboardRef) {
                        if (rootShell.dashboardRef.dashboardActive) {
                            rootShell.dashboardRef.cancelDismiss();
                        } else {
                            // 🎯 FIX: Force Wayland output mapping on hover enter
                            rootShell.dashboardRef.screen = targetScreen; 
                            rootShell.dashboardRef.showDashboard();
                        }
                    }
                }
                onExited: {
                    if (rootShell.dashboardRef) {
                        // Call the module's dedicated dismiss request which handles the timeout logic
                        rootShell.dashboardRef.requestDismiss();
                    }
                }
                
                // Fallback click action
                onClicked: {
                    if (rootShell.dashboardRef) {
                        if (rootShell.dashboardRef.dashboardActive) {
                            rootShell.dashboardRef.forceDismiss();
                        } else {
                            // 🎯 FIX: Force Wayland output mapping on manual fallback click
                            rootShell.dashboardRef.screen = targetScreen; 
                            rootShell.dashboardRef.showDashboard();
                        }
                    }
                }
            }
        }

        // --- Right-aligned System Tray Drawer Container ---
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: edge === "top" ? 1 : -1
            height: parent.height

            SysTray {
                height: 32
                anchors.verticalCenter: parent.verticalCenter
                shellTarget: rootShell
                parentBarWindow: horizontalBar
            }
        }
    }
}
