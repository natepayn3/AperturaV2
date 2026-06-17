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
            case "left":   return Screen.height - height - 10        
            case "right":  return Screen.height - height - 10;
            default:       return hoverOriginY;
        }
    }

    // --- State Management ---
    property bool isPowered: false
    property bool isScanning: false
    property bool _lockoutPolling: false 
    
    property string activeStatusText: isScanning 
        ? "Scanning..." 
        : (isPowered ? "Bluetooth is ON" : "Bluetooth is OFF")
    
    ListModel {
        id: deviceModel
    }

    // --- Core Model Sorting Engine ---
    function sortDeviceModel() {
        if (deviceModel.count <= 1) return;

        let items = [];
        for (let i = 0; i < deviceModel.count; i++) {
            let item = deviceModel.get(i);
            items.push({
                mac: item.mac,
                name: item.name,
                connected: item.connected,
                paired: item.paired
            });
        }

        items.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            return 0;
        });

        deviceModel.clear();
        for (let k = 0; k < items.length; k++) {
            deviceModel.append(items[k]);
        }
    }

    // --- Unified Bluetooth Session ---
    Process {
        id: bluetoothSession
        command: ["/usr/bin/bluetoothctl"]
        running: bluetoothRoot.active
        
        stdout: StdioCollector {
            onTextChanged: {
                let cleaned = this.text.trim();
                if (cleaned.includes("[CHG]") || cleaned.includes("Device")) {
                    handleBluetoothEvent(cleaned);
                }
            }
        }
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
                stateFetcher.running = false;
            }
        }
    }

    // The clean initial frame-1 bootstrapper you liked
    Process {
        id: bootstrapPairedFetcher
        command: ["/usr/bin/bluetoothctl", "paired-devices"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                handleBluetoothEvent(this.text);
                deviceFetcher.running = true;
            }
        }
    }

    Process {
        id: deviceFetcher
        command: [
            "/bin/bash", 
            "-c", 
            "bluetoothctl devices | grep '^Device ' | while read -r _ mac name; do info=$(bluetoothctl info \"$mac\"); [[ \"$info\" == *\"Paired: yes\"* ]] && paired='true' || paired='false'; [[ \"$info\" == *\"Connected: yes\"* ]] && conn='true' || conn='false'; echo \"$mac|$name|$conn|$paired\"; done"
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
                    let isConnected = parts[2] === "true";
                    let isPaired = parts[3] === "true";
                    
                    if (name.includes("RSSI:") || name.includes("TxPower:")) continue;

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
                        deviceModel.append({
                            mac: mac,
                            name: name,
                            connected: isConnected,
                            paired: isPaired
                        });
                    }
                }
                
                sortDeviceModel();
                
                deviceFetcher.running = false;
                if (!bluetoothRoot._lockoutPolling) {
                    stateFetcher.running = false;
                    stateFetcher.running = true;
                }
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
            bluetoothRoot._lockoutPolling = true; 
            bluetoothSession.write("scan off\n");
            
            Qt.callLater(() => {
                bluetoothRoot._lockoutPolling = false;
                stateFetcher.running = true;
            }, 1000);
        }
    }

    Timer {
        id: stateFetcherTimer
        interval: 1500
        repeat: true
        running: bluetoothRoot.active
        onTriggered: {
            if (!togglePowerProc.running && !toggleScanProc.running && !deviceActionProc.running) {
                if (!stateFetcher.running && !deviceFetcher.running && !bootstrapPairedFetcher.running) {
                    deviceFetcher.running = true;
                }
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

    // Your Exact Preferred Logic Block
    function handleBluetoothEvent(text) { 
        let lines = text.split("\n");
        let modelChanged = false;

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            let match = line.match(/Device\s+([0-9A-Fa-f:]{17})\s+(.*)/);
            if (match) {
                let mac = match[1];
                let desc = match[2].trim();
                let found = false;

                for (let j = 0; j < deviceModel.count; j++) {
                    if (deviceModel.get(j).mac === mac) {
                        found = true;
                        if (desc !== "" && !desc.startsWith("RSSI") && deviceModel.get(j).name !== desc) {
                            deviceModel.setProperty(j, "name", desc);
                            modelChanged = true;
                        }
                        if (line.includes("[CHG]") && line.includes("Connected: yes")) { deviceModel.setProperty(j, "connected", true); modelChanged = true; }
                        if (line.includes("[CHG]") && line.includes("Connected: no")) { deviceModel.setProperty(j, "connected", false); modelChanged = true; }
                        if (line.includes("[CHG]") && line.includes("Paired: yes")) { deviceModel.setProperty(j, "paired", true); modelChanged = true; }
                        break;
                    }
                }

                if (!found && desc !== "" && !desc.startsWith("RSSI")) {
                    deviceModel.append({ mac: mac, name: desc, connected: false, paired: false });
                    modelChanged = true;
                }
            }
        }
        if (modelChanged) {
            sortDeviceModel();
        }
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
        // 🎯 FIX: Removed deviceModel.clear() from here so the cached frame stays visible instantly
        if (active) {
            stateFetcher.running = true;
            bootstrapPairedFetcher.running = true; 
        }
    }

    // --- Visuals & Animations ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft
            if (rootShell.barPosition === "right") return Item.BottomRight
            if (rootShell.barPosition === "top") return Item.TopRight
            if (rootShell.barPosition === "bottom") return Item.BottomRight
            return Item.Center
        }

        opacity: bluetoothRoot.active ? 1.0 : 0.0
        scale: bluetoothRoot.active ? 1.0 : 0.0
        x: bluetoothRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: bluetoothRoot.active ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            color: rootShell.colorBackground
            z: 2
            border.width: 0

            topLeftRadius:     getCornerRadius("topLeft")
            topRightRadius:    getCornerRadius("topRight")
            bottomLeftRadius:  getCornerRadius("bottomLeft")
            bottomRightRadius: getCornerRadius("bottomRight")

            function getCornerRadius(corner) {
                let pos = rootShell.barPosition;
                let rad = bluetoothRoot.radiusValue;

                if (pos === "top") return (corner === "bottomLeft") ? rad : 0;
                if (pos === "bottom") return (corner === "topLeft") ? rad : 0;
                if (pos === "left") return (corner === "topRight") ? rad : 0;
                if (pos === "right") return (corner === "topLeft") ? rad : 0;
                return rad;
            }
        }

        Item {
            anchors.fill: parent
            visible: bluetoothRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"
                
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
                    x: parent.width; y: parent.height
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

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

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

                Shape {
                    rotation: 90
                    transformOrigin: Item.TopRight
                    x: 0 - bluetoothRoot.wingSize; y: parent.height
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
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                Shape {
                    x: -bluetoothRoot.wingSize; y: 0
                    width: bluetoothRoot.wingSize; height: bluetoothRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: bluetoothRoot.wingSize; startY: 0
                        PathLine { x: bluetoothRoot.wingSize; y: bluetoothRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: 0 }
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
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"
                
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
                
                Shape {
                    rotation: 180 
                    transformOrigin: Item.TopLeft
                    x: parent.width - maxCardWidth; y: parent.height 
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
        }

        MouseArea { id: popupHoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            z: 5

            HoverHandler { id: contentHoverHandler }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                anchors.bottomMargin: 8
                spacing: 0

                ListView {
                    id: mainDeviceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: deviceModel
                    spacing: 6
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        width: mainDeviceList.width
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
                                        id: itemMouse; anchors.fill: parent; hoverEnabled: true
                                    }
                                }
                                
                                Rectangle {
                                    width: 32; height: 32; radius: 6
                                    color: actionMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        text: !model.paired ? "link" : (model.connected ? "link_off" : "cable")
                                        font.family: "Material Symbols Outlined"; font.pixelSize: 18; color: "#ffffff"
                                    }
                                    
                                    MouseArea {
                                        id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
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
                                        text: "delete"; font.family: "Material Symbols Outlined"; font.pixelSize: 18
                                        color: rootShell.colorClose
                                    }
                                    
                                    MouseArea {
                                        id: forgetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
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
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                }

                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 48

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: footerScanMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                            
                            Text {
                                anchors.centerIn: parent
                                text: "radar"
                                font.family: "Material Symbols Outlined"; font.pixelSize: 24
                                color: bluetoothRoot.isScanning ? rootShell.colorAccent : "#ffffff"
                            }
                            
                            MouseArea {
                                id: footerScanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: bluetoothRoot.isPowered
                                onClicked: {
                                    stateFetcherTimer.running = false;
                                    bluetoothRoot.triggerScan();
                                    Qt.callLater(() => { stateFetcherTimer.running = true; }, 2000);
                                }
                            }
                        }

                        Text {
                            text: bluetoothRoot.activeStatusText
                            font.family: rootShell.shellFont; font.pixelSize: 14;
                            color: "#ffffff"; opacity: 0.8
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Switch {
                            id: powerSwitch
                            checked: bluetoothRoot.isPowered
                            implicitWidth: 42; implicitHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: bluetoothRoot.togglePower()
                            
                            indicator: Rectangle {
                                width: powerSwitch.implicitWidth; height: powerSwitch.implicitHeight; radius: 12
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
