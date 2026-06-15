import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: verticalBar
    
    // Injected dependencies
    property var rootShell: null
    property var targetScreen: null
    property string edge: "left" // "left" or "right"

    screen: targetScreen
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: WlrLayershell.Exclusive
    exclusiveZone: 36 * rootShell.verticalBarProgress
    color: "transparent"
    
    // Dynamic anchors based on edge string
    anchors.left: edge === "left"
    anchors.right: edge === "right"
    anchors.top: true
    anchors.bottom: true
    
    implicitWidth: 44.0 * rootShell.verticalBarProgress
    implicitHeight: screen ? screen.height : 0

    Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
    
    Item { 
        anchors.fill: parent
        Column {
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            // Offset logic dynamically flips based on edge
            anchors.horizontalCenterOffset: edge === "left" ? 1 : -1
            spacing: 12
            width: parent.width
            
            MouseArea {
                id: settingsMouse
                width: 28; height: 28
                anchors.horizontalCenter: parent.horizontalCenter
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
                    text: "settings"; font.family: "Material Icons"; font.pixelSize: 18; 
                    color: rootShell.settingsAppRef.windowVisible ? rootShell.colorAccent : rootShell.colorText; 
                    anchors.centerIn: parent 
                }
            }

            MouseArea {
                id: launcherMouse
                width: 28; height: 28
                anchors.horizontalCenter: parent.horizontalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                
                onClicked: {
                    if (rootShell.launcherRef) {
                        rootShell.launcherRef.active = !rootShell.launcherRef.active;
                    }
                }

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: launcherMouse.containsMouse || rootShell.launcherRef.launcherActive ? 0.3 : 0.0
                }
                
                Text {
                    text: "apps" // Or your designated icon string
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 22
                    anchors.centerIn: parent 
                    
                    // Dynamic color matching the Settings active state logic
                    color: (rootShell.launcherRef && rootShell.launcherRef.active)
                        ? rootShell.colorAccent 
                        : rootShell.colorText
                }
            }
            
            MouseArea {
                id: clockMouse
                width: 36; height: clockCol.implicitHeight + 8
                anchors.horizontalCenter: parent.horizontalCenter
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (rootShell.launcherRef.launcherActive) {
                        rootShell.launcherRef.forceDismiss();
                    }
                    rootShell.calendarRef.showCalendar();
                }
                onExited: rootShell.calendarRef.requestDismiss()

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: rootShell.colorAccent
                    opacity: clockMouse.containsMouse ? 0.3 : 0.0
                }
                Column {
                    id: clockCol
                    anchors.centerIn: parent; spacing: 2
                    width: parent.width
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
                width: 28; anchors.horizontalCenter: parent.horizontalCenter; 
                shellTarget: rootShell; parentBarWindow: verticalBar; 
                previewWindowInstance: rootShell.workspaceRef 
            }
        }
    }
}
