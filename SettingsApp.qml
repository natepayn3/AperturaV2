import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "."

Scope {
    id: settingsModuleRoot

    property var shellTarget: null
    property alias windowVisible: settingsWindow.visible

    function updateDisplaysFromShell() {
        if (shellTarget) {
            settingsWindow.enabledDisplays = shellTarget.enabledDisplayStr;
        }
    }

    PanelWindow {
        id: settingsWindow
        visible: false
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-settings"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        implicitWidth: 720
        implicitHeight: 520
        color: Qt.rgba(0, 0, 0, 0)

        anchors {
            left: false
            right: false
            top: false
            bottom: false
        }

        property string currentPosition: "left"
        property string enabledDisplays: "0"
        property string activeCategory: "Layout"

        readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell/Test"
        readonly property string configFilePath: configDir + "/shell_settings.json"

        Component.onCompleted: {
            if (shellTarget) {
                currentPosition = shellTarget.barPosition;
                enabledDisplays = shellTarget.enabledDisplayStr;
            }
        }

        Connections {
            target: settingsModuleRoot.shellTarget
            ignoreUnknownSignals: true

            function onBarPositionChanged() {
                if (settingsModuleRoot.shellTarget) {
                    settingsWindow.currentPosition = settingsModuleRoot.shellTarget.barPosition;
                }
            }

            function onEnabledDisplayStrChanged() {
                if (settingsModuleRoot.shellTarget) {
                    settingsWindow.enabledDisplays = settingsModuleRoot.shellTarget.enabledDisplayStr;
                }
            }
        }

        function isLocalDisplayActive(idx) {
            let items = enabledDisplays.split(",");
            return items.indexOf(String(idx)) !== -1;
        }

        function pushUpdate() {
            let updatePayload = {
                "position": settingsWindow.currentPosition,
                "enabledDisplays": settingsWindow.enabledDisplays
            };
            
            writeProc.command = [
                "bash", "-c", 
                "mkdir -p '" + configDir + "' && echo '" + JSON.stringify(updatePayload) + "' > '" + configFilePath + "'"
            ];
            writeProc.running = false;
            writeProc.running = true;
        }

        Process {
            id: writeProc
            running: false
        }

        Rectangle {
            anchors.fill: parent
            color: shellTarget ? shellTarget.colorBackground : "#cc11111b" 
            radius: 20
            border.color: shellTarget ? shellTarget.colorBorder : "#313244" 
            border.width: 3

            Row {
                anchors.fill: parent

                Rectangle {
                    width: 220
                    height: parent.height
                    color: "transparent"

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: shellTarget ? shellTarget.colorBorder : "#313244"
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 12

                        Text {
                            text: "Preferences"
                            font.family: "Rubik"
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1
                            color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                            height: 30
                            x: 20
                        }

                        component CategoryButton : Button {
                            property string categoryName: ""
                            flat: true
                            width: parent.width
                            height: 44
                            background: Rectangle { 
                                color: settingsWindow.activeCategory === categoryName ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                                radius: 10 
                            }
                            contentItem: Text { 
                                text: parent.categoryName
                                color: settingsWindow.activeCategory === categoryName ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                                font.family: "Rubik"
                                font.pixelSize: 16
                                font.bold: settingsWindow.activeCategory === categoryName
                                anchors.left: parent.left
                                anchors.leftMargin: 20
                                verticalAlignment: Text.AlignVCenter 
                            }
                            onClicked: settingsWindow.activeCategory = categoryName
                        }
                        CategoryButton { categoryName: "Layout" }
                        CategoryButton { categoryName: "Colors" }
                        CategoryButton { categoryName: "Modules" }
                        CategoryButton { categoryName: "Behavior" }
                    }
                }

                Item {
                    width: parent.width - 220
                    height: parent.height

                    Item {
                        id: contentHeader
                        width: parent.width
                        height: 70
                        anchors.top: parent.top

                        Text {
                            text: settingsWindow.activeCategory
                            font.family: "Rubik"
                            font.pixelSize: 26
                            font.bold: true
                            color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Button {
                            id: closeBtn
                            flat: true
                            anchors.right: parent.right
                            anchors.rightMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                            background: Rectangle { 
                                implicitWidth: 40
                                implicitHeight: 40
                                color: closeBtn.hovered ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                                radius: 10 
                            }
                            contentItem: Text { 
                                text: "✕"
                                font.family: "Rubik"
                                font.pixelSize: 20
                                font.bold: true
                                color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter 
                            }
                            onClicked: settingsWindow.visible = false
                        }
                    }

                    Item {
                        anchors.top: contentHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 30

                        Column {
                            anchors.fill: parent
                            spacing: 36
                            visible: settingsWindow.activeCategory === "Layout"

                            Column {
                                width: parent.width
                                spacing: 12

                                Text {
                                    text: "Show bar on these displays:"
                                    font.family: "Rubik"
                                    font.pixelSize: 20
                                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                    font.bold: true
                                }

                                Row {
                                    spacing: 12
                                    anchors.left: parent.left
                                    Repeater {
                                        model: Quickshell.screens
                                        delegate: Button {
                                            id: dispSelBtn
                                            flat: true
                                            width: 86
                                            height: 40
                                            property bool isSelected: settingsWindow.isLocalDisplayActive(index)
                                            background: Rectangle { 
                                                color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : "transparent"
                                                border.color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorBorder : "#313244")
                                                border.width: 2
                                                radius: 8 
                                            }
                                            contentItem: Text {
                                                text: modelData.name.toUpperCase()
                                                font.family: "Rubik"
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorBackground : "#11111b") : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            onClicked: {
                                                if (shellTarget) {
                                                    shellTarget.toggleDisplay(index);
                                                    settingsWindow.enabledDisplays = shellTarget.enabledDisplayStr;
                                                    settingsWindow.pushUpdate();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 16

                                Text {
                                    text: "Bar Orientation"
                                    font.family: "Rubik"
                                    font.pixelSize: 20
                                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                    font.bold: true
                                }

                                Item {
                                    width: 134
                                    height: 92
                                    anchors.left: parent.left
                                    anchors.leftMargin: -2

                                    Rectangle {
                                        id: monitorFrame
                                        x: 12
                                        y: 12
                                        width: 110
                                        height: 68
                                        color: "transparent"
                                        border.color: shellTarget ? shellTarget.colorBorder : "#313244"
                                        border.width: 2
                                        radius: 6

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 16
                                            height: 2
                                            color: shellTarget ? shellTarget.colorBorder : "#313244"
                                            opacity: 0.4
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 2
                                            height: 16
                                            color: shellTarget ? shellTarget.colorBorder : "#313244"
                                            opacity: 0.4
                                        }

                                        Rectangle {
                                            id: miniActiveBar
                                            color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                                            radius: 3

                                            // Establish clean base defaults
                                            x: 0; y: 0
                                            width: 6; height: parent.height

                                            // Explicitly define property values for each state configuration
                                            states: [
                                                State {
                                                    name: "left"
                                                    when: settingsWindow.currentPosition === "left"
                                                    PropertyChanges { target: miniActiveBar; x: 0; y: 0; width: 6; height: monitorFrame.height }
                                                },
                                                State {
                                                    name: "right"
                                                    when: settingsWindow.currentPosition === "right"
                                                    PropertyChanges { target: miniActiveBar; x: monitorFrame.width - 6; y: 0; width: 6; height: monitorFrame.height }
                                                },
                                                State {
                                                    name: "top"
                                                    when: settingsWindow.currentPosition === "top"
                                                    PropertyChanges { target: miniActiveBar; x: 0; y: 0; width: monitorFrame.width; height: 6 }
                                                },
                                                State {
                                                    name: "bottom"
                                                    when: settingsWindow.currentPosition === "bottom"
                                                    PropertyChanges { target: miniActiveBar; x: 0; y: monitorFrame.height - 6; width: monitorFrame.width; height: 6 }
                                                }
                                            ]

                                            // Intercept state changes and animate properties smoothly without cross-talk
                                            transitions: [
                                                Transition {
                                                    ParallelAnimation {
                                                        NumberAnimation { properties: "x,y,width,height"; duration: 150; easing.type: Easing.OutCubic }
                                                    }
                                                }
                                            ]
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: (mouse) => {
                                            let localX = mouse.x - monitorFrame.x;
                                            let localY = mouse.y - monitorFrame.y;
                                            
                                            let xPct = Math.max(0.0, Math.min(1.0, localX / monitorFrame.width));
                                            let yPct = Math.max(0.0, Math.min(1.0, localY / monitorFrame.height));
                                            
                                            let dists = [yPct, 1 - yPct, xPct, 1 - xPct];
                                            let minIdx = dists.indexOf(Math.min(...dists));
                                            let edges = ["top", "bottom", "left", "right"];
                                            
                                            settingsWindow.currentPosition = edges[minIdx];
                                            if (shellTarget) shellTarget.triggerOrientationChange(edges[minIdx]);
                                            settingsWindow.pushUpdate();
                                        }
                                    }
                                }
                            }
                        }
                        
                        Loader {
                            anchors.fill: parent
                            active: settingsWindow.activeCategory !== "Layout"
                            sourceComponent: Component {
                                Text { 
                                    text: "Configuration for " + settingsWindow.activeCategory + " is coming soon."
                                    font.family: "Rubik"
                                    font.pixelSize: 20
                                    color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}