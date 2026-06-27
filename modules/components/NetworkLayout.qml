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
    property string wifiInterfaceName: "wlan0"
    property string wifiHardwareModel: "Wireless Adapter"
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

    // Evaluates operational states across available physical cards (Stable Core Command)
    Process {
        id: deviceStateWorker
        command: ["nmcli", "-g", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let lines = text.trim().split("\n");
                let discoveredIfaces = [];

                for (let i = 0; i < lines.length; i++) {
                    let parts = lines[i].split(":");
                    if (parts.length < 3) continue;
                    
                    let dev = parts[0];
                    let type = parts[1];
                    let state = parts[2];
                    let conn = parts[3] || "";

                    if (type === "wifi") {
                        networkLayoutRoot.wifiEnabled = (state !== "unavailable" && state !== "unmanaged");
                        if (networkLayoutRoot.wifiInterfaceName !== dev) {
                            networkLayoutRoot.wifiInterfaceName = dev;
                            wifiHardwareDetailsProc.fetchDetails(dev);
                        }
                    } else if (type === "ethernet") {
                        let isUp = (state === "connected");
                        discoveredIfaces.push(dev);
                        
                        let matchIndex = -1;
                        for (let e = 0; e < ethernetListModel.count; e++) {
                            if (ethernetListModel.get(e).interfaceName === dev) {
                                matchIndex = e;
                                break;
                            }
                        }

                        let statusString = isUp ? "Connected" : "Cable disconnected";

                        if (matchIndex !== -1) {
                            let item = ethernetListModel.get(matchIndex);
                            
                            if (item.isConnected !== isUp) ethernetListModel.setProperty(matchIndex, "isConnected", isUp);
                            if (item.statusText !== statusString) ethernetListModel.setProperty(matchIndex, "statusText", statusString);
                            if (item.profileName !== conn) ethernetListModel.setProperty(matchIndex, "profileName", conn);
                            
                            // Fix: Only fetch if up, not already fetching, and values are empty/reset
                            if (isUp && !item.isFetching && (item.ipAddress === "Fetching..." || item.ipAddress === undefined || item.isConnected !== isUp)) {
                                ethernetListModel.setProperty(matchIndex, "isFetching", true);
                                ethernetDetailsWorker.fetchDetails(dev, matchIndex);
                            }
                        } else {
                            ethernetListModel.append({
                                "interfaceName": dev,
                                "statusText": statusString,
                                "profileName": conn,
                                "isConnected": isUp,
                                "ipAddress": "Fetching...",
                                "subnetMask": "",
                                "speed": "Fetching...",
                                "gateway": "Fetching...",
                                "dnsServers": "Fetching...",
                                "macAddress": "Fetching...",
                                "isFetching": isUp // Flag true immediately if launching fetcher
                            });
                            
                            if (isUp) {
                                ethernetDetailsWorker.fetchDetails(dev, ethernetListModel.count - 1);
                            }
                        }
                    }
                }

                for (let c = ethernetListModel.count - 1; c >= 0; c--) {
                    if (discoveredIfaces.indexOf(ethernetListModel.get(c).interfaceName) === -1) {
                        ethernetListModel.remove(c);
                    }
                }
            }
        }
    }

    // Asynchronously grabs individual IP, Gateway, DNS, and MAC metrics safely out-of-band
    Process {
        id: ethernetDetailsWorker
        property int targetIndex: -1
        running: false
        
        function fetchDetails(iface, index) {
            targetIndex = index;
            command = [
                "fish", "-c", 
                "cat /sys/class/net/" + iface + "/speed 2>/dev/null; " +
                "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,GENERAL.HWADDR device show " + iface
            ];
            running = false;
            running = true;
        }
        
        stdout: StdioCollector {
            onTextChanged: {
                if (ethernetDetailsWorker.targetIndex === -1 || !text.trim()) return;
                let lines = text.split("\n");
                
                let rawSpeed = lines[0] ? parseInt(lines[0].trim()) : 0;
                let speedStr = "Unknown link speed";
                if (rawSpeed > 0) {
                    speedStr = rawSpeed >= 1000 ? (rawSpeed / 1000) + " Gbps" : rawSpeed + " Mbps";
                }
                
                let ip = "No IP assigned";
                let cidr = "";
                let gateway = "None configured";
                let dnsList = [];
                let mac = "Unknown MAC";
                
                for (let i = 1; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line) continue;
                    
                    let splitIdx = line.indexOf(":");
                    if (splitIdx === -1) continue;
                    
                    let key = line.substring(0, splitIdx).trim();
                    let val = line.substring(splitIdx + 1).trim();
                    if (!val) continue;
                    
                    if (key.indexOf("IP4.ADDRESS") === 0) {
                        ip = val.split("/")[0];
                        cidr = val.includes("/") ? "/" + val.split("/")[1] : "";
                    } else if (key.indexOf("IP4.GATEWAY") === 0) {
                        gateway = val;
                    } else if (key.indexOf("IP4.DNS") === 0) {
                        dnsList.push(val);
                    } else if (key.indexOf("GENERAL.HWADDR") === 0) {
                        mac = val;
                    }
                }
                
                let dnsStr = dnsList.length > 0 ? dnsList.join(", ") : "None configured";
                
                if (ethernetDetailsWorker.targetIndex < ethernetListModel.count) {
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "ipAddress", ip);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "subnetMask", cidr);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "speed", speedStr);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "gateway", gateway);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "dnsServers", dnsStr);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "macAddress", mac);
                    ethernetListModel.setProperty(ethernetDetailsWorker.targetIndex, "isFetching", false); // Clear flag
                }
            }
        }
    }

    // Fetches full hardware descriptions separately to avoid parsing race conditions
    Process {
        id: wifiHardwareDetailsProc
        running: false
        function fetchDetails(iface) {
            command = ["nmcli", "-g", "GENERAL.PRODUCT", "device", "show", iface];
            running = false;
            running = true;
        }
        stdout: StdioCollector {
            onTextChanged: {
                let model = text.trim();
                if (model !== "") {
                    networkLayoutRoot.wifiHardwareModel = model;
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
                let currentAttempt = attemptingSsid;
                if (exitCode !== 0) {
                    networkLayoutRoot.failedSsid = networkLayoutRoot.connectingSsid;
                    if (currentAttempt !== "" && networkLayoutRoot.knownWifis.indexOf(currentAttempt) !== -1) {
                        failedAuthCleanUpProc.dropProfile(currentAttempt);
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
                
                // Added a fallback height property to handle varying data block dimensions safely
                property int expandedHeightOverride: 104

                signal clicked()

                Layout.fillWidth: true
                // Fix: Bind dynamically using the override fallback value
                Layout.preferredHeight: expanded ? expandedHeightOverride : 52
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
                    mainText: networkLayoutRoot.wifiInterfaceName
                    subText: networkLayoutRoot.wifiEnabled ? "Wi-Fi is ON" : "Wi-Fi is OFF"
                    iconGlyph: networkLayoutRoot.wifiEnabled ? "wifi" : "wifi_off"
                    isRowActive: false // Drop the highlight accent frame around the hardware toggle row
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

                // Scanned Access Points List Container
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16  // Indent left edge to define sub-section alignment
                    Layout.rightMargin: 16 // Narrow right edge symmetrically
                    spacing: 6

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
                                    ? "Wrong password!" 
                                    : (model.isConnected ? "Active connection profile" : (isSaved ? "Saved network profile" : "Signal strength: " + model.signal + "%")))
                            
                            isRowActive: model.isConnected
                            iconGlyph: model.isConnected ? "signal_wifi_4_bar" : (model.isSecure ? "network_wifi_locked" : "network_wifi")
                            isInteractiveElement: !isConnecting
                            expanded: networkLayoutRoot.expandedSsid === model.ssid

                            onClicked: {
                                if (networkLayoutRoot.expandedSsid === model.ssid) {
                                    networkLayoutRoot.expandedSsid = "";
                                    networkLayoutRoot.failedSsid = "";
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

                                            Text {
                                                text: "Password..."
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
            }

            // --- SUB-VIEW CONTENT: HARDWARE ETHERNET LINKS ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: networkLayoutRoot.currentSection === "ethernet"

                Repeater {
                    model: ethernetListModel
                    
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        // Giving it a solid, explicit pixel footprint that easily clears all 5 lines
                        Layout.preferredHeight: model.isConnected ? 210 : 52
                        radius: 8
                        color: "transparent"
                        border.color: themeBorder
                        border.width: 0
                        clip: true

                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Primary Header Bar Element (Matches your standard card layout dimensions)
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
                                            text: model.isConnected ? "lan" : "lan_disconnect"
                                            font.family: "Material Symbols Outlined"
                                            font.pixelSize: 22
                                            color: themeText
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                                        Text {
                                            text: model.interfaceName
                                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: themeText
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: model.isConnected ? model.profileName : model.statusText
                                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                                            font.pixelSize: 11
                                            color: themeSubtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            // Expanded Metrics Data List
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: model.isConnected
                                spacing: 10
                                Layout.topMargin: 2
                                Layout.bottomMargin: 14

                                // 1. IP Address Row
                                RowLayout {
                                    Layout.fillWidth: true; Layout.leftMargin: 54; Layout.rightMargin: 16; spacing: 12
                                    Text { text: "IP Address:"; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; font.bold: true; color: themeAccent; Layout.preferredWidth: 90 }
                                    Text { text: (model.ipAddress ? model.ipAddress : "Fetching...") + (model.subnetMask ? model.subnetMask : ""); font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; color: themeText; Layout.fillWidth: true; elide: Text.ElideRight }
                                }

                                // 2. Link Speed Row
                                RowLayout {
                                    Layout.fillWidth: true; Layout.leftMargin: 54; Layout.rightMargin: 16; spacing: 12
                                    Text { text: "Link Speed:"; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; font.bold: true; color: themeAccent; Layout.preferredWidth: 90 }
                                    Text { text: model.speed ? model.speed : "Fetching..."; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; color: themeText; Layout.fillWidth: true; elide: Text.ElideRight }
                                }

                                // 3. Gateway Row
                                RowLayout {
                                    Layout.fillWidth: true; Layout.leftMargin: 54; Layout.rightMargin: 16; spacing: 12
                                    Text { text: "Gateway:"; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; font.bold: true; color: themeAccent; Layout.preferredWidth: 90 }
                                    Text { text: model.gateway ? model.gateway : "Fetching..."; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; color: themeText; Layout.fillWidth: true; elide: Text.ElideRight }
                                }

                                // 4. DNS Servers Row
                                RowLayout {
                                    Layout.fillWidth: true; Layout.leftMargin: 54; Layout.rightMargin: 16; spacing: 12
                                    Text { text: "DNS Servers:"; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; font.bold: true; color: themeAccent; Layout.preferredWidth: 90 }
                                    Text { text: model.dnsServers ? model.dnsServers : "Fetching..."; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; color: themeText; Layout.fillWidth: true; elide: Text.ElideRight }
                                }

                                // 5. MAC Address Row
                                RowLayout {
                                    Layout.fillWidth: true; Layout.leftMargin: 54; Layout.rightMargin: 16; spacing: 12
                                    Text { text: "MAC Address:"; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; font.bold: true; color: themeAccent; Layout.preferredWidth: 90 }
                                    Text { text: model.macAddress ? model.macAddress : "Fetching..."; font.family: settingsWindow ? settingsWindow.selectedFont : "sans"; font.pixelSize: 12; color: themeText; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
