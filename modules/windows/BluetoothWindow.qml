import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: bluetoothWindow
    
    required property var rootShell
    property bool bluetoothActive: false
    readonly property var cardRef: innerBluetoothCard

    screen: Quickshell.screens[0] 
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bluetooth-preview"
    WlrLayershell.keyboardFocus: bluetoothActive ? WlrLayershell.OnDemand : WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: bluetoothActive || rootShell.bluetoothProgress > 0.0
    color: "transparent"

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        enabled: bluetoothWindow.bluetoothActive
        onPressed: (mouse) => {
            bluetoothWindow.forceDismiss();
            mouse.accepted = false;
        }
    }

    function showBluetooth() { 
        if (!bluetoothActive) {
            rootShell.closeAllPopups();
            
            // Safely check if the timer exists before stopping it
            if (rootShell.bluetoothDismissTimer) {
                rootShell.bluetoothDismissTimer.stop(); 
            }
            
            bluetoothActive = true; 
            showBluetoothAnim.restart();
            innerBluetoothCard.forceActiveFocus();
        }
    }
    
    function forceDismiss() {
        bluetoothActive = false;
        hideBluetoothAnim.restart();
    }

    Shortcut {
        sequence: "Escape"
        enabled: bluetoothWindow.bluetoothActive
        onActivated: bluetoothWindow.forceDismiss()
    }

    ParallelAnimation {
        id: showBluetoothAnim
        NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideBluetoothAnim
        NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: bluetoothWindow; property: "bluetoothActive"; value: false }
    }

    Bluetooth {
        id: innerBluetoothCard
        active: bluetoothWindow.bluetoothActive
        hoverOriginX: bluetoothWindow.hoverOriginX
        hoverOriginY: bluetoothWindow.hoverOriginY
    }
}
