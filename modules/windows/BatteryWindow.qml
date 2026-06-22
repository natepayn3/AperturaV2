import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: batteryWindow
    
    required property var rootShell
    property bool active: false
    readonly property var cardRef: innerBatteryCard

    screen: Quickshell.screens[0] 
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-battery-preview"
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    // Full screen mapping allows the MouseArea to catch outside clicks
    anchors { left: true; right: true; top: true; bottom: true }
    visible: active || (rootShell && rootShell.batteryProgress > 0.0)
    color: "transparent"

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    // Full screen mask to click-to-dismiss when clicking anywhere outside the card boundaries
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        enabled: batteryWindow.active
        onPressed: (mouse) => {
            batteryWindow.forceDismiss();
            mouse.accepted = false;
        }
    }

    function showBattery() { 
        if (!active) {
            rootShell.closeAllPopups();
            
            if (rootShell.batteryDismissTimer) {
                rootShell.batteryDismissTimer.stop(); 
            }
            
            active = true; 
            showBatteryAnim.restart();
            innerBatteryCard.forceActiveFocus();
        }
    }
    
    function forceDismiss() {
        active = false;
        hideBatteryAnim.restart();
    }

    Shortcut {
        sequence: "Escape"
        enabled: batteryWindow.active
        onActivated: batteryWindow.forceDismiss()
    }

    ParallelAnimation {
        id: showBatteryAnim
        NumberAnimation { target: rootShell; property: "batteryProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideBatteryAnim
        NumberAnimation { target: rootShell; property: "batteryProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: batteryWindow; property: "active"; value: false }
    }

    Battery {
        id: innerBatteryCard
        active: batteryWindow.active
        hoverOriginX: batteryWindow.hoverOriginX
        hoverOriginY: batteryWindow.hoverOriginY
    }
}
