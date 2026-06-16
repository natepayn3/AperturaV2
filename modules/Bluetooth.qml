import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: bluetoothRoot

    property string namespace: "quickshell-bluetooth-popup"
    property bool active: false
    
    // Unified Hover Logic mirroring original Calendar architecture spec
    property bool isHovered: popupHoverArea.containsMouse || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real maxCardHeight: 440

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)
    opacity: 1.0
    visible: true
    clip: false

    // --- Dynamic Root Anchoring ---
    x: rootShell.barPosition === "right" 
       ? hoverOriginX - width 
       : (rootShell.barPosition === "left" ? hoverOriginX + 35 : hoverOriginX) 
       
    y: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left" || rootShell.barPosition === "right") 
       ? hoverOriginY - height + 94
       : hoverOriginY

    // --- State Management ---
    property bool isPowered: false
    property bool isScanning: false
    property string activeController: "Unknown"
    property var deviceModel: []

    // --- Core Bluetooth Processes via absolute path allocations ---
    Process {
        id: stateFetcher
        command: ["/usr/bin/bluetoothctl", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let textLines = this.text.split("\n");
                let powered = false;
                let discovering = false;
                let name = "Unknown";
                
                for (let line of textLines) {
                    if (line.includes("Powered: yes")) powered = true;
                    if (line.includes("Discovering: yes")) discovering = true;
                    if (line.includes("Name:")) name = line.replace(/.*Name:\s*/, "").trim();
                }
                
                bluetoothRoot.isPowered = powered;
                bluetoothRoot.isScanning = discovering;
                bluetoothRoot.activeController = name;
                stateFetcher.running = false;
                
                if (powered) deviceFetcher.running = true;
            }
        }
    }

    Process {
        id: deviceFetcher
        command: ["/usr/bin/bluetoothctl", "devices"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                let parsedDevices = [];
                
                for (let line of lines) {
                    let match = line.match(/^Device\s+([0-9A-Fa-f:]+)\s+(.*)$/);
                    if (match) {
                        parsedDevices.push({
                            "mac": match[1],
                            "name": match[2],
                            "connected": false
                        });
                    }
                }
                bluetoothRoot.deviceModel = parsedDevices;
                deviceFetcher.running = false;
                
                if (parsedDevices.length > 0) connectionVerifier.running = true;
            }
        }
    }

    Process {
        id: connectionVerifier
        command: ["/usr/bin/bluetoothctl", "info"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let updatedModel = [...bluetoothRoot.deviceModel];
                for (let i = 0; i < updatedModel.length; i++) {
                    if (this.text.includes(updatedModel[i].mac) && this.text.includes("Connected: yes")) {
                        updatedModel[i].connected = true;
                    }
                }
                bluetoothRoot.deviceModel = updatedModel;
                connectionVerifier.running = false;
            }
        }
    }

    Process { id: togglePowerProc; running: false }
    Process { id: toggleScanProc; running: false }
    Process { id: deviceActionProc; running: false }

    function togglePower() {
        togglePowerProc.command = ["/usr/bin/bluetoothctl", bluetoothRoot.isPowered ? "power off" : "power on"];
        togglePowerProc.running = true;
        stateFetcher.running = true;
    }

    function toggleScan() {
        if (!bluetoothRoot.isPowered) return;
        toggleScanProc.command = ["/usr/bin/bluetoothctl", bluetoothRoot.isScanning ? "scan off" : "scan on"];
        toggleScanProc.running = true;
        stateFetcher.running = true;
    }

    function handleDeviceClick(mac, isConnected) {
        let mode = isConnected ? "disconnect" : "connect";
        deviceActionProc.command = ["/usr/bin/bluetoothctl", mode, mac];
        deviceActionProc.running = true;
        stateFetcher.running = true;
    }

    onActiveChanged: {
        if (active) {
            stateFetcher.running = true;
        }
    }

    // --- Visuals & Animations ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft  // Cloned from Calendar "bottom"
            if (rootShell.barPosition === "right") return Item.TopRight
            if (rootShell.barPosition === "top") return Item.TopLeft
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        states: [
            State {
                name: "hidden"
                when: !bluetoothRoot.active
                PropertyChanges { target: animatedGroup; opacity: 0.0; scale: 0.0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 0.0 }
                PropertyChanges { 
                    target: animatedGroup
                    x: {
                        switch (rootShell.barPosition) {
                            case "left":   return -40; // Cloned from Calendar "bottom"
                            case "bottom": return -40; 
                            case "right":  return 40;  
                            case "top":    return -40; 
                            default:       return 0;
                        }
                    }
                    y: {
                        switch (rootShell.barPosition) {
                            case "left":   return 40;  // Cloned from Calendar "bottom"
                            case "bottom": return 40;  
                            case "right":  return -40; 
                            case "top":    return -40; 
                            default:       return 0;
                        }
                    }
                }
            },
            State {
                name: "shown"
                when: bluetoothRoot.active
                PropertyChanges { target: animatedGroup; opacity: 1.0; scale: 1.0; x: 0; y: 0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 1.0 }
            }
        ]

        transitions: [
            Transition {
                from: "hidden"; to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 200 } 
                        NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 200; easing.type: Easing.InQuad }
                    }
                }
            },
            Transition {
                from: "shown"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 100 }
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                }
            }
        ]

        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            color: rootShell.colorBackground
            z: 2
            
            border.width: 0
            border.color: "transparent"

            // Mapped left to exactly match Calendar's bottom corner rounding
            topLeftRadius: 0
            topRightRadius: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left") ? bluetoothRoot.radiusValue : 0
            bottomLeftRadius: rootShell.barPosition === "right" ? bluetoothRoot.radiusValue : 0
            bottomRightRadius: rootShell.barPosition === "top" ? bluetoothRoot.radiusValue : 0
        }

        // --- Wings Component ---
        Item {
            anchors.fill: parent
            visible: bluetoothRoot.width > 30
            z: 2 

            // Exact 1:1 copy of Calendar's "bottom" wing code, applied to both left and bottom
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left" || rootShell.barPosition === "bottom"

                Shape {
                    x: 0; y: -bluetoothRoot.wingSize
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: bluetoothRoot.wingSize
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: bluetoothRoot.wingSize }
                        PathLine { x: 0; y: bluetoothRoot.wingSize }
                    }
                }
                Shape {
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    x: parent.width
                    y: parent.height
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: bluetoothRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            // Original Calendar "top" wing code
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                Shape {
                    x: 0; y: parent.height
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: bluetoothRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: 0; y: bluetoothRoot.wingSize }
                        PathQuad { x: bluetoothRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            // Original Calendar "right" wing code
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: -bluetoothRoot.wingSize; y: 0
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: bluetoothRoot.wingSize; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: bluetoothRoot.wingSize; controlY: 0 }
                        PathLine { x: bluetoothRoot.wingSize; y: 0 }
                    }
                }
                
                Shape {
                    x: parent.width - bluetoothRoot.wingSize; y: parent.height
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: bluetoothRoot.wingSize; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: bluetoothRoot.wingSize; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        // Structural background hover area intercepts clicks inside card boundary
        MouseArea { 
            id: popupHoverArea
            anchors.fill: parent 
            hoverEnabled: true 
            z: 1
        }

        // --- Internal System Content View ---
        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 18
            z: 5

            HoverHandler { id: contentHoverHandler }

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text { 
                        text: "Bluetooth"
                        font.family: rootShell.shellFont; font.pixelSize: 16; font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: refreshMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                        Text { 
                            anchors.centerIn: parent; text: "refresh"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 18
                            color: rootShell.colorAccent
                        }
                        MouseArea {
                            id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: stateFetcher.running = true
                        }
                    }

                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: scanMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                        Text { 
                            anchors.centerIn: parent
                            text: bluetoothRoot.isScanning ? "radar" : "search"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 18
                            color: bluetoothRoot.isScanning ? rootShell.colorAccent : rootShell.colorSubtext
                        }
                        MouseArea {
                            id: scanMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: bluetoothRoot.toggleScan()
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: !bluetoothRoot.isPowered
                            text: "Adapter Powered Off"
                            font.family: rootShell.shellFont; font.pixelSize: 13
                            color: rootShell.colorSubtext
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 40
                        }

                        Repeater {
                            model: bluetoothRoot.isPowered ? bluetoothRoot.deviceModel : 0
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 8
                                color: itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent"
                                border.width: modelData.connected ? 1 : 0
                                border.color: rootShell.colorAccent

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Math.round(8)
                                    spacing: 10

                                    Text {
                                        text: modelData.connected ? "bluetooth_connected" : "bluetooth"
                                        font.family: "Material Symbols Outlined"; font.pixelSize: 18
                                        color: modelData.connected ? rootShell.colorAccent : "#ffffff"
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.name !== "" ? modelData.name : modelData.mac
                                            font.family: rootShell.shellFont; font.pixelSize: 13; font.weight: Font.Medium
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.mac
                                            font.family: rootShell.shellFont; font.pixelSize: 10
                                            color: rootShell.colorSubtext
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: bluetoothRoot.handleDeviceClick(modelData.mac, modelData.connected)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255,255,255,0.1)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56

                    RowLayout {
                        anchors.fill: parent; spacing: 14

                        Text {
                            text: bluetoothRoot.isPowered ? "bluetooth" : "bluetooth_disabled"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 32
                            color: bluetoothRoot.isPowered ? rootShell.colorAccent : rootShell.colorClose
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true

                            Text {
                                text: bluetoothRoot.activeController
                                font.family: rootShell.shellFont; font.pixelSize: 14; font.weight: Font.Bold
                                color: "#ffffff"
                                elide: Text.ElideRight
                            }

                            Text {
                                text: bluetoothRoot.isScanning ? "Scanning for devices..." : "Radio Idle"
                                font.family: rootShell.shellFont; font.pixelSize: 12
                                color: "#ffffff"; opacity: 0.6
                            }
                        }

                        Switch {
                            id: powerSwitch
                            checked: bluetoothRoot.isPowered
                            onPositionChanged: {
                                if ((checked && !bluetoothRoot.isPowered) || (!checked && bluetoothRoot.isPowered)) {
                                    bluetoothRoot.togglePower();
                                }
                            }
                            
                            indicator: Rectangle {
                                implicitWidth: 42; implicitHeight: 24
                                x: powerSwitch.leftPadding; y: parent.height / 2 - height / 2
                                radius: 12
                                color: powerSwitch.checked ? rootShell.colorAccent : "transparent"
                                border.color: powerSwitch.checked ? rootShell.colorAccent : rootShell.colorBorder
                                border.width: 2

                                Rectangle {
                                    x: powerSwitch.checked ? parent.width - width - 4 : 4
                                    y: parent.height / 2 - height / 2
                                    width: 14; height: 14; radius: 7
                                    color: powerSwitch.checked ? rootShell.colorBackground : rootShell.colorSubtext
                                    
                                    Behavior on x {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
