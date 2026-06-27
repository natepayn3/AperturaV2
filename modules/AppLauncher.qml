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

    // 🎯 The Reactive Bridge
    property color themeBackground: rootShell ? rootShell.colorBackground : "#11111b"
    property color themeText: rootShell ? rootShell.colorText : "#cdd6f4"
    property color themeAccent: rootShell ? rootShell.colorAccent : "#89b4fa"
    property color themeBorder: rootShell ? rootShell.colorBorder : "#313244"
    
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
        visible: false
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-launcher-preview"
        WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"

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
            Quickshell.execDetached(["fish", "-c", "echo '" + jsonStr + "' > ~/.cache/quickshell_launcher_pins.json"]);
        }

        Process {
            id: appFetcher
            // 🛠️ AWK expansion: Added comment extraction logic and sanitized JSON characters
            command: ["bash", "-c", "find /usr/share/applications ~/.local/share/applications -maxdepth 2 -name '*.desktop' 2>/dev/null | awk 'BEGIN { print \"[\"; c=0 } { name=\"\"; exec=\"\"; icon=\"\"; desc=\"\"; nshow=0; while ((getline line < $0) > 0) { if (line ~ /^Name=/ && name==\"\") name = substr(line, 6); if (line ~ /^Exec=/ && exec==\"\") exec = substr(line, 6); if (line ~ /^Icon=/ && icon==\"\") icon = substr(line, 6); if (line ~ /^Comment=/ && desc==\"\") desc = substr(line, 9); if (line ~ /^NoDisplay=true/) nshow=1 } close($0); if (name != \"\" && exec != \"\" && nshow==0) { gsub(/[\"\\\\]/, \"\", name); gsub(/[\"\\\\]/, \"\", exec); gsub(/[\"\\\\]/, \"\", icon); gsub(/[\"\\\\]/, \"\", desc); if (c > 0) print \",\"; printf \"{\\\"name\\\":\\\"%s\\\", \\\"exec\\\":\\\"%s\\\", \\\"icon\\\":\\\"%s\\\", \\\"desc\\\":\\\"%s\\\", \\\"path\\\":\\\"%s\\\"}\", name, exec, icon, desc, $0; c++ } } END { print \"]\" }'"]
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
                
                // 🔍 Search Optimization: Now matches keywords found inside descriptions as well
                if (query !== "" && !app.name.toLowerCase().includes(query) && !app.desc.toLowerCase().includes(query)) continue;

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
            propagateComposedEvents: true
            onPressed: (mouse) => {
                launcherModuleRoot.closeRequested();
                mouse.accepted = false; 
            }
        }

        Item {
            id: launcherCardFrame
            width: 600  
            height: 500 
            anchors.centerIn: parent
            transformOrigin: Item.Center

            MouseArea {
                anchors.fill: parent
                onPressed: (event) => event.accepted = true
                onClicked: (event) => event.accepted = true
            }

            states: [
                State {
                    name: "hidden"
                    when: !launcherModuleRoot.active
                    PropertyChanges { target: launcherCardFrame; opacity: 0.0; scale: 0.0 }
                },
                State {
                    name: "shown"
                    when: launcherModuleRoot.active
                    PropertyChanges { target: launcherCardFrame; opacity: 1.0; scale: 1.0 }
                }
            ]

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
                    SequentialAnimation {
                        ParallelAnimation {
                            NumberAnimation { target: launcherCardFrame; property: "scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                            NumberAnimation { target: launcherCardFrame; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                        }
                        ScriptAction {
                            script: launcherWindow.visible = false
                        }
                    }
                }
            ]

            Rectangle {
                id: cardMainBody
                anchors.fill: parent
                color: launcherModuleRoot.themeBackground
                radius: 24 
                border.color: launcherModuleRoot.themeAccent
                border.width: 2 
                antialiasing: true
            }

            Item {
                id: layoutContentWrapper
                anchors.fill: parent
                anchors.margins: 24 

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 16

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52 
                        placeholderText: "Search applications..."
                        font.family: rootShell.shellFont
                        font.pixelSize: 18 
                        color: rootShell.colorText
                        placeholderTextColor: rootShell.colorSubtext
                        selectByMouse: true
                        verticalAlignment: TextInput.AlignVCenter
                        
                        background: Rectangle {
                            color: Qt.rgba(0, 0, 0, 0.2)
                            border.color: searchInput.activeFocus ? launcherModuleRoot.themeAccent : launcherModuleRoot.themeBorder
                            border.width: 1
                            radius: 12 
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
                        color: launcherModuleRoot.themeAccent
                        opacity: 0.5 
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ListView {
                            id: appListView
                            spacing: 6
                            keyNavigationEnabled: false
                            model: launcherWindow.filteredApps
                            
                            delegate: ItemDelegate {
                                id: appDelegate
                                width: appListView.width
                                height: 64 // 📏 Increased height slightly to cleanly fit dual-line text rows
                                highlighted: appListView.currentIndex === index
                                
                                property string appExec: modelData.exec
                                property bool isPinned: launcherWindow.localPins.includes(modelData.path)

                                background: Rectangle {
                                    color: appDelegate.highlighted
                                        ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15)
                                        : (appDelegate.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                                    radius: 12 
                                    border.width: appDelegate.highlighted ? 1 : 0
                                    border.color: rootShell.colorAccent
                                }

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12 
                                    spacing: 16

                                    Image {
                                        Layout.preferredWidth: 32 
                                        Layout.preferredHeight: 32
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        source: Quickshell.iconPath(modelData.icon !== "" ? modelData.icon : "application-x-executable")
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }

                                    // 🔀 Stacked Layout: Clear parent of the invalid property
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        // Layout.alignment attached here positions the entire block vertically inside the RowLayout
                                        Layout.alignment: Qt.AlignVCenter 

                                        Text {
                                            text: modelData.name
                                            font.family: rootShell.shellFont
                                            font.pixelSize: 16
                                            color: appDelegate.isPinned ? rootShell.colorAccent : rootShell.colorText
                                            font.weight: appDelegate.isPinned ? Font.Bold : Font.Normal
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.desc !== "" ? modelData.desc : "Application"
                                            font.family: rootShell.shellFont
                                            font.pixelSize: 14
                                            color: rootShell.colorSubtext
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            opacity: 0.7
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true

                                    property point lastPos: Qt.point(-1, -1)

                                    onPositionChanged: (mouse) => {
                                        let currentPos = Qt.point(mouse.screenX, mouse.screenY);
                                        if (lastPos.x === -1 || lastPos.x !== currentPos.x || lastPos.y !== currentPos.y) {
                                            if (appListView.currentIndex !== index) {
                                                appListView.currentIndex = index;
                                            }
                                            lastPos = currentPos;
                                        }
                                    }

                                    onExited: {
                                        lastPos = Qt.point(-1, -1);
                                    }

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
        }
    }
}
