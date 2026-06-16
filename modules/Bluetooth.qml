import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: bluetoothRoot

    property bool isLocked: false

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
       // Bypass the broken SysTray coordinates and lock it to the screen's right edge
       // (parent.width is the monitor edge, minus popup width, minus ~55px for the bar + gap)
       ? parent.width - width - 46
       : (rootShell.barPosition === "left" ? hoverOriginX + 35 : hoverOriginX) 
       
    y: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left" || rootShell.barPosition === "right") 
       ? hoverOriginY - height + 94
       : hoverOriginY

    // --- State Management ---
    property bool isPowered: false
    property bool isScanning: false
    property string activeStatusText: "Bluetooth is ON"
    
    ListModel {
        id: deviceModel
    }

    // --- Unified Bluetooth Session ---
    Process {
        id: bluetoothSession
        command: ["/usr/bin/stdbuf", "-oL", "/usr/bin/bluetoothctl"]
        running: bluetoothRoot.active
        // stdout stripped: Process is strictly an interactive writer now to prevent stream lockups
    }

    // --- Core Bluetooth Processes ---
    Process {
        id: stateFetcher
        command: ["/usr/bin/bluetoothctl", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (bluetoothRoot.isLocked) {
                    stateFetcher.running = false;
                    return;
                }
                let textLines = this.text.split("\n");
                bluetoothRoot.isPowered = textLines.some(l => l.includes("Powered: yes"));
                bluetoothRoot.isScanning = textLines.some(l => l.includes("Discovering: yes"));
                
                bluetoothRoot.activeStatusText = bluetoothRoot.isScanning ? "Scanning..." : (bluetoothRoot.isPowered ? "Bluetooth is ON" : "Bluetooth is OFF");
                stateFetcher.running = false;
            }
        }
    }

    Process {
        id: deviceFetcher
        // Bash pipeline fetches exact connection and pairing states efficiently 
        command: [
            "/bin/bash", 
            "-c", 
            "bluetoothctl devices | grep '^Device ' | while read -r _ mac name; do info=$(bluetoothctl info \"$mac\"); [[ \"$info\" == *\"Paired: yes\"* ]] && paired='true' || paired='false'; [[ \"$info\" == *\"Connected: yes\"* ]] && conn='true' || conn='false'; echo \"$mac|$name|$paired|$conn\"; done"
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i] === "") continue;
                    
                    let parts = lines[i].split("|");
                    if (parts.length < 4) continue;

                    let mac = parts[0];
                    let name = parts[1].trim();
                    let isPaired = parts[2] === "true";
                    let isConnected = parts[3] === "true";
                    
                    let found = false;

                    for (let j = 0; j < deviceModel.count; j++) {
                        if (deviceModel.get(j).mac === mac) {
                            found = true;
                            deviceModel.setProperty(j, "connected", isConnected);
                            deviceModel.setProperty(j, "paired", isPaired);
                            
                            if (name !== "" && deviceModel.get(j).name !== name) {
                                deviceModel.setProperty(j, "name", name);
                            }
                            break;
                        }
                    }

                    if (!found) {
                        let deviceData = {
                            mac: mac,
                            name: name,
                            connected: isConnected,
                            paired: isPaired
                        };

                        if (isPaired || isConnected) {
                            deviceModel.insert(0, deviceData);
                        } else {
                            deviceModel.append(deviceData);
                        }
                    }
                }
                deviceFetcher.running = false;
            }
        }
    }

    Process { id: togglePowerProc; running: false; onRunningChanged: { if (!running) stateFetcher.running = true; } }
    Process { id: toggleScanProc; running: false; onRunningChanged: { if (!running) stateFetcher.running = true; } }
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
        interval: 1500
        repeat: true
        running: bluetoothRoot.active
        onTriggered: {
            if (!togglePowerProc.running && !toggleScanProc.running && !deviceActionProc.running) {
                stateFetcher.running = true;
                deviceFetcher.running = true;
            }
        }
    }

    function triggerScan() {
        deviceModel.clear();
        bluetoothSession.write("agent on\n");
        bluetoothSession.write("default-agent\n");
        bluetoothSession.write("scan on\n");

        scanDurationTimer.restart();

        bluetoothRoot.isScanning = true;
        bluetoothRoot.activeStatusText = "Scanning...";
    }

    function togglePower() {
        let cmd = bluetoothRoot.isPowered ? "power off\n" : "power on\n";
        bluetoothSession.write(cmd);
        Qt.callLater(() => { stateFetcher.running = true; }, 1000);
    }

    function handleDeviceClick(mac, isConnected) {
        let mode = isConnected ? "disconnect" : "connect";
        bluetoothSession.write(mode + " " + mac + "\n");
        Qt.callLater(() => { stateFetcher.running = true; }, 500);
    }

    function pairDevice(mac) {
        bluetoothSession.write("trust " + mac + "\n");
        bluetoothSession.write("pair " + mac + "\n");
    }

    function removeDevice(mac) {
        bluetoothSession.write("remove " + mac + "\n");
        for (let i = 0; i < deviceModel.count; i++) {
            if (deviceModel.get(i).mac === mac) {
                deviceModel.remove(i);
                break;
            }
        }
    }

    onActiveChanged: {
        if (active) {
            deviceModel.clear();
            stateFetcher.running = true;
            deviceFetcher.running = true;
        }
    }

    // --- Visuals & Animations ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft
            if (rootShell.barPosition === "right") return Item.BottomRight
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
                    y: (rootShell.barPosition === "top") ? -40 : 40 
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
            
            // The edge touching the bar is sharp (0)
            // AND the bottom corner where the wing attaches is sharp (0)
            topLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "top") ? 0 : bluetoothRoot.radiusValue
            bottomLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "bottom" || rootShell.barPosition === "right") ? 0 : bluetoothRoot.radiusValue
            topRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "top") ? 0 : bluetoothRoot.radiusValue
            bottomRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "bottom" || rootShell.barPosition === "left") ? 0 : bluetoothRoot.radiusValue
        }

        Item {
            anchors.fill: parent
            visible: bluetoothRoot.width > 30
            z: 2 

            // --- LEFT BAR WINGS (Popup is on the right, wings merge up/down into the left bar) ---
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"
                
                // Top-Left Wing (Points UP)
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
                
                // Bottom-Left Wing (Points DOWN)
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

            // --- RIGHT BAR WINGS (Popup is to the left of the bar) ---
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                // Top-Right Wing (Points UP)
                Shape {
                    x: parent.width - bluetoothRoot.wingSize; y: -bluetoothRoot.wingSize
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: bluetoothRoot.wingSize; startY: bluetoothRoot.wingSize
                        PathLine { x: 0; y: bluetoothRoot.wingSize }
                        PathQuad { x: bluetoothRoot.wingSize; y: 0; controlX: bluetoothRoot.wingSize; controlY: bluetoothRoot.wingSize }
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                    }
                }

                // Bottom-Right Wing (Points DOWN)
                Shape {
                    rotation: 90
                    transformOrigin: Item.TopRight
                    x: 0 - bluetoothRoot.wingSize
                    y: parent.height
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: bluetoothRoot.wingSize; startY: 0
                        PathLine { x: 0; y: 0 }
                        PathQuad { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize; controlX: bluetoothRoot.wingSize; controlY: 0 }
                        PathLine { x: bluetoothRoot.wingSize; y: 0 }
                    }
                }
            }
        }

        MouseArea { id: popupHoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

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
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                stateFetcherTimer.running = false;
                                bluetoothRoot.triggerScan();
                                Qt.callLater(() => { stateFetcherTimer.running = true; }, 2000);
                            }
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: deviceModel
                    spacing: 4
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    header: Item {
                        width: ListView.view ? ListView.view.width : 0
                        height: !bluetoothRoot.isPowered ? 24 : 0
                        visible: !bluetoothRoot.isPowered
                        
                        Text {
                            text: "Adapter Powered Off"
                            font.family: rootShell.shellFont
                            font.pixelSize: 13
                            color: rootShell.colorSubtext
                        }
                    }

                    delegate: Item {
                        width: ListView.view.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            
                            color: model.connected 
                                   ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) 
                                   : (itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent")

                            border.width: model.connected ? 1 : 0
                            border.color: rootShell.colorAccent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        spacing: 0

                                        Text {
                                            text: model.name !== "" ? model.name : model.mac
                                            color: "#ffffff"
                                            font.pixelSize: 13
                                            font.weight: model.connected ? Font.Bold : Font.Normal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: model.connected ? "Connected" : (model.paired ? "Paired" : model.mac)
                                            color: model.connected ? rootShell.colorAccent : rootShell.colorSubtext
                                            font.pixelSize: 11
                                        }
                                    }
                                    
                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }
                                }
                                
                                Rectangle {
                                    width: 32; height: 32; radius: 6
                                    color: actionMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        text: !model.paired ? "link" : (model.connected ? "link_off" : "cable")
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 18
                                        color: "#ffffff"
                                    }
                                    
                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!model.paired) {
                                                bluetoothRoot.pairDevice(model.mac);
                                            } else {
                                                bluetoothRoot.handleDeviceClick(model.mac, model.connected);
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: model.paired
                                    width: 32; height: 32; radius: 6
                                    color: forgetMouse.containsMouse ? Qt.rgba(255,90,90,0.1) : "transparent"
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        text: "delete" 
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 18
                                        color: rootShell.colorClose
                                    }
                                    
                                    MouseArea {
                                        id: forgetMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: bluetoothRoot.removeDevice(model.mac)
                                    }
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
                    Layout.fillWidth: true; Layout.preferredHeight: 56

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        Text {
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
