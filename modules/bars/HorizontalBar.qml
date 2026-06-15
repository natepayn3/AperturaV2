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
    WlrLayershell.layer: WlrLayer.Overlay
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
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            // Offset logic
            anchors.verticalCenterOffset: edge === "top" ? 1 : -1
            spacing: 12
            height: parent.height
            
            MouseArea {
                id: settingsMouse
                width: 32; height: 32
                anchors.verticalCenter: parent.verticalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (rootShell.launcherRef.launcherActive) {
                        rootShell.launcherRef.forceDismiss();
                    }
                }
                onClicked: rootShell.settingsAppRef.windowVisible = !rootShell.settingsAppRef.windowVisible

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: settingsMouse.containsMouse ? 0.3 : 0.0
                }
                Text { 
                    text: "settings"; font.family: "Material Icons"; font.pixelSize: 22; 
                    color: rootShell.settingsAppRef.windowVisible ? rootShell.colorAccent : rootShell.colorText; 
                    anchors.centerIn: parent 
                }
            }

            MouseArea {
                id: launcherMouse
                width: 32; height: 32
                anchors.verticalCenter: parent.verticalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                
                onClicked: {
                    if (rootShell.launcherRef.launcherActive) {
                        rootShell.launcherRef.forceDismiss();
                    } else {
                        rootShell.launcherRef.showLauncher();
                    }
                }

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: launcherMouse.containsMouse || rootShell.launcherRef.launcherActive ? 0.3 : 0.0
                }
                
                Text { 
                    text: "apps"; font.family: "Material Symbols Outlined"; font.pixelSize: 22
                    color: rootShell.launcherRef.launcherActive ? rootShell.colorAccent : rootShell.colorText
                    anchors.centerIn: parent 
                }
            }
            
            MouseArea {
                id: clockMouse
                width: clockRow.implicitWidth + 12; height: 32
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                anchors.verticalCenter: parent.verticalCenter
                onContainsMouseChanged: {
                    if (containsMouse) {
                        if (rootShell.launcherRef.launcherActive) {
                            rootShell.launcherRef.forceDismiss();
                        }
                        rootShell.calendarRef.showCalendar();
                    } else {
                        rootShell.calendarRef.requestDismiss();
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
    }
}
