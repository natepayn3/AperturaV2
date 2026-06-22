import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io 
import Qt.labs.folderlistmodel

Item {
    id: sysTrayContainer
    
    property var parentBarWindow: null
    property var shellTarget: null
    property bool isVertical: shellTarget ? (shellTarget.activeLayoutOrientation === "vertical") : true
    property bool drawerOpen: false

    readonly property real collapsedSize: 34 

    implicitWidth: isVertical ? 32 : (drawerOpen ? trayLayout.implicitWidth + 8 : collapsedSize)
    implicitHeight: isVertical ? (drawerOpen ? trayLayout.implicitHeight + 8 : collapsedSize) : 32

    Timer {
        id: volumeDebounceTimer
        interval: 20 
        repeat: false
    }
    
    Process {
        id: wifiHardwareCheck
        command: ["sh", "-c", "ls /sys/class/net | grep -q '^wl' && echo true || echo false"]
        running: true
        property bool hasAdapter: false
        stdout: StdioCollector {
            onTextChanged: wifiHardwareCheck.hasAdapter = (text.trim() === "true");
        }
    }

    Process {
        id: batteryHardwareCheck
        command: ["sh", "-c", "ls /sys/class/power_supply | grep -q '^BAT' && echo true || echo false"]
        running: true
        property bool hasBattery: false
        stdout: StdioCollector {
            onTextChanged: batteryHardwareCheck.hasBattery = (text.trim() === "true");
        }
    }

    Process {
        id: audioMuteCheck
        command: ["stdbuf", "-oL", "pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("sink")) volumeDebounceTimer.restart();
            }
        }
    }

    Item {
        visible: false

        FolderListModel {
            id: globalWallpaperModel
            folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
            nameFilters: ["*.jpg", "*.png", "*.gif", "*.mp4", "*.webm"]
            showDirs: false
        }

        Repeater {
            model: globalWallpaperModel
            
            delegate: Loader {
                active: index < 15 
                sourceComponent: Component {
                    Image {
                        property string pathStr: String(filePath).toLowerCase()
                        property bool isStatic: !pathStr.endsWith(".mp4") && !pathStr.endsWith(".webm") && !pathStr.endsWith(".gif")
                        
                        source: isStatic ? fileUrl : ""
                        sourceSize: Qt.size(300, 320) 
                        fillMode: Image.PreserveAspectCrop 
                        asynchronous: false 
                    }
                }
            }
        }
    }

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

        Flow {
            id: trayLayout
            anchors.centerIn: parent
            spacing: 8
            flow: sysTrayContainer.isVertical ? Flow.TopToBottom : Flow.LeftToRight

            Rectangle {
                width: 24; height: 24; radius: 4
                color: toggleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (sysTrayContainer.isVertical) return sysTrayContainer.drawerOpen ? "keyboard_arrow_down" : "keyboard_arrow_up";
                        else return sysTrayContainer.drawerOpen ? "keyboard_arrow_right" : "keyboard_arrow_left";
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
                property bool shouldBeVisible: sysTrayContainer.drawerOpen
                clip: true 
                
                width: sysTrayContainer.isVertical ? 24 : (shouldBeVisible ? inlineHardwareLayout.implicitWidth : 0)
                height: sysTrayContainer.isVertical ? (shouldBeVisible ? inlineHardwareLayout.implicitHeight : 0) : 24
                
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Flow {
                    id: inlineHardwareLayout
                    spacing: 8
                    flow: sysTrayContainer.isVertical ? Flow.TopToBottom : Flow.LeftToRight

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
                                        if (sysTrayContainer.parentBarWindow) popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        popupWindow.showBluetooth();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: audioIconWrapper
                        width: 24; height: 24; radius: 4
                        color: audioMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
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
                                        if (sysTrayContainer.parentBarWindow) popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        popupWindow.showAudio();
                                    }
                                }
                            }
                        }
                    }

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
                                        if (sysTrayContainer.parentBarWindow) popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        popupWindow.showWifi();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: batteryIconWrapper
                        width: 24; height: 24; radius: 4
                        color: batteryMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        visible: batteryHardwareCheck.hasBattery

                        Text {
                            anchors.centerIn: parent
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            
                            // 🎯 Dynamically calculate the custom frame variant directly in the tray
                            text: {
                                if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.batteryRef) {
                                    let bat = sysTrayContainer.shellTarget.batteryRef;
                                    if (bat.isCharging) return "battery_android_frame_bolt";
                                    if (bat.capacity >= 95) return "battery_android_frame_full";
                                    if (bat.capacity >= 80) return "battery_android_frame_6";
                                    if (bat.capacity >= 65) return "battery_android_frame_5";
                                    if (bat.capacity >= 50) return "battery_android_frame_4";
                                    if (bat.capacity >= 35) return "battery_android_frame_3";
                                    if (bat.capacity >= 20) return "battery_android_frame_2";
                                    return "battery_android_frame_1";
                                }
                                return "battery_android_frame_full"; // Clean default fallback state
                            }
                            
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.batteryRef && sysTrayContainer.shellTarget.batteryRef.active)
                                ? sysTrayContainer.shellTarget.colorAccent
                                : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea { 
                            id: batteryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.batteryRef) {
                                    let popupWindow = sysTrayContainer.shellTarget.batteryRef;
                                    if (popupWindow.active) {
                                        popupWindow.forceDismiss();
                                    } else {
                                        let globalPos = batteryIconWrapper.mapToItem(null, 0, 0);
                                        popupWindow.hoverOriginX = globalPos.x;
                                        popupWindow.hoverOriginY = globalPos.y;
                                        if (sysTrayContainer.parentBarWindow) {
                                            popupWindow.screen = sysTrayContainer.parentBarWindow.screen;
                                        }
                                        popupWindow.showBattery();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: launcherIconWrapper
                        width: 24; height: 24; radius: 4
                        color: launcherMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "apps"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.launcherRef && sysTrayContainer.shellTarget.launcherRef.active) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: launcherMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.launcherRef) sysTrayContainer.shellTarget.launcherRef.active = !sysTrayContainer.shellTarget.launcherRef.active;
                        }
                    }

                    Rectangle {
                        id: wallpaperIconWrapper
                        width: 24; height: 24; radius: 4
                        color: wallpaperMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "wallpaper"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.wallpaperRef && sysTrayContainer.shellTarget.wallpaperRef.active) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: wallpaperMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.wallpaperRef) sysTrayContainer.shellTarget.wallpaperRef.active = !sysTrayContainer.shellTarget.wallpaperRef.active;
                        }
                    }

                    Rectangle {
                        id: settingsIconWrapper
                        width: 24; height: 24; radius: 4
                        color: settingsMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "settings"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.settingsAppRef && sysTrayContainer.shellTarget.settingsAppRef.windowVisible) ? sysTrayContainer.shellTarget.colorAccent : sysTrayContainer.shellTarget.colorText
                        }

                        MouseArea {
                            id: settingsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (sysTrayContainer.shellTarget && sysTrayContainer.shellTarget.settingsAppRef) sysTrayContainer.shellTarget.settingsAppRef.windowVisible = !sysTrayContainer.shellTarget.settingsAppRef.windowVisible;
                        }
                    }
                }
            }
        }
    }
}
