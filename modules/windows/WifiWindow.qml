import QtQuick
import Quickshell
import Quickshell.Wayland
import "../" 

PanelWindow {
    id: wifiWindow
    
    required property var rootShell
    property bool wifiActive: false
    readonly property var cardRef: innerWifiCard

    screen: Quickshell.screens[0] 
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-wifi-preview"
    WlrLayershell.keyboardFocus: wifiActive ? WlrLayershell.OnDemand : WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: wifiActive || rootShell.wifiProgress > 0.0
    color: "transparent"

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    // 🛡️ Defend against shell.qml instant-close loops
    Timer {
        id: lockoutTimer
        interval: 100
        running: false
        repeat: false
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        enabled: wifiWindow.wifiActive
        onPressed: (mouse) => {
            wifiWindow.forceDismiss();
            mouse.accepted = false;
        }
    }

    function showWifi() { 
        if (!wifiActive) {
            // Lock the dismissal gate for 100ms so shell.qml can't instantly kill the window
            lockoutTimer.restart(); 
            rootShell.closeAllPopups();
            wifiActive = true; 
            showWifiAnim.restart();
            innerWifiCard.forceActiveFocus();
        }
    }
    
    function forceDismiss() {
        // If the lockout timer is running, ignore rogue dismiss commands from the shell event loop
        if (lockoutTimer.running) return; 
        
        wifiActive = false;
        hideWifiAnim.restart();
    }

    Shortcut {
        sequence: "Escape"
        enabled: wifiWindow.wifiActive
        onActivated: wifiWindow.forceDismiss()
    }

    ParallelAnimation {
        id: showWifiAnim
        NumberAnimation { target: rootShell; property: "wifiProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideWifiAnim
        NumberAnimation { target: rootShell; property: "wifiProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: wifiWindow; property: "wifiActive"; value: false }
    }

    Wifi {
        id: innerWifiCard
        active: wifiWindow.wifiActive
        hoverOriginX: wifiWindow.hoverOriginX
        hoverOriginY: wifiWindow.hoverOriginY
    }
}
