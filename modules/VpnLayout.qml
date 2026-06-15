import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Item {
    id: vpnLayoutRoot

    property var shellTarget: null
    property var settingsWindow: null

    // --- Core State Management ---
    property string activeVpnName: ""
    property string publicIpAddress: "" 
    property bool textVisible: true
    
    property bool hasImportError: false
    property bool showFileBrowser: false
    property string currentBrowserPath: "file://" + Quickshell.env("HOME")

    // Auto-clears the red text error state cleanly after 5 seconds
    Timer {
        id: errorDismissTimer
        interval: 5000
        repeat: false
        running: vpnLayoutRoot.hasImportError
        onTriggered: vpnLayoutRoot.hasImportError = false
    }

    // Explicit internal data store allows smooth tracking of rows
    ListModel {
        id: vpnListModel
    }

    // Reset browser directory to $HOME and hide warnings whenever settings app opens
    Connections {
        target: settingsWindow
        ignoreUnknownSignals: true
        
        function onVisibleChanged() {
            if (settingsWindow && settingsWindow.visible) {
                vpnLayoutRoot.showFileBrowser = false;
                vpnLayoutRoot.hasImportError = false;
                vpnLayoutRoot.currentBrowserPath = "file://" + Quickshell.env("HOME");
                vpnListPopulator.running = false;
                vpnListPopulator.running = true;
            }
        }
    }

    // Polling engine keeps state tracks synchronized
    Timer {
        id: syncVpnTimer
        interval: 3000
        running: settingsWindow && settingsWindow.visible && !vpnLayoutRoot.showFileBrowser
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
        }
    }

    Timer {
        id: delayFetchTimer
        interval: 800 
        repeat: false
        running: false
        onTriggered: {
            publicIpFetcher.running = false;
            publicIpFetcher.running = true;
        }
    }

    // Robust Scraper processes system outputs into the local ListModel container smoothly
    Process {
        id: vpnListPopulator
        command: ["nmcli", "-g", "TYPE,NAME,STATE", "connection", "show"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanText = text.trim();
                if (!cleanText) {
                    vpnListModel.clear();
                    vpnLayoutRoot.activeVpnName = "";
                    return;
                }

                let lines = cleanText.split("\n");
                let incomingProfiles = [];
                let currentActive = "";

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    let parts = line.split(":");
                    if (parts.length >= 2) {
                        let type = parts[0];
                        let name = parts[1];
                        let state = parts[2] || "";

                        if (type === "wireguard" || type === "vpn" || type === "tun") {
                            let isActive = (state.indexOf("activated") !== -1);
                            if (isActive) {
                                currentActive = name;
                            }
                            if (incomingProfiles.indexOf(name) === -1) {
                                incomingProfiles.push(name);
                            }
                        }
                    }
                }

                vpnLayoutRoot.activeVpnName = currentActive;

                // Sync incoming profiles to our local ListModel without breaking object allocations
                for (let m = vpnListModel.count - 1; m >= 0; m--) {
                    let currentModelName = vpnListModel.get(m).profileName;
                    if (incomingProfiles.indexOf(currentModelName) === -1) {
                        vpnListModel.remove(m);
                    }
                }

                for (let p = 0; p < incomingProfiles.length; p++) {
                    let pName = incomingProfiles[p];
                    let foundIndex = -1;
                    
                    for (let m = 0; m < vpnListModel.count; m++) {
                        if (vpnListModel.get(m).profileName === pName) {
                            foundIndex = m;
                            break;
                        }
                    }

                    if (foundIndex === -1) {
                        vpnListModel.append({ "profileName": pName });
                    }
                }

                if (vpnLayoutRoot.activeVpnName !== "") {
                    for (let m = 0; m < vpnListModel.count; m++) {
                        if (vpnListModel.get(m).profileName === vpnLayoutRoot.activeVpnName) {
                            if (m !== 0) {
                                vpnListModel.move(m, 0, 1);
                            }
                            break;
                        }
                    }
                } else {
                    let sortingChanged = true;
                    while (sortingChanged) {
                        sortingChanged = false;
                        for (let i = 0; i < vpnListModel.count - 1; i++) {
                            let nameA = vpnListModel.get(i).profileName;
                            let nameB = vpnListModel.get(i+1).profileName;
                            if (nameA.localeCompare(nameB, undefined, { numeric: true }) > 0) {
                                vpnListModel.move(i + 1, i, 1);
                                sortingChanged = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // Dynamic Connection State Machine Manager
    Process {
        id: vpnStateExecutor
        running: false
        onExited: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
            delayFetchTimer.restart();
        }
    }

    // Native Public IP Scraper
    Process {
        id: publicIpFetcher
        command: ["curl", "-s", "-4", "icanhazip.com"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanIp = text.trim();
                if (cleanIp) {
                    vpnLayoutRoot.publicIpAddress = cleanIp;
                    vpnLayoutRoot.textVisible = true;
                }
            }
        }
    }

    // Pipeline: Attempts raw import and checks stderr stream for validation block tokens
    Process {
        id: vpnImporter
        running: false
        stderr: StdioCollector {
            onTextChanged: {
                if (text.indexOf("QS_IMPORT_FAILED") !== -1 || text.toLowerCase().indexOf("error") !== -1) {
                    vpnLayoutRoot.hasImportError = true;
                }
            }
        }
        onExited: {
            if (!vpnLayoutRoot.hasImportError) {
                notifyProc.command = ["notify-send", "-a", "VPN Manager", "-i", "network-vpn", "Profile Imported", "Configuration processed successfully."];
                notifyProc.running = true;
                nmcliReloader.running = true;
            }
        }
    }

    Process {
        id: nmcliReloader
        command: ["nmcli", "connection", "reload"]
        running: false
        onExited: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
        }
    }

    Process {
        id: notifyProc
        running: false
    }

    // Isolated state changes prevent crossover triggering blocks
    function toggleProfileState(profileName, itemChecked) {
        vpnLayoutRoot.textVisible = false;
        
        if (itemChecked) {
            if (vpnLayoutRoot.activeVpnName !== "" && vpnLayoutRoot.activeVpnName !== profileName) {
                vpnStateExecutor.command = [
                    "bash", "-c",
                    "nmcli connection down id '" + vpnLayoutRoot.activeVpnName + "' && nmcli connection up id '" + profileName + "'"
                ];
            } else {
                vpnStateExecutor.command = ["nmcli", "connection", "up", "id", profileName];
            }
        } else {
            vpnStateExecutor.command = ["nmcli", "connection", "down", "id", profileName];
        }
        vpnStateExecutor.running = true;
    }

    Component.onCompleted: {
        publicIpFetcher.running = true;
        vpnListPopulator.running = true;
    }

    // --- Core Layout Rendering Area ---
    Item {
        anchors.fill: parent

        // Main Profile Control Panel
        ColumnLayout {
            anchors.fill: parent
            spacing: 16
            visible: !vpnLayoutRoot.showFileBrowser

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Available profiles:"
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 16
                    font.bold: true
                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    Layout.fillWidth: true
                }

                Button {
                    id: importBtn
                    flat: true
                    implicitWidth: 150
                    implicitHeight: 34

                    background: Rectangle {
                        color: importBtn.hovered ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                        border.color: shellTarget ? shellTarget.colorBorder : "#313244"
                        border.width: 1
                        radius: 8
                    }

                    contentItem: Item {
                        anchors.fill: parent
                        RowLayout {
                            spacing: 6
                            anchors.centerIn: parent
                            
                            Text {
                                text: "upload_file"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                                color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                            }
                            Text {
                                text: "Import Profile"
                                font.family: settingsWindow.selectedFont
                                font.pixelSize: 13
                                font.bold: true
                                color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                            }
                        }
                    }

                    onClicked: {
                        vpnLayoutRoot.hasImportError = false;
                        vpnLayoutRoot.showFileBrowser = true;
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }

            // Fallback visual block if zero WireGuard profiles exist
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                color: Qt.rgba(0, 0, 0, 0.15)
                radius: 12
                border.color: shellTarget ? shellTarget.colorBorder : "#313244"
                border.width: 1
                visible: vpnListModel.count === 0

                Text {
                    anchors.centerIn: parent
                    text: "No VPN Profiles found. Click 'Import Profile' above to add a .conf file."
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 13
                    color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: profileListView
                    anchors.fill: parent
                    spacing: 10
                    clip: true
                    model: vpnListModel
                    
                    topMargin: 20
                    bottomMargin: 20

                    move: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: 220
                            easing.type: Easing.Linear
                        }
                    }

                    moveDisplaced: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: 220
                            easing.type: Easing.Linear
                        }
                    }

                    delegate: Rectangle {
                        id: profileCard
                        width: profileListView.width - 4 
                        height: 84
                        color: Qt.rgba(0, 0, 0, 0.15)
                        radius: 12
                        border.color: vpnLayoutRoot.activeVpnName === profileName 
                            ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                            : (shellTarget ? shellTarget.colorBorder : "#313244")
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14

                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: vpnLayoutRoot.activeVpnName === profileName ? Qt.rgba(137/255, 180/255, 250/255, 0.15) : Qt.rgba(1, 1, 1, 0.05)

                                Text {
                                    anchors.centerIn: parent
                                    text: vpnLayoutRoot.activeVpnName === profileName ? "vpn_key" : "vpn_key_off"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 20
                                    color: vpnLayoutRoot.activeVpnName === profileName ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorSubtext : "#a6adc8")
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true

                                Text {
                                    text: profileName 
                                    font.family: settingsWindow.selectedFont
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                    elide: Text.ElideRight
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true

                                    Text {
                                        text: vpnLayoutRoot.activeVpnName === profileName ? "Connected" : "Disconnected"
                                        font.family: settingsWindow.selectedFont
                                        font.pixelSize: 12
                                        color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                                    }

                                    Text {
                                        text: (vpnLayoutRoot.activeVpnName === profileName && vpnLayoutRoot.publicIpAddress !== "") 
                                            ? vpnLayoutRoot.publicIpAddress 
                                            : "No active endpoint"
                                        font.family: settingsWindow.selectedFont
                                        font.pixelSize: 11
                                        color: vpnLayoutRoot.activeVpnName === profileName ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : "transparent"
                                        opacity: vpnLayoutRoot.textVisible ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                }
                            }

                            Switch {
                                id: itemToggleSwitch
                                checked: vpnLayoutRoot.activeVpnName === profileName
                                
                                onClicked: {
                                    vpnLayoutRoot.toggleProfileState(profileName, checked);
                                }

                                background: Rectangle {
                                    implicitWidth: 44
                                    implicitHeight: 22
                                    radius: 11
                                    color: itemToggleSwitch.checked 
                                        ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                                        : (shellTarget ? shellTarget.colorBorder : "#313244")
                                    
                                    Rectangle {
                                        width: 16; height: 16; radius: 8; color: "#11111b"
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: itemToggleSwitch.checked ? 24 : 4
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                    }
                                }
                                indicator: Item {}
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                    ScrollBar.vertical: ScrollBar {}
                }

                Text {
                    id: floatingErrorText
                    text: "Error: check your config"
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 13
                    font.bold: true
                    color: "#f38ba8"
                    
                    anchors.top: parent.top
                    anchors.topMargin: -2 
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    visible: opacity > 0.0
                    opacity: vpnLayoutRoot.hasImportError ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }
        }

        // --- Custom Embedded File Browser Component ---
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            visible: vpnLayoutRoot.showFileBrowser

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Select WireGuard Config File:"
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 15
                    font.bold: true
                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    Layout.fillWidth: true
                }

                Button {
                    id: cancelBrowserBtn
                    flat: true
                    implicitWidth: 80
                    implicitHeight: 30
                    background: Rectangle {
                        color: cancelBrowserBtn.hovered ? Qt.rgba(1,1,1,0.08) : "transparent"
                        radius: 6
                    }
                    contentItem: Text {
                        text: "Cancel"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: settingsWindow.selectedFont
                        color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                    }
                    onClicked: vpnLayoutRoot.showFileBrowser = false
                }
            }

            Text {
                text: vpnLayoutRoot.currentBrowserPath.replace("file://", "")
                font.family: settingsWindow.selectedFont
                font.pixelSize: 12
                color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                elide: Text.ElideLeft
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(0, 0, 0, 0.2)
                radius: 10
                border.color: shellTarget ? shellTarget.colorBorder : "#313244"
                border.width: 1
                clip: true

                Item {
                    id: browserViewContainer
                    anchors.fill: parent
                    
                    property string pendingPath: ""
                    property string lastPath: ""

                    ListView {
                        id: fileListView
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        clip: true
                        
                        Behavior on contentY {
                            NumberAnimation { duration: 180; easing.type: Easing.Linear }
                        }

                        model: FolderListModel {
                            id: folderModel
                            folder: vpnLayoutRoot.currentBrowserPath
                            showDirsFirst: true
                            showDotAndDotDot: true
                            nameFilters: ["*.conf"] 
                        }

                        populate: null

                        delegate: ItemDelegate {
                            width: fileListView.width
                            height: 38
                            
                            background: Rectangle {
                                color: hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                radius: 6
                            }

                            contentItem: RowLayout {
                                spacing: 10
                                anchors.fill: parent
                                anchors.leftMargin: 8

                                Text {
                                    text: fileIsDir ? "folder" : "description"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 18
                                    color: fileIsDir ? "#f9e2af" : (shellTarget ? shellTarget.colorAccent : "#89b4fa")
                                }

                                Text {
                                    text: fileName
                                    font.family: settingsWindow.selectedFont
                                    font.pixelSize: 13
                                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                    Layout.fillWidth: true
                                }
                            }

                            onClicked: {
                                if (fileIsDir) {
                                    // 🛠️ FIX: Store the click metadata safely without altering the model target path yet
                                    browserViewContainer.lastPath = vpnLayoutRoot.currentBrowserPath;
                                    browserViewContainer.pendingPath = fileUrl.toString();
                                    
                                    // Fire sequential outward animation block first
                                    pathFadeAnimation.start();
                                } else {
                                    let urlString = fileUrl.toString();
                                    let parsedPath = urlString.startsWith("file:///") 
                                        ? urlString.substring(7) 
                                        : urlString.replace("file://", "");

                                    vpnImporter.command = [
                                        "bash", "-c",
                                        "nmcli connection import type wireguard file '" + parsedPath + "' || echo 'QS_IMPORT_FAILED' >&2"
                                    ];
                                    vpnImporter.running = true;
                                    vpnLayoutRoot.showFileBrowser = false;
                                }
                            }
                        }
                        ScrollBar.vertical: ScrollBar {}
                    }

                    // 🛠️ FIX: Staged timeline prevents model text blinking.
                    // The old directory view slides completely away to blank space *before* updating the path strings.
                    SequentialAnimation {
                        id: pathFadeAnimation
                        
                        // Phase 1: Slide and fade out the existing frozen directory view data
                        ParallelAnimation {
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "opacity"
                                from: 1.0; to: 0.0
                                duration: 110
                                easing.type: Easing.Linear
                            }
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "x"
                                to: (browserViewContainer.pendingPath.length > browserViewContainer.lastPath.length) ? -30 : 30
                                duration: 110
                                easing.type: Easing.Linear
                            }
                        }
                        
                        // Phase 2: Complete the path transition safely while hidden
                        ScriptAction {
                            script: {
                                vpnLayoutRoot.currentBrowserPath = browserViewContainer.pendingPath;
                            }
                        }
                        
                        // Phase 3: Teleport the canvas boundary wrapper to its incoming opposite offset vector
                        PropertyAction {
                            target: browserViewContainer
                            property: "x"
                            value: (browserViewContainer.pendingPath.length > browserViewContainer.lastPath.length) ? 30 : -30
                        }
                        
                        // Phase 4: Slide cleanly back up from blank space to center position with the fresh data layout loaded
                        ParallelAnimation {
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "opacity"
                                from: 0.0; to: 1.0
                                duration: 130
                                easing.type: Easing.Linear
                            }
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "x"
                                to: 0
                                duration: 130
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }
            }
        }
    }
}
