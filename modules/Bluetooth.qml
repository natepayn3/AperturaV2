import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

Item {
    id: bluetoothRoot

    property bool isLocked: false
    property string namespace: "quickshell-bluetooth-popup"
    property bool active: false
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real maxCardHeight: 440

    property real baseLayoutHeight: 100 
    property real calculatedHeight: baseLayoutHeight + (deviceModel.count > 0 ? (deviceModel.count * 54) : 0)

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.min(Math.round(calculatedHeight), Math.round(maxCardHeight))
    width: Math.round(maxCardWidth)
    height: implicitHeight

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
    
    property string activeStatusText: isScanning ? "Scanning..." : (isPowered ? "Bluetooth is ON" : "Bluetooth is OFF")
    
    onIsPoweredChanged: {
        syncDevices();
    }

    ListModel {
        id: deviceModel
    }

    function syncDevices() {
        if (!active) return;
        
        if (isPowered) {
            if (!deviceFetcher.running) {
                deviceFetcher.running = true;
            }
        } else {
            deviceModel.clear();
        }
    }

    function sortDeviceModel() {
        if (deviceModel.count <= 1) return;
        let items = [];
        for (let i = 0; i < deviceModel.count; i++) {
            let item = deviceModel.get(i);
            items.push({ mac: item.mac, name: item.name, connected: item.connected, paired: item.paired });
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

    // --- Unified Bluetooth Session (Event Listener) ---
    Process {
        id: bluetoothSession
        command: ["/usr/bin/stdbuf", "-oL", "/usr/bin/bluetoothctl"]
        running: bluetoothRoot.active
        
        // Track state to prevent O(N^2) parsing loop lockups
        property int lastProcessedIndex: 0
        property string lineBuffer: ""

        onRunningChanged: {
            if (!running) {
                lastProcessedIndex = 0;
                lineBuffer = "";
            }
        }
        
        stdout: StdioCollector {
            onTextChanged: {
                // Extract only the new delta 
                let newChunk = this.text.substring(bluetoothSession.lastProcessedIndex);
                bluetoothSession.lastProcessedIndex = this.text.length;
                
                bluetoothSession.lineBuffer += newChunk;
                
                // Split by newline, leaving any incomplete trailing chunk in the buffer
                let lines = bluetoothSession.lineBuffer.split("\n");
                bluetoothSession.lineBuffer = lines.pop(); 
                
                let completeLines = lines.join("\n");
                
                if (completeLines.length > 0) {
                    // Strip all invisible ANSI color/formatting codes
                    let cleanText = completeLines.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
                    handleBluetoothEvent(cleanText);
                }
            }
        }
    }

    Process {
        id: stateFetcher
        command: ["/usr/bin/bluetoothctl", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let textLines = this.text.split("\n");
                
                let isNowPowered = textLines.some(l => l.includes("Powered: yes"));
                let hardwareScanning = textLines.some(l => l.includes("Discovering: yes"));
                
                if (hardwareScanning && !bluetoothRoot.isScanning) {
                    bluetoothRoot.isScanning = true;
                    scanDurationTimer.restart(); 
                } else if (!hardwareScanning) {
                    bluetoothRoot.isScanning = false;
                }
                
                // If power changed, onIsPoweredChanged will automatically trigger syncDevices()
                if (bluetoothRoot.isPowered !== isNowPowered) {
                    bluetoothRoot.isPowered = isNowPowered;
                } else {
                    // If power didn't change (e.g. standard open), explicitly trigger the fetch
                    bluetoothRoot.syncDevices();
                }
                
                bluetoothRoot.isToggling = false; 
                stateFetcher.running = false;
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
            }
        }
    }

    // Replaces BlueZ TTY failure by forcing manual CLI checks during scan
    Timer {
        id: liveScanTimer
        interval: 1500
        repeat: true
        running: bluetoothRoot.isScanning 
        onTriggered: {
            if (!deviceFetcher.running) {
                deviceFetcher.running = true;
            }
        }
    }

    Process {
        id: deviceActionProc
        running: false
        
        function act(mode, mac) {
            if (mode === "pair") {
                // Trust must be established before pairing headless
                command = ["/bin/bash", "-c", "bluetoothctl trust " + mac + " && bluetoothctl pair " + mac];
            } else {
                command = ["bluetoothctl", mode, mac];
            }
            // Reset and fire the blocking process
            running = false;
            running = true;
        }
        
        onRunningChanged: {
            // The exact millisecond BlueZ exits with a success/fail state, force a hard UI refresh
            if (!running && bluetoothRoot.active) {
                bluetoothRoot.syncDevices();
            }
        }
    }

    Timer {
        id: scanDurationTimer
        interval: 5000
        repeat: false
        onTriggered: {
            bluetoothRoot.isScanning = false;
            bluetoothSession.write("scan off\n");
            // Extended 2.5s delay allows BlueZ hardware to completely halt
            Qt.callLater(() => { stateFetcher.running = true; }, 2500);
        }
    }

    // Converted to Play/Stop toggle
    function triggerScan() {
        if (bluetoothRoot.isScanning) {
            scanDurationTimer.stop();
            bluetoothRoot.isScanning = false;
            bluetoothSession.write("scan off\n");
            Qt.callLater(() => { stateFetcher.running = true; }, 1000);
        } else {
            bluetoothRoot.isScanning = true;
            bluetoothSession.write("scan on\n");
            scanDurationTimer.restart();
        }
    }

    property bool isToggling: false

    function togglePower() {
        if (isToggling) return;
        isToggling = true;

        let targetState = !bluetoothRoot.isPowered;
        bluetoothRoot.isPowered = targetState;
        
        bluetoothSession.write(targetState ? "power on\n" : "power off\n");
        unlockTimer.restart();
    }

    Timer {
        id: unlockTimer
        interval: 1000
        onTriggered: isToggling = false
    }

    function handleDeviceClick(mac, isConnected) {
        deviceActionProc.act(isConnected ? "disconnect" : "connect", mac);
    }

    function pairDevice(mac) {
        deviceActionProc.act("pair", mac);
    }

    function removeDevice(mac) {
        deviceActionProc.act("remove", mac);
    }

    function handleBluetoothEvent(text) { 
        let lines = text.split("\n");
        let listNeedsSorting = false;

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];

            // Safety net: Catch explicit command success messages that suppress [CHG] logs
            if (line.includes("Pairing successful") || line.includes("Connection successful")) {
                bluetoothRoot.syncDevices();
                continue;
            }

            if (line.includes("[NEW] Device")) {
                let match = line.match(/Device\s+([0-9A-Fa-f:]{17})\s+(.*)/);
                if (match) {
                    let mac = match[1];
                    let name = match[2].trim();
                    
                    let exists = false;
                    for (let j = 0; j < deviceModel.count; j++) {
                        if (deviceModel.get(j).mac === mac) { exists = true; break; }
                    }
                    
                    if (!exists) {
                        deviceModel.append({ mac: mac, name: name, connected: false, paired: false });
                    }
                }
            }

            if (line.includes("[CHG]")) {
                let match = line.match(/Device\s+([0-9A-Fa-f:]{17})/);
                if (match) {
                    let mac = match[1];
                    for (let j = 0; j < deviceModel.count; j++) {
                        if (deviceModel.get(j).mac === mac) {
                            
                            if (line.includes("Connected: yes") && !deviceModel.get(j).connected) {
                                deviceModel.setProperty(j, "connected", true);
                                listNeedsSorting = true;
                            }
                            if (line.includes("Connected: no") && deviceModel.get(j).connected) {
                                deviceModel.setProperty(j, "connected", false);
                                listNeedsSorting = true;
                            }
                            if (line.includes("Paired: yes") && !deviceModel.get(j).paired) {
                                deviceModel.setProperty(j, "paired", true);
                                listNeedsSorting = true;
                            }
                            break;
                        }
                    }
                }
            }
        }
        
        // Immediately snap newly connected/paired devices to the top of the UI
        if (listNeedsSorting) {
            sortDeviceModel();
        }
    }

    onActiveChanged: {
        if (active) {
            stateFetcher.running = true;
        } else {
            // Safely spin down processes when hiding
            deviceFetcher.running = false;
        }
    }

    // --- Visuals & Animations ---
    AnimatedCard {
        id: cardWrapper
        anchors.fill: parent
        
        active: bluetoothRoot.active
        barPosition: rootShell.barPosition
        backgroundColor: rootShell.colorBackground
        
        targetWidth: bluetoothRoot.width
        targetHeight: bluetoothRoot.height
        
        radiusValue: bluetoothRoot.radiusValue
        wingSize: bluetoothRoot.wingSize

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
                                            font.family: rootShell.shellFont
                                            font.pixelSize: 13
                                            font.weight: model.connected ? Font.Bold : Font.Normal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: model.connected ? "Connected" : (model.paired ? "Paired" : model.mac)
                                            color: model.connected ? rootShell.colorAccent : rootShell.colorSubtext
                                            font.family: rootShell.shellFont
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
                                onClicked: bluetoothRoot.triggerScan();
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

                        Item {
                            implicitWidth: 42; implicitHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: bluetoothRoot.isPowered ? "#ffffff" : "transparent"
                                border.color: bluetoothRoot.isPowered ? "#ffffff" : rootShell.colorBorder
                                border.width: 2

                                Rectangle {
                                    x: bluetoothRoot.isPowered ? parent.width - width - 4 : 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14; height: 14; radius: 7
                                    color: bluetoothRoot.isPowered ? rootShell.colorBackground : rootShell.colorSubtext
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !bluetoothRoot.isToggling
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bluetoothRoot.togglePower()
                            }
                        }
                    }
                }
            }
        }
    }
}
