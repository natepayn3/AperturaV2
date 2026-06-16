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

    x: rootShell.barPosition === "right" 
       ? hoverOriginX - width 
       : (rootShell.barPosition === "left" ? hoverOriginX + 35 : hoverOriginX) 
       
    y: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left" || rootShell.barPosition === "right") 
       ? hoverOriginY - height + 94
       : hoverOriginY

    // --- State Management ---
    property bool isPowered: false
    property bool isScanning: false
    property string activeStatusText: "Bluetooth is ON"
    property var deviceModel: []

    // --- Core Bluetooth Processes ---
    Process {
        id: stateFetcher
        command: ["/usr/bin/bluetoothctl", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (togglePowerProc.running || toggleScanProc.running) { stateFetcher.running = false; return; }
                
                let textLines = this.text.replace(/\r/g, "").split("\n");
                let powered = false;
                let discovering = false;
                
                for (let line of textLines) {
                    let cleanLine = line.trim();
                    if (cleanLine.includes("Powered: yes")) powered = true;
                    if (cleanLine.includes("Discovering: yes")) discovering = true;
                }
                
                bluetoothRoot.isPowered = powered;
                bluetoothRoot.isScanning = discovering;
                
                if (!powered) {
                    bluetoothRoot.activeStatusText = "Bluetooth is OFF";
                    bluetoothRoot.deviceModel = [];
                } else if (discovering) {
                    bluetoothRoot.activeStatusText = "Scanning for devices...";
                } else {
                    bluetoothRoot.activeStatusText = scanDurationTimer.running ? "Scanning for devices..." : "Bluetooth is ON";
                }
                
                stateFetcher.running = false;
                if (powered && !togglePowerProc.running && !toggleScanProc.running) deviceFetcher.running = true;
            }
        }
    }

    Process {
        id: deviceFetcher
        command: ["/usr/bin/bluetoothctl", "devices"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (togglePowerProc.running || !bluetoothRoot.isPowered || toggleScanProc.running) { deviceFetcher.running = false; return; }
                let lines = this.text.replace(/\r/g, "").split("\n");
                let parsedDevices = [];
                
                for (let line of lines) {
                    let match = line.trim().match(/^Device\s+([0-9A-Fa-f:]+)\s+(.*)$/);
                    if (match) {
                        parsedDevices.push({
                            "mac": match[1],
                            "name": match[2].trim(),
                            "connected": false
                        });
                    }
                }
                bluetoothRoot.deviceModel = parsedDevices;
                deviceFetcher.running = false;
                
                if (parsedDevices.length > 0 && bluetoothRoot.isPowered && !togglePowerProc.running && !toggleScanProc.running) connectionVerifier.running = true;
            }
        }
    }

    Process {
        id: connectionVerifier
        command: ["/usr/bin/bluetoothctl", "info"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (!bluetoothRoot.isPowered || togglePowerProc.running || toggleScanProc.running) { connectionVerifier.running = false; return; }
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

    Process { 
        id: togglePowerProc
        running: false 
        onRunningChanged: { if (!running) stateFetcherTimer.restart(); }
    }
    
    // 🎯 FIX: Explicitly sync state strings when scanning engine runs down
    Process { 
        id: toggleScanProc
        running: false 
        onRunningChanged: { if (!running) stateFetcherTimer.restart(); }
    }
    
    Process { id: deviceActionProc; running: false }

    Timer {
        id: scanDurationTimer
        interval: 10000
        repeat: false
        onTriggered: {
            bluetoothRoot.isScanning = false;
            bluetoothRoot.activeStatusText = "Bluetooth is ON";
            toggleScanProc.command = ["/usr/bin/bluetoothctl", "scan", "off"];
            toggleScanProc.running = true;
        }
    }

    Timer {
        id: stateFetcherTimer
        interval: 300
        repeat: false
        onTriggered: stateFetcher.running = true
    }

    function triggerScan() {
        if (!bluetoothRoot.isPowered || togglePowerProc.running || toggleScanProc.running) return;
        scanDurationTimer.stop();
        bluetoothRoot.activeStatusText = "Scanning for devices...";
        toggleScanProc.command = ["/usr/bin/bluetoothctl", "scan", "on"];
        toggleScanProc.running = true;
        scanDurationTimer.start();
    }

    function togglePower() {
        if (togglePowerProc.running || toggleScanProc.running) return;
        scanDurationTimer.stop();
        
        let turningOn = !bluetoothRoot.isPowered;
        deviceFetcher.running = false;
        connectionVerifier.running = false;
        
        if (!turningOn) {
            bluetoothRoot.activeStatusText = "Bluetooth is OFF";
            bluetoothRoot.deviceModel = [];
            // 🎯 FIX: Clear the scanning states immediately before execution to ensure sequential delivery
            bluetoothRoot.isScanning = false; 
            
            // Execute absolute chain task block to force kill active hardware loops safely
            toggleScanProc.command = ["/usr/bin/bluetoothctl", "scan", "off"];
            togglePowerProc.command = ["/usr/bin/bluetoothctl", "power", "off"];
            toggleScanProc.running = true;
            togglePowerProc.running = true;
        } else {
            bluetoothRoot.activeStatusText = "Bluetooth is ON";
            togglePowerProc.command = ["/usr/bin/bluetoothctl", "power", "on"];
            togglePowerProc.running = true;
        }
    }

    function handleDeviceClick(mac, isConnected) {
        if (togglePowerProc.running || toggleScanProc.running || !bluetoothRoot.isPowered) return;
        let mode = isConnected ? "disconnect" : "connect";
        deviceActionProc.command = ["/usr/bin/bluetoothctl", mode, mac];
        deviceActionProc.running = true;
        stateFetcherTimer.restart();
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
            if (rootShell.barPosition === "left") return Item.BottomLeft
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
                    x: (rootShell.barPosition === "right") ? 40 : -40
                    y: (rootShell.barPosition === "left" || rootShell.barPosition === "bottom") ? 40 : -40
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
            topLeftRadius: 0
            topRightRadius: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left") ? bluetoothRoot.radiusValue : 0
            bottomLeftRadius: rootShell.barPosition === "right" ? bluetoothRoot.radiusValue : 0
            bottomRightRadius: (rootShell.barPosition === "top") ? bluetoothRoot.radiusValue : 0
        }

        // --- Wings Component ---
        Item {
            anchors.fill: parent
            visible: bluetoothRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left" || rootShell.barPosition === "bottom"
                Shape {
                    x: 0; y: -bluetoothRoot.wingSize; width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: bluetoothRoot.wingSize
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: bluetoothRoot.wingSize }
                        PathLine { x: 0; y: bluetoothRoot.wingSize }
                    }
                }
                Shape {
                    rotation: -90; transformOrigin: Item.TopLeft
                    x: parent.width; y: parent.height; width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: bluetoothRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        MouseArea { id: popupHoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

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
                            onClicked: bluetoothRoot.triggerScan()
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
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
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 40
                        }

                        Repeater {
                            model: bluetoothRoot.isPowered ? bluetoothRoot.deviceModel : 0
                            delegate: Rectangle {
                                id: delegateBody
                                Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 8
                                color: itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent"
                                border.width: modelData.connected ? 1 : 0
                                border.color: rootShell.colorAccent

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12; anchors.rightMargin: 12
                                    spacing: 0
                                    
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.name !== "" ? modelData.name : modelData.mac
                                            font.family: rootShell.shellFont; font.pixelSize: 13; font.weight: Font.Medium
                                            color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: modelData.mac
                                            font.family: rootShell.shellFont; font.pixelSize: 10; color: rootShell.colorSubtext
                                            opacity: 0.7; elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    z: 20 
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

                // --- Standardized Footer Panel Layout ---
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 56

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        Text {
                            id: bigFooterIcon
                            text: bluetoothRoot.isPowered ? "bluetooth" : "bluetooth_disabled"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 32
                            color: bluetoothRoot.isPowered ? rootShell.colorAccent : rootShell.colorClose
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: bluetoothRoot.activeStatusText
                            font.family: rootShell.shellFont; font.pixelSize: 13
                            color: "#ffffff"; opacity: 0.8
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Switch {
                            id: powerSwitch
                            checked: bluetoothRoot.isPowered
                            implicitWidth: 42
                            implicitHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            
                            onClicked: bluetoothRoot.togglePower()
                            
                            indicator: Rectangle {
                                width: powerSwitch.implicitWidth
                                height: powerSwitch.implicitHeight
                                radius: 12
                                color: powerSwitch.checked ? rootShell.colorAccent : "transparent"
                                border.color: powerSwitch.checked ? rootShell.colorAccent : rootShell.colorBorder
                                border.width: 2

                                Rectangle {
                                    x: powerSwitch.checked ? parent.width - width - 4 : 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14; height: 14; radius: 7
                                    color: powerSwitch.checked ? rootShell.colorBackground : rootShell.colorSubtext
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
