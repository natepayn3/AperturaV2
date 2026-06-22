import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

Item {
    id: batteryRoot

    property bool active: false
    property bool isHovered: animatedGroup.isHovered || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real baseLayoutHeight: 140

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(baseLayoutHeight)
    width: Math.round(maxCardWidth)
    height: implicitHeight

    // Coordinate mapping matching Audio.qml
    x: {
        if (rootShell.barPosition === "top") return Screen.width - width - 10;
        if (rootShell.barPosition === "bottom") return Screen.width - width - 10;
        if (rootShell.barPosition === "right") return Screen.width - width - 46;
        if (rootShell.barPosition === "left") return 46; 
        return hoverOriginX; 
    }

    y: {
        switch (rootShell.barPosition) {
            case "bottom": return Screen.height - height - 46;
            case "top":    return 46;                             
            case "left":   return Screen.height - height - 10;       
            case "right":  return Screen.height - height - 10;
            default:       return hoverOriginY;
        }
    }

    // --- Live Data Tracking ---
    property int capacity: 0
    property string status: "Unknown"
    property bool isCharging: false
    property string supplyNode: "" // 🎯 Start empty to prevent default BAT0 lookups on boot

    // Icon sets mapped exactly to your specifications
    readonly property string batteryIcon: {
        if (isCharging) return "battery_android_frame_bolt";
        if (capacity >= 95) return "battery_android_frame_full";
        if (capacity >= 80) return "battery_android_frame_6";
        if (capacity >= 65) return "battery_android_frame_5";
        if (capacity >= 50) return "battery_android_frame_4";
        if (capacity >= 35) return "battery_android_frame_3";
        if (capacity >= 20) return "battery_android_frame_2";
        return "battery_android_frame_1";
    }

    readonly property string statusText: {
        if (isCharging) return "Charging";
        if (status === "Full") return "Fully Charged";
        if (status === "Discharging") return "Discharging";
        return status;
    }

    // --- Dynamic Target File Path Detectors ---
    FileView {
        id: capacityReader
        path: batteryRoot.supplyNode !== "" ? "/sys/class/power_supply/" + batteryRoot.supplyNode + "/capacity" : ""
        onTextChanged: {
            let val = parseInt(text().trim());
            if (!isNaN(val)) batteryRoot.capacity = Math.max(0, Math.min(100, val));
        }
    }

    FileView {
        id: statusReader
        path: batteryRoot.supplyNode !== "" ? "/sys/class/power_supply/" + batteryRoot.supplyNode + "/status" : ""
        onTextChanged: {
            let cleanStatus = text().trim();
            batteryRoot.status = cleanStatus;
            batteryRoot.isCharging = (cleanStatus === "Charging");
        }
    }

    // Hardware supply system target scanner
    Process {
        id: detectBatteryNodeProc
        command: ["sh", "-c", "ls /sys/class/power_supply | grep -m1 '^BAT'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let node = this.text.trim();
                if (node !== "") {
                    batteryRoot.supplyNode = node;
                    // Trigger initial manual reloads on verified path bindings
                    capacityReader.reload();
                    statusReader.reload();
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 10000
        running: batteryRoot.active && batteryRoot.supplyNode !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            capacityReader.reload();
            statusReader.reload();
        }
    }

    onActiveChanged: {
        if (active && batteryRoot.supplyNode !== "") {
            capacityReader.reload();
            statusReader.reload();
        }
    }

    Component.onCompleted: {
        detectBatteryNodeProc.running = true;
    }

    AnimatedCard {
        id: animatedGroup
        anchors.fill: parent
        
        barPosition: rootShell.barPosition
        backgroundColor: rootShell.colorBackground
        
        active: batteryRoot.active
        radiusValue: batteryRoot.radiusValue
        wingSize: batteryRoot.wingSize
        targetWidth: batteryRoot.width
        targetHeight: batteryRoot.height

        Item {
            id: layoutContentWrapper
            anchors.fill: parent

            HoverHandler { id: contentHoverHandler }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    Rectangle {
                        width: 56; height: 56; radius: 12
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.rgba(255, 255, 255, 0.03)

                        Text {
                            anchors.centerIn: parent
                            text: batteryRoot.batteryIcon
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 36
                            color: batteryRoot.isCharging 
                                ? "#a6e3a1"
                                : (batteryRoot.capacity <= 20 ? rootShell.colorClose : rootShell.colorAccent)
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter

                        RowLayout {
                            spacing: 8
                            Text {
                                text: batteryRoot.capacity + "%"
                                font.family: rootShell.shellFont
                                font.pixelSize: 24
                                font.weight: Font.Bold
                                color: "#ffffff"
                            }
                        }

                        Text {
                            text: batteryRoot.statusText
                            font.family: rootShell.shellFont
                            font.pixelSize: 13
                            color: batteryRoot.isCharging ? "#a6e3a1" : rootShell.colorSubtext
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255, 255, 255, 0.1)
                }

                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        Rectangle {
                            id: progressBarBg
                            Layout.fillWidth: true
                            height: 8; radius: 4
                            color: Qt.rgba(255, 255, 255, 0.1)

                            Rectangle {
                                width: (batteryRoot.capacity / 100.0) * parent.width
                                height: parent.height; radius: 4
                                color: batteryRoot.isCharging 
                                    ? "#a6e3a1"
                                    : (batteryRoot.capacity <= 20 ? rootShell.colorClose : rootShell.colorAccent)

                                Behavior on width { 
                                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
