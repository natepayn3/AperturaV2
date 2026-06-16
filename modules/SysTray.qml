import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item {
    id: sysTrayContainer
    
    property var parentBarWindow: null
    property var shellTarget: null
    property bool isVertical: shellTarget ? (shellTarget.activeLayoutOrientation === "vertical") : true

    property bool drawerOpen: false

    readonly property real expandedSize: trayLayout.implicitHeight + 8
    readonly property real collapsedSize: 34 

    implicitWidth: isVertical ? 32 : (drawerOpen ? trayLayout.implicitWidth + 8 : collapsedSize)
    implicitHeight: isVertical ? (drawerOpen ? expandedSize : collapsedSize) : 32

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

    Rectangle {
        id: moduleBackground
        anchors.fill: parent
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.03)
        border.width: 0
        border.color: sysTrayContainer.shellTarget ? sysTrayContainer.shellTarget.colorBorder : "transparent"
        z: 0
    }

    Item {
        anchors.fill: parent
        clip: true
        z: 1

        Grid {
            id: trayLayout
            anchors.centerIn: parent
            columns: isVertical ? 1 : -1
            rows: isVertical ? -1 : 1
            spacing: 8

            Rectangle {
                width: 24; height: 24; radius: 4
                color: toggleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (sysTrayContainer.isVertical) {
                            return sysTrayContainer.drawerOpen ? "keyboard_arrow_down" : "keyboard_arrow_up";
                        } else {
                            return sysTrayContainer.drawerOpen ? "keyboard_arrow_right" : "keyboard_arrow_left";
                        }
                    }
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 16
                    color: sysTrayContainer.shellTarget ? sysTrayContainer.shellTarget.colorAccent : "#ffffff"
                }

                MouseArea {
                    id: toggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sysTrayContainer.drawerOpen = !sysTrayContainer.drawerOpen
                }
            }

            Item {
                id: collapsibleGroup
                width: sysTrayContainer.isVertical ? 24 : (sysTrayContainer.drawerOpen ? inlineHardwareLayout.implicitWidth : 0)
                height: sysTrayContainer.isVertical ? (sysTrayContainer.drawerOpen ? inlineHardwareLayout.implicitHeight : 0) : 24
                visible: opacity > 0.0
                opacity: sysTrayContainer.drawerOpen ? 1.0 : 0.0
                
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Grid {
                    id: inlineHardwareLayout
                    columns: sysTrayContainer.isVertical ? 1 : -1
                    rows: sysTrayContainer.isVertical ? -1 : 1
                    spacing: 8

                    Rectangle {
                        id: bluetoothIconWrapper
                        width: 24; height: 24; radius: 4
                        color: bluetoothMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.bluetoothRef && sysTrayContainer.shellTarget.bluetoothRef.bluetoothActive) ? "bluetooth_connected" : "bluetooth"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.bluetoothRef && sysTrayContainer.shellTarget.bluetoothRef.bluetoothActive) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: bluetoothMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.bluetoothRef) {
                                    let popupWindow = sysTrayContainer.shellTarget.bluetoothRef;
                                    
                                    if (popupWindow.bluetoothActive) {
                                        popupWindow.forceDismiss();
                                    } else {
                                        let globalPos = bluetoothIconWrapper.mapToItem(null, 0, 0);
                                        popupWindow.hoverOriginX = globalPos.x;
                                        popupWindow.hoverOriginY = globalPos.y;
                                        
                                        popupWindow.showBluetooth();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: wifiIconWrapper
                        width: 24; height: 24; radius: 4
                        color: wifiMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Text {
                            anchors.centerIn: parent; text: "wifi"; font.family: "Material Symbols Outlined"; font.pixelSize: 16
                            color: sysTrayContainer.shellTarget ? sysTrayContainer.shellTarget.colorText : "#ffffff"
                        }
                        MouseArea { id: wifiMouse; anchors.fill: parent; hoverEnabled: true }
                    }

                    Rectangle {
                        id: batteryIconWrapper
                        width: 24; height: 24; radius: 4
                        color: batteryMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Text {
                            anchors.centerIn: parent; text: "battery_full"; font.family: "Material Symbols Outlined"; font.pixelSize: 16
                            color: sysTrayContainer.shellTarget ? sysTrayContainer.shellTarget.colorText : "#ffffff"
                        }
                        MouseArea { id: batteryMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }
}
