import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: networkLayoutRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    // --- Dynamic Theme Hook Alignments ---
    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"
    property color themeSubtext: "transparent"
    property color themeError: "#f38ba8"

    // --- Core State Properties ---
    property string currentSection: "wifi" // "wifi" | "ethernet"
    property string activeWifiSsid: ""
    property bool wifiEnabled: true
    property string expandedSsid: ""
    property var knownWifis: []

    // Connection Feedback State Flags
    property string connectingSsid: ""
    property string failedSsid: ""

    // --- Internal Data Models ---
    ListModel { id: wifiListModel }
    ListModel { id: ethernetListModel }

    Connections {
        target: settingsWindow
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (settingsWindow && settingsWindow.visible) {
                globalNetworkPoller.running = false;
                globalNetworkPoller.running = true;
            }
        }
    }

    // Centralized engine poller keeps device sweeps predictable
    Timer {
        id: globalNetworkPoller
        interval: 2000
        running: settingsWindow && settingsWindow.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!deviceStateWorker.running) {
                deviceStateWorker.running = true;
            }
            
            if (networkLayoutRoot.currentSection === "wifi" && networkLayoutRoot.wifiEnabled && networkLayoutRoot.expandedSsid === "" && !connectNetworkProc.running) {
                if (!wifiHardwareRescanner.running) {
                    wifiHardwareRescanner.running = true;
                }
            }
            if (!knownNetworksPopulator.running) {
                knownNetworksPopulator.running = true;
            }
        }
    }

    // Hot-wires a manual physical probe to bypass NM caching lag completely
    Process {
        id: wifiHardwareRescanner
        command: ["nmcli", "device", "wifi", "rescan"]
        running: false
        onExited: {
            wifiListPopulator.running = false;
            wifiListPopulator.running = true;
        }
    }

    // Evaluates operational states across available physical cards
    Process {
        id: deviceStateWorker
        command: ["nmcli", "-g", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let lines = text.trim().split("\n");
                ethernetListModel.clear();

                for (let i = 0; i < lines.length; i++) {
                    let parts = lines[i].split(":");
                    if (parts.length < 3) continue;
                    
                    let dev = parts[0];
                    let type = parts[1];
                    let state = parts[2];
                    let conn = parts[3] || "";

                    if (type === "wifi") {
                        networkLayoutRoot.wifiEnabled = (state !== "unavailable" && state !== "unmanaged");
                    } else if (type === "ethernet") {
                        let isUp = (state === "connected");
                        ethernetListModel.append({
                            "interfaceName": dev,
                            "statusText": isUp ? "Connected" : "Cable disconnected",
                            "profileName": conn,
                            "isConnected": isUp
                        });
                    }
                }
            }
        }
    }

    // Collects metadata profiles regarding neighborhood access points
    Process {
        id: wifiListPopulator
        command: ["nmcli", "-g", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                if (!text.trim()) { wifiListModel.clear(); return; }

                let lines = text.trim().split("\n");
                let discoveredSsids = [];
                let rawItemsList = [];
                let activeSsidFound = "";

                // Phase 1: Parse data streams out of nmcli
                for (let i = 0; i < lines.length; i++) {
                    let parts = lines[i].match(/(?:\\:|[^:])+/g) || [];
                    if (parts.length < 4) continue;

                    let inUse = (parts[0] === "*");
                    let ssid = parts[1].replace(/\\:/g, ":");
                    let signal = parseInt(parts[2]) || 0;
                    let securityStr = parts[3].trim();
                    let securityDisplay = (securityStr === "--" || securityStr === "") ? "Open" : securityStr;
                    let secureNode = (securityDisplay !== "Open");
                    
                    if (!ssid || discoveredSsids.indexOf(ssid) !== -1) continue;
                    discoveredSsids.push(ssid);

                    if (inUse) activeSsidFound = ssid;

                    rawItemsList.push({
                        "ssid": ssid,
                        "signal": signal,
                        "isConnected": inUse,
                        "isSecure": secureNode,
                        "securityType": securityDisplay,
                        // Force false if it is the actively failing target profile to block transient sorting jumps
                        "isSaved": networkLayoutRoot.failedSsid === ssid ? false : (networkLayoutRoot.knownWifis.indexOf(ssid) !== -1)
                    });
                }

                // Phase 2: Separate into categorical buckets to enforce priority hierarchy
                let tempActiveList = [];
                let tempSavedList = [];
                let tempNormalList = [];

                for (let k = 0; k < rawItemsList.length; k++) {
                    let item = rawItemsList[k];
                    if (item.isConnected) tempActiveList.push(item);
                    else if (item.isSaved) tempSavedList.push(item);
                    else tempNormalList.push(item);
                }

                // Sort saved and unsaved chunks independently by signal strength
                tempSavedList.sort((a, b) => b.signal - a.signal);
                tempNormalList.sort((a, b) => b.signal - a.signal);

                // Merge back into final priority array: Connected -> Saved Profiles -> Discoveries
                let sortedItems = tempActiveList.concat(tempSavedList).concat(tempNormalList);

                // Phase 3: Sync array to ListModel while maintaining view position sanity
                for (let j = 0; j < sortedItems.length; j++) {
                    let item = sortedItems[j];
                    let matchIndex = -1;

                    for (let m = 0; m < wifiListModel.count; m++) {
                        if (wifiListModel.get(m).ssid === item.ssid) {
                            matchIndex = m;
                            break;
                        }
                    }

                    if (matchIndex !== -1) {
                        wifiListModel.setProperty(matchIndex, "signal", item.signal);
                        wifiListModel.setProperty(matchIndex, "isConnected", item.isConnected);
                        
                        if (matchIndex !== j) wifiListModel.move(matchIndex, j, 1);
                    } else {
                        wifiListModel.insert(j, {
                            "ssid": item.ssid,
                            "signal": item.signal,
                            "isConnected": item.isConnected,
                            "isSecure": item.isSecure,
                            "securityType": item.securityType
                        });
                    }
                }

                // Garbage collect vanished entries
                for (let c = wifiListModel.count - 1; c >= 0; c--) {
                    if (discoveredSsids.indexOf(wifiListModel.get(c).ssid) === -1) {
                        wifiListModel.remove(c);
                    }
                }

                networkLayoutRoot.activeWifiSsid = activeSsidFound;
            }
        }
    }

    // Cross-references NetworkManager for saved connection profiles with VALID stored secrets
    Process {
        id: knownNetworksPopulator
        command: ["fish", "-c", "nmcli -g NAME,TYPE connection show | while read -l line; set -l p (string split ':' -- $line); if test $p[2] = '802-11-wireless' -o $p[2] = 'wifi'; set -l sec (nmcli -s -g 802-11-wireless-security.psk connection show $p[1] 2>/dev/null); if test -n \"$sec\"; echo $p[1]; end; end; end"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                if (!text.trim()) { networkLayoutRoot.knownWifis = []; return; }
                
                let lines = text.trim().split("\n");
                let known = [];
                for (let i = 0; i < lines.length; i++) {
                    let name = lines[i].trim();
                    if (name !== "" && name !== networkLayoutRoot.connectingSsid) {
                        known.push(name);
                    }
                }
                networkLayoutRoot.knownWifis = known;
            }
        }
    }

    // --- Core Network Action Drivers ---

    Process {
        id: togglePowerProc
        running: false
        onExited: {
            deviceStateWorker.running = false;
            deviceStateWorker.running = true;
        }
    }

    Process {
        id: connectNetworkProc
        running: false
        property string attemptingSsid: ""

        function connectTo(ssidTarget, password) {
            networkLayoutRoot.failedSsid = "";
            networkLayoutRoot.connectingSsid = ssidTarget;
            attemptingSsid = ssidTarget;
            
            let cleanPass = password.trim();
            if (cleanPass === "") {
                command = ["nmcli", "device", "wifi", "connect", ssidTarget];
            } else {
                command = ["nmcli", "device", "wifi", "connect", ssidTarget, "password", cleanPass];
            }
            running = true;
        }

        onExited: (exitCode) => {
            if (networkLayoutRoot.connectingSsid !== "") {
                if (exitCode !== 0) {
                    networkLayoutRoot.failedSsid = networkLayoutRoot.connectingSsid;
                    
                    if (attemptingSsid !== "" && networkLayoutRoot.knownWifis.indexOf(attemptingSsid) !== -1) {
                        failedAuthCleanUpProc.dropProfile(attemptingSsid);
                    } else {
                        if (!wifiListPopulator.running) wifiListPopulator.running = true;
                        if (!knownNetworksPopulator.running) knownNetworksPopulator.running = true;
                    }
                } else {
                    networkLayoutRoot.expandedSsid = "";
                    if (!deviceStateWorker.running) deviceStateWorker.running = true;
                    if (!wifiListPopulator.running) wifiListPopulator.running = true;
                    if (!knownNetworksPopulator.running) knownNetworksPopulator.running = true;
                }
                networkLayoutRoot.connectingSsid = "";
                attemptingSsid = "";
            }
        }
    }

    Process {
        id: disconnectProc
        running: false
        function disconnect(ssidTarget) {
            command = ["nmcli", "connection", "down", "id", ssidTarget];
            running = true;
        }
        onExited: {
            networkLayoutRoot.expandedSsid = "";
            deviceStateWorker.running = true;
            wifiListPopulator.running = true;
            if (!knownNetworksPopulator.running) knownNetworksPopulator.running = true;
        }
    }

    Process {
        id: forgetProc
        running: false
        function forget(ssidTarget) {
            command = ["nmcli", "connection", "delete", "id", ssidTarget];
            running = true;
        }
        onExited: {
            networkLayoutRoot.expandedSsid = "";
            deviceStateWorker.running = true;
            wifiListPopulator.running = true;
            if (!knownNetworksPopulator.running) knownNetworksPopulator.running = true;
        }
    }

    // Reusable background worker to drop authenticated profiles that failed connectivity
    Process {
        id: failedAuthCleanUpProc
        running: false
        function dropProfile(ssidTarget) {
            command = ["nmcli", "connection", "delete", "id", ssidTarget];
            running = false;
            running = true;
        }
        onExited: {
            if (!deviceStateWorker.running) deviceStateWorker.running = true;
            if (!wifiListPopulator.running) wifiListPopulator.running = true;
            if (!knownNetworksPopulator.running) knownNetworksPopulator.running = true;
        }
    }

    function toggleWifiPower(enable) {
        togglePowerProc.command = ["nmcli", "radio", "wifi", enable ? "on" : "off"];
        togglePowerProc.running = true;
    }

    Component.onCompleted: {
        deviceStateWorker.running = true;
        wifiHardwareRescanner.running = true;
        knownNetworksPopulator.running = true;
    }

    // --- Core View Area Container ---
    ScrollView {
        id: scrollContainer
        anchors.fill: parent
        clip: true
        topPadding: 0
        leftPadding: 10
        rightPadding: 10
        bottomPadding: 16
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: scrollContainer.availableWidth
            spacing: 12

            // --- Multi-Interface Tab Selector ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { tag: "wifi", display: "Wi-Fi", icon: "wifi" },
                        { tag: "ethernet", display: "Ethernet", icon: "settings_ethernet" }
                    ]
                    
                    delegate: Button {
                        id: tabBtn
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        flat: true

                        background: Rectangle {
                            color: networkLayoutRoot.currentSection === modelData.tag 
                                ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 0.1) 
                                : (tabBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                            border.color: networkLayoutRoot.currentSection === modelData.tag 
                                ? themeAccent 
                                : (tabBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                            border.width: networkLayoutRoot.currentSection === modelData.tag ? 2 : 1
                            radius: 8
                        }

                        contentItem: Item {
                            anchors.fill: parent
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 14

                                Text {
                                    text: modelData.icon
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 18
                                    color: networkLayoutRoot.currentSection === modelData.tag ? themeAccent : themeText
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    text: modelData.display
                                    font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: themeText
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                        
                        onClicked: networkLayoutRoot.currentSection = modelData.tag
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }

            // --- Unified Row Design Modular Layout Component ---
            component NetworkRowCard : Item {
                id: rowCardRoot
                property string mainText: ""
                property string subText: ""
                property string iconGlyph: ""
                property bool isRowActive: false
                property bool isInteractiveElement: false
                property Component controlOverrideComponent: null
                property Component expandedControlsComponent: null
                property bool expanded: false

                signal clicked()

                Layout.fillWidth: true
                Layout.preferredHeight: expanded ? 104 : 52
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    clip: true
                    color: rowCardRoot.isRowActive 
                        ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 0.1) 
                        : (rowCardMouse.containsMouse && rowCardRoot.isInteractiveElement ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    border.color: rowCardRoot.isRowActive 
                        ? themeAccent 
                        : (rowCardMouse.containsMouse && rowCardRoot.isInteractiveElement ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                    border.width: rowCardRoot.isRowActive ? 2 : 1

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 14

                                Item {
                                    width: 24
                                    height: 24
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: rowCardRoot.iconGlyph
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 22
                                        color: rowCardRoot.isRowActive ? themeAccent : themeText
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                                    Text {
                                        text: rowCardRoot.mainText
                                        font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: themeText
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: rowCardRoot.subText
                                        font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                                        font.pixelSize: 11
                                        color: themeSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                Loader {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    sourceComponent: rowCardRoot.controlOverrideComponent
                                    visible: status === Loader.Ready
                                }
                            }

                            MouseArea {
                                id: rowCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: rowCardRoot.isInteractiveElement
                                cursorShape: Qt.PointingHandCursor
                                preventStealing: false
                                onClicked: rowCardRoot.clicked()
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            visible: rowCardRoot.expanded
                            sourceComponent: rowCardRoot.expandedControlsComponent
                        }
                    }
                }
            }

            // --- SUB-VIEW CONTENT: WI-FI INTERFACES ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: networkLayoutRoot.currentSection === "wifi"

                NetworkRowCard {
                    mainText: "Wireless Radio Link"
                    subText: networkLayoutRoot.wifiEnabled ? "Network discovery running" : "Hardware radio layer interface disabled"
                    iconGlyph: networkLayoutRoot.wifiEnabled ? "wifi" : "wifi_off"
                    isRowActive: networkLayoutRoot.wifiEnabled
                    isInteractiveElement: false
                    
                    controlOverrideComponent: Component {
                        Switch {
                            id: wifiToggleSwitch
                            checked: networkLayoutRoot.wifiEnabled
                            onClicked: networkLayoutRoot.toggleWifiPower(checked)
                            
                            background: Rectangle {
                                implicitWidth: 44
                                implicitHeight: 22
                                radius: 11
                                color: wifiToggleSwitch.checked ? themeAccent : themeBorder
                                
                                Rectangle {
                                    width: 16; height: 16; radius: 8; color: "#11111b"
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: wifiToggleSwitch.checked ? 24 : 4
                                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                }
                            }
                            indicator: Item {}
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }

                Repeater {
                    model: networkLayoutRoot.wifiEnabled ? wifiListModel : null
                    
                    delegate: NetworkRowCard {
                        property bool isConnecting: networkLayoutRoot.connectingSsid === model.ssid
                        property bool isFailed: networkLayoutRoot.failedSsid === model.ssid
                        property bool isSaved: networkLayoutRoot.knownWifis.indexOf(model.ssid) !== -1

                        mainText: model.ssid
                        subText: isConnecting 
                            ? "Connecting to interface..." 
                            : (isFailed 
                                ? "Authentication failed - verify password" 
                                : (model.isConnected ? "Active connection profile" : (isSaved ? "Saved network profile" : "Signal strength: " + model.signal + "%")))
                        
                        isRowActive: model.isConnected
                        iconGlyph: model.isConnected ? "signal_wifi_4_bar" : (model.isSecure ? "network_wifi_locked" : "network_wifi")
                        isInteractiveElement: !isConnecting
                        expanded: networkLayoutRoot.expandedSsid === model.ssid

                        onClicked: {
                            if (networkLayoutRoot.expandedSsid === model.ssid) {
                                networkLayoutRoot.expandedSsid = "";
                                // If they dismiss while it's flagged as failed, scrub it from memory cleanly
                                if (networkLayoutRoot.failedSsid === model.ssid) {
                                    networkLayoutRoot.failedSsid = "";
                                }
                            } else {
                                networkLayoutRoot.expandedSsid = model.ssid;
                            }
                        }

                        expandedControlsComponent: Component {
                            RowLayout {
                                width: parent ? parent.width : 0
                                height: 40
                                spacing: 10

                                Item { width: 6 }

                                // 1. Password Input: Only visible if secure, disconnected, and NOT already saved
                                Rectangle {
                                    id: passInputContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    color: Qt.rgba(0, 0, 0, 0.2)
                                    border.color: isFailed ? themeError : themeBorder
                                    border.width: 1
                                    radius: 6
                                    visible: !model.isConnected && model.isSecure && (!isSaved || isFailed)

                                    TextInput {
                                        id: passInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: isFailed ? themeError : themeText
                                        font.pixelSize: 13
                                        echoMode: TextInput.Password
                                        selectByMouse: true
                                        enabled: !isConnecting

                                        Connections {
                                            target: networkLayoutRoot
                                            function onExpandedSsidChanged() {
                                                if (networkLayoutRoot.expandedSsid !== model.ssid) {
                                                    passInput.text = "";
                                                }
                                            }
                                        }

                                        onAccepted: connectNetworkProc.connectTo(model.ssid, text)
                                        onTextEdited: if (isFailed) networkLayoutRoot.failedSsid = ""

                                        Text {
                                            text: "Enter Network Password..."
                                            color: themeSubtext
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: passInput.text === "" && !passInput.activeFocus
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    spacing: 8
                                    Layout.fillWidth: !passInputContainer.visible

                                    // Connect/Disconnect Button
                                    Button {
                                        id: actionBtn
                                        Layout.preferredWidth: 110
                                        Layout.preferredHeight: 34
                                        flat: true
                                        enabled: !isConnecting
                                        
                                        background: Rectangle {
                                            color: model.isConnected 
                                                ? Qt.rgba(243/255, 139/255, 168/255, 0.12) 
                                                : (isConnecting ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 0.4) : themeAccent)
                                            radius: 6
                                        }

                                        contentItem: Text {
                                            text: model.isConnected ? "Disconnect" : (isConnecting ? "Connecting..." : "Connect")
                                            color: model.isConnected ? themeError : "#11111b"
                                            font.bold: true
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: {
                                            if (model.isConnected) {
                                                disconnectProc.disconnect(model.ssid);
                                            } else {
                                                connectNetworkProc.connectTo(model.ssid, passInputContainer.visible ? passInput.text : "");
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }

                                    // Forget Button
                                    Button {
                                        id: forgetBtn
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 34
                                        flat: true
                                        enabled: !isConnecting
                                        visible: model.isConnected || isSaved
                                        
                                        background: Rectangle {
                                            color: forgetBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                                            border.color: forgetBtn.hovered ? themeError : themeBorder
                                            border.width: 1
                                            radius: 6
                                        }

                                        contentItem: Text {
                                            text: "Forget"
                                            color: themeText
                                            font.bold: true
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: forgetProc.forget(model.ssid)
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                                Item { width: 6 }
                            }
                        }
                    }
                }
            }

            // --- SUB-VIEW CONTENT: HARDWARE ETHERNET LINKS ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: networkLayoutRoot.currentSection === "ethernet"

                Repeater {
                    model: ethernetListModel
                    
                    delegate: NetworkRowCard {
                        mainText: "Interface: " + model.interfaceName
                        subText: model.isConnected ? "Profile connection target: " + model.profileName : model.statusText
                        iconGlyph: model.isConnected ? "lan" : "lan_disconnect"
                        isRowActive: model.isConnected
                        isInteractiveElement: false
                    }
                }
            }
        }
    }
}
