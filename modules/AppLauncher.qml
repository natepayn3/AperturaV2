import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: launcherModuleRoot

    property alias launcherWindowObject: launcherWindow
    
    // Decouple the public active flag so it kicks off the exit states 
    // instead of destroying the layout instance instantly
    property bool active: false
    onActiveChanged: {
        if (active) {
            launcherWindow.visible = true;
        }
    }

    signal closeRequested()
    onCloseRequested: launcherModuleRoot.active = false

    PanelWindow {
        id: launcherWindow
        // Controlled dynamically by the end of the transition curve
        visible: false
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-launcher-preview"
        WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"

        // --- State Properties & Functions (Unchanged) ---
        property var allApps: []
        property var filteredApps: []
        property var localPins: []

        FileView {
            id: pinCacheReader
            path: Quickshell.env("HOME") + "/.cache/quickshell_launcher_pins.json"
            onTextChanged: {
                let cleanText = text().trim();
                if (!cleanText || cleanText === "[]") return;
                try {
                    let parsed = JSON.parse(cleanText);
                    if (parsed && parsed.pins) {
                        launcherWindow.localPins = parsed.pins;
                        launcherWindow.updateModel();
                    }
                } catch(e) {}
            }
        }

        function togglePin(appPath) {
            let currentPins = launcherWindow.localPins.slice();
            let idx = currentPins.indexOf(appPath);
            if (idx !== -1) {
                currentPins.splice(idx, 1);
            } else {
                currentPins.push(appPath);
            }
            launcherWindow.localPins = currentPins;
            launcherWindow.updateModel();
            
            let jsonStr = JSON.stringify({ "pins": currentPins });
            Quickshell.execDetached(["bash", "-c", "echo '" + jsonStr + "' > ~/.cache/quickshell_launcher_pins.json"]);
        }

        Process {
            id: appFetcher
            command: ["bash", "-c", "find /usr/share/applications ~/.local/share/applications -maxdepth 2 -name '*.desktop' 2>/dev/null | awk 'BEGIN { print \"[\"; c=0 } { name=\"\"; exec=\"\"; icon=\"\"; nshow=0; while ((getline line < $0) > 0) { if (line ~ /^Name=/ && name==\"\") name = substr(line, 6); if (line ~ /^Exec=/ && exec==\"\") exec = substr(line, 6); if (line ~ /^Icon=/ && icon==\"\") icon = substr(line, 6); if (line ~ /^NoDisplay=true/) nshow=1 } close($0); if (name != \"\" && exec != \"\" && nshow==0) { gsub(/[\"\\\\]/, \"\", name); gsub(/[\"\\\\]/, \"\", exec); gsub(/[\"\\\\]/, \"\", icon); if (c > 0) print \",\"; printf \"{\\\"name\\\":\\\"%s\\\", \\\"exec\\\":\\\"%s\\\", \\\"icon\\\":\\\"%s\\\", \\\"path\\\":\\\"%s\\\"}\", name, exec, icon, $0; c++ } } END { print \"]\" }'"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        launcherWindow.allApps = JSON.parse(this.text);
                        launcherWindow.updateModel();
                    } catch(e) {}
                }
            }
        }

        function updateModel() {
            let query = searchInput.text.trim().toLowerCase();
            let pins = [];
            let others = [];

            for (let i = 0; i < launcherWindow.allApps.length; i++) {
                let app = launcherWindow.allApps[i];
                if (query !== "" && !app.name.toLowerCase().includes(query)) continue;

                if (launcherWindow.localPins.includes(app.path)) {
                    pins.push(app);
                } else {
                    others.push(app);
                }
            }

            pins.sort((a,b) => a.name.localeCompare(b.name));
            others.sort((a,b) => a.name.localeCompare(b.name));
            launcherWindow.filteredApps = pins.concat(others);
            
            appListView.currentIndex = 0;
            appListView.positionViewAtBeginning(); 
        }

        function launchApp(execString) {
            let cleanExec = execString.replace(/%[uUfFkKcCiI]/g, "").trim();
            Hyprland.dispatch(`hl.dsp.exec_cmd("${cleanExec}")`);
            launcherModuleRoot.closeRequested();
        }

        // Changed target from visibility changes to the public activation state token
        onVisibleChanged: {
            if (visible) {
                if (allApps.length === 0) appFetcher.running = true;
                searchInput.text = "";
                searchInput.forceActiveFocus();
                pinCacheReader.reload();
                updateModel();
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: launcherModuleRoot.closeRequested()

            Item {
                id: launcherCardFrame
                width: 400
                height: 400
                anchors.centerIn: parent
                transformOrigin: Item.Center

                // --- Animation States ---
                states: [
                    State {
                        name: "hidden"
                        // Tie tracking flags straight to the public module property state
                        when: !launcherModuleRoot.active
                        PropertyChanges { target: launcherCardFrame; opacity: 0.0; scale: 0.0 }
                    },
                    State {
                        name: "shown"
                        when: launcherModuleRoot.active
                        PropertyChanges { target: launcherCardFrame; opacity: 1.0; scale: 1.0 }
                    }
                ]

                // --- Animation Transitions ---
                transitions: [
                    Transition {
                        from: "hidden"; to: "shown"
                        ParallelAnimation {
                            NumberAnimation { target: launcherCardFrame; property: "scale"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                            NumberAnimation { target: launcherCardFrame; property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                        }
                    },
                    Transition {
                        from: "shown"; to: "hidden"
                        // SequentialAnimation ensures the window visibility toggle waits for the scale/opacity to finish
                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation { target: launcherCardFrame; property: "scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                                NumberAnimation { target: launcherCardFrame; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                            }
                            // Safe Exit: Turning off window visibility ONLY after the transition finishes animating
                            ScriptAction {
                                script: launcherWindow.visible = false
                            }
                        }
                    }
                ]

                Rectangle {
                    id: cardMainBody
                    anchors.fill: parent
                    color: rootShell.colorBackground
                    radius: 20
                    border.color: rootShell.colorText
                    border.width: 3
                    antialiasing: true
                }

                Item {
                    id: layoutContentWrapper
                    anchors.fill: parent
                    anchors.margins: 20

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 14

                        TextField {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            placeholderText: "Search applications..."
                            font.family: rootShell.shellFont
                            font.pixelSize: 15
                            color: rootShell.colorText
                            placeholderTextColor: rootShell.colorSubtext
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            
                            background: Rectangle {
                                color: Qt.rgba(0, 0, 0, 0.2)
                                border.color: searchInput.activeFocus ? rootShell.colorAccent : rootShell.colorBorder
                                border.width: 1
                                radius: 8
                            }

                            onTextChanged: launcherWindow.updateModel()

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Down) {
                                    appListView.incrementCurrentIndex();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    appListView.decrementCurrentIndex();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (appListView.currentItem) {
                                        launcherWindow.launchApp(appListView.currentItem.appExec);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    launcherModuleRoot.closeRequested();
                                    event.accepted = true;
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: rootShell.colorText
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                id: appListView
                                spacing: 4
                                keyNavigationEnabled: false
                                model: launcherWindow.filteredApps
                                
                                delegate: ItemDelegate {
                                    id: appDelegate
                                    width: appListView.width
                                    height: 46
                                    highlighted: appListView.currentIndex === index
                                    
                                    property string appExec: modelData.exec
                                    property bool isPinned: launcherWindow.localPins.includes(modelData.path)

                                    background: Rectangle {
                                        color: appDelegate.highlighted
                                            ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15)
                                            : (appDelegate.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                                        radius: 8
                                        border.width: appDelegate.highlighted ? 1 : 0
                                        border.color: rootShell.colorAccent
                                    }

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 12

                                        Image {
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26
                                            source: Quickshell.iconPath(modelData.icon !== "" ? modelData.icon : "application-x-executable")
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }

                                        Text {
                                            text: modelData.name
                                            font.family: rootShell.shellFont
                                            font.pixelSize: 14
                                            color: appDelegate.isPinned ? rootShell.colorAccent : rootShell.colorText
                                            font.weight: appDelegate.isPinned ? Font.Bold : Font.Normal
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        Text {
                                            text: "keep"
                                            visible: appDelegate.isPinned
                                            font.family: "Material Symbols Outlined"
                                            font.pixelSize: 16
                                            color: rootShell.colorAccent
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true

                                        onEntered: appListView.currentIndex = index

                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.RightButton) {
                                                launcherWindow.togglePin(modelData.path);
                                            } else {
                                                launcherWindow.launchApp(modelData.exec);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true; }
                }
            }
        }
    }
}
