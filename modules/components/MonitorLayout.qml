import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

Item {
    id: monitorLayoutModuleRoot

    property var shellTarget: null
    property var settingsWindow: null

    Column {
        anchors.fill: parent
        spacing: 32

        // Display Selection Section
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Show bar on these displays:"
                font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
                font.pixelSize: 20
                color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter
                
                Repeater {
                    // FIX: Connect directly to the geometry sorting matrix array instead of raw Quickshell order
                    model: settingsWindow ? settingsWindow.getGeometricallySortedScreens() : []
                    
                    delegate: Button {
                        id: dispSelBtn
                        flat: true
                        width: 96
                        height: 42
                        
                        // FIX: Pull immutable hardware indexes from the custom geometric tracking payload
                        property int realHardwareIndex: modelData.index
                        property bool isSelected: settingsWindow ? settingsWindow.isLocalDisplayActive(realHardwareIndex) : false
                        
                        background: Rectangle { 
                            color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : "transparent"
                            
                            // FIXED: Lifted dim container outline up to follow active colorText token
                            border.color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                            border.width: 1
                            radius: 8 
                        }
                        
                        contentItem: Text {
                            // Pull name string parameters from the target live screen C++ model object wrapper
                            text: modelData.obj.name.toUpperCase()
                            font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
                            font.pixelSize: 13
                            font.bold: true
                            color: dispSelBtn.isSelected ? (shellTarget ? shellTarget.colorBackground : "#11111b") : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            if (shellTarget && settingsWindow) {
                                // Enforce safe real hardware index execution routing toggles
                                shellTarget.toggleDisplay(realHardwareIndex);
                                settingsWindow.enabledDisplays = shellTarget.enabledDisplayStr;
                                settingsWindow.pushUpdate();
                            }
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }
        }

        // Bar Orientation Section
        Column {
            width: parent.width
            spacing: 16

            Text {
                text: "Bar Orientation"
                font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
                font.pixelSize: 20
                color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
                id: monitorFrame
                width: 140
                height: 86
                color: "transparent"
                
                // FIXED: Set monitor preview card box boundary outline to colorText
                border.color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                border.width: 1
                radius: 8
                anchors.horizontalCenter: parent.horizontalCenter

                // Crosshair guides
                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 2
                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    opacity: 0.3
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: 20
                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    opacity: 0.3
                }

                // Viewport layout container to manage position states without anchoring conflicts
                Item {
                    anchors.fill: parent

                    Rectangle {
                        id: miniActiveBar
                        color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                        radius: 4

                        // Default dimensions (overridden by states)
                        width: 8
                        height: 8

                        states: [
                            State {
                                name: "left"
                                when: !settingsWindow || settingsWindow.currentPosition === "left"
                                PropertyChanges { target: miniActiveBar; x: 0; y: 0; width: 8; height: parent.height }
                            },
                            State {
                                name: "right"
                                when: settingsWindow && settingsWindow.currentPosition === "right"
                                PropertyChanges { target: miniActiveBar; x: parent.width - 8; y: 0; width: 8; height: parent.height }
                            },
                            State {
                                name: "top"
                                when: settingsWindow && settingsWindow.currentPosition === "top"
                                PropertyChanges { target: miniActiveBar; x: 0; y: 0; width: parent.width; height: 8 }
                            },
                            State {
                                name: "bottom"
                                when: settingsWindow && settingsWindow.currentPosition === "bottom"
                                PropertyChanges { target: miniActiveBar; x: 0; y: parent.height - 8; width: parent.width; height: 8 }
                            }
                        ]

                        transitions: [
                            Transition {
                                from: "*"; to: "*"
                                ParallelAnimation {
                                    NumberAnimation { properties: "x,y,width,height"; duration: 150; easing.type: Easing.OutCubic }
                                }
                            }
                        ]
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    cursorShape: Qt.PointingHandCursor
                    
                    onClicked: (mouse) => {
                        if (!settingsWindow) return;
                        let localX = mouse.x + anchors.margins;
                        let localY = mouse.y + anchors.margins;
                        
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
}
