import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io 

Item {
    id: sysTrayContainer
    
    // Public tracking pointer assigned by the VerticalBar layout wrapper
    property var parentBarWindow: null
    
    property var shellTarget: null
    property bool isVertical: shellTarget ? (shellTarget.activeLayoutOrientation === "vertical") : true

    // State property to track drawer status
    property bool drawerOpen: false

    // Target tracking height limits calculated dynamically
    readonly property real expandedSize: trayLayout.implicitHeight + 8
    readonly property real collapsedSize: 34 // Size of just the toggle button + padding

    // Dimensions switch based on structural orientation vectors
    implicitWidth: isVertical ? 32 : (drawerOpen ? trayLayout.implicitWidth + 8 : collapsedSize)
    implicitHeight: isVertical ? (drawerOpen ? expandedSize : collapsedSize) : 32

    // --- Hardware Adapter Engines ---
    Process {
        id: wifiHardwareCheck
        // Scans sysfs for wireless interfaces (wlan0, wlp3s0, etc.)
        command: ["sh", "-c", "ls /sys/class/net | grep -q '^wl' && echo true || echo false"]
        running: true

        property bool hasAdapter: false

        stdout: StdioCollector {
            onTextChanged: {
                wifiHardwareCheck.hasAdapter = (text.trim() === "true");
            }
        }
    }

    Process {
        id: batteryHardwareCheck
        // Checks if a battery sub-system directory exists under power_supply
        command: ["sh", "-c", "ls /sys/class/power_supply | grep -q '^BAT' && echo true || echo false"]
        running: true

        property bool hasBattery: false

        stdout: StdioCollector {
            onTextChanged: {
                batteryHardwareCheck.hasBattery = (text.trim() === "true");
            }
        }
    }

    // --- Audio State Engine (Event-Driven & Isolated) ---
    Process {
        id: audioMuteCheck
        // Let the shell stream events natively, handle the logic in QML
        command: ["stdbuf", "-oL", "pactl", "subscribe"]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("sink")) {
                    // Trigger a debounced QML timer here to fetch volume
                    // instead of forking bash inside the stream
                    volumeDebounceTimer.restart();
                }
            }
        }
    }

    // Smooth physics mapping transitions
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

    // Force strict layout boundaries during animation cycles
    Item {
        anchors.fill: parent
        clip: true
        z: 1

        Flow {
            id: trayLayout
            anchors.centerIn: parent
            spacing: 8
            flow: sysTrayContainer.isVertical ? Flow.TopToBottom : Flow.LeftToRight

            // --- Drawer Toggle Button Module ---
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

            // --- Collapsible Status Group Layout ---
            Item {
                id: collapsibleGroup
                
                // Keep the drawer locked open when toggled or when Bluetooth window is active
                property bool shouldBeVisible: sysTrayContainer.drawerOpen
                
                width: sysTrayContainer.isVertical ? 24 : (shouldBeVisible ? inlineHardwareLayout.implicitWidth : 0)
                height: sysTrayContainer.isVertical ? (shouldBeVisible ? inlineHardwareLayout.implicitHeight : 0) : 24
                visible: opacity > 0.0
                opacity: shouldBeVisible ? 1.0 : 0.0
                
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Flow {
                    id: inlineHardwareLayout
                    spacing: 8
                    flow: sysTrayContainer.isVertical ? Flow.TopToBottom : Flow.LeftToRight

                    // Bluetooth Status Node
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
                                        
                                        // Pass the screen context of the bar window to the popup module
                                        if (sysTrayContainer.parentBarWindow) {
                                            popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        }
                                        
                                        popupWindow.showBluetooth();
                                    }
                                }
                            }
                        }
                    }

                    // Audio Status Node
                    Rectangle {
                        id: audioIconWrapper
                        width: 24; height: 24; radius: 4
                        color: audioMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            // Bound directly to our isolated event-driven process property
                            text: audioMuteCheck.isMuted ? "volume_off" : "volume_up"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.audioRef && sysTrayContainer.shellTarget.audioRef.audioActive) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: audioMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.audioRef) {
                                    let popupWindow = sysTrayContainer.shellTarget.audioRef;
                                    
                                    if (popupWindow.audioActive) {
                                        popupWindow.forceDismiss();
                                    } else {
                                        let globalPos = audioIconWrapper.mapToItem(null, 0, 0);
                                        popupWindow.hoverOriginX = globalPos.x;
                                        popupWindow.hoverOriginY = globalPos.y;
                                        
                                        // Pass the screen context of the bar window to the popup module
                                        if (sysTrayContainer.parentBarWindow) {
                                            popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        }
                                        
                                        popupWindow.showAudio();
                                    }
                                }
                            }
                        }
                    }

                    // Network Wi-Fi Component Node
                    Rectangle {
                        id: wifiIconWrapper
                        width: 24; height: 24; radius: 4
                        color: wifiMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        
                        visible: wifiHardwareCheck.hasAdapter
                        
                        Text {
                            anchors.centerIn: parent
                            text: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.wifiRef && sysTrayContainer.shellTarget.wifiRef.wifiActive) ? "signal_wifi_4_bar" : "wifi"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.wifiRef && sysTrayContainer.shellTarget.wifiRef.wifiActive) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: wifiMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.wifiRef) {
                                    let popupWindow = sysTrayContainer.shellTarget.wifiRef;
                                    
                                    if (popupWindow.wifiActive) {
                                        popupWindow.forceDismiss();
                                    } else {
                                        let globalPos = wifiIconWrapper.mapToItem(null, 0, 0);
                                        popupWindow.hoverOriginX = globalPos.x;
                                        popupWindow.hoverOriginY = globalPos.y;
                                        
                                        // Pass the screen context of the bar window to the popup module
                                        if (sysTrayContainer.parentBarWindow) {
                                            popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        }
                                        
                                        popupWindow.showWifi();
                                    }
                                }
                            }
                        }
                    }

                    // Battery Status Component Node
                    Rectangle {
                        id: batteryIconWrapper
                        width: 24; height: 24; radius: 4
                        color: batteryMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        
                        visible: batteryHardwareCheck.hasBattery

                        Text {
                            anchors.centerIn: parent; text: "battery_android_frame_full"; font.family: "Material Symbols Outlined"; font.pixelSize: 16
                            color: sysTrayContainer.shellTarget ? sysTrayContainer.shellTarget.colorText : "#ffffff"
                        }
                        MouseArea { id: batteryMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }
}
