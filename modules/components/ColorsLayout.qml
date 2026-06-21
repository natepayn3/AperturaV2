import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: colorsLayoutRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"

    Binding {
        target: settingsWindow
        property: "matugenScheme"
        value: shellTarget && shellTarget.wallpaperRef ? shellTarget.wallpaperRef.currentScheme : "scheme-tonal-spot"
    }

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
            spacing: 8 

            component ProfileCard : Button {
                id: cardBtn
                property string schemeId: ""
                property string schemeLabel: ""
                property var customPalette: {
                    let tick = shellTarget ? shellTarget.matugenPreviewTick : 0;
                    return shellTarget && shellTarget.matugenPreviews ? (shellTarget.matugenPreviews[schemeId] || []) : [];
                }
                Layout.fillWidth: true
                Layout.preferredHeight: 48 
                flat: true

                background: Rectangle {
                    color: settingsWindow.matugenScheme === schemeId 
                        ? Qt.rgba(themeBorder.r, themeBorder.g, themeBorder.b, 0.1) 
                        : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    border.color: settingsWindow.matugenScheme === schemeId 
                        ? themeAccent 
                        : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                    border.width: settingsWindow.matugenScheme === schemeId ? 2 : 1
                    radius: 8
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 24
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: "palette"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 20 
                            color: settingsWindow.matugenScheme === schemeId ? themeAccent : themeText
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: schemeLabel
                        font.family: settingsWindow.selectedFont
                        font.pixelSize: 13
                        font.bold: true
                        color: themeText
                        verticalAlignment: Text.AlignVCenter
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: 10
                        visible: true
                        opacity: settingsWindow.matugenScheme === schemeId ? 1.0 : 0.4
                        
                        Repeater {
                            model: cardBtn.customPalette.length > 0 
                                 ? cardBtn.customPalette 
                                 : [themeText, themeText, themeText]
                            
                            RowLayout {
                                spacing: 4
                                
                                Rectangle {
                                    width: 12 
                                    height: 12
                                    radius: 3
                                    color: cardBtn.customPalette.length > 0 ? modelData : Qt.rgba(1, 1, 1, 0.1)
                                    border.color: Qt.rgba(1, 1, 1, 0.2)
                                    border.width: 1
                                }
                                
                                Text {
                                    text: cardBtn.customPalette.length > 0 ? String(modelData).substring(0, 7).toUpperCase() : "..."
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    color: themeText
                                }
                            }
                        }
                    }
                }

                onClicked: {
                    settingsWindow.matugenScheme = schemeId;
                    settingsWindow.pushUpdate();
                    if (shellTarget && shellTarget.wallpaperRef) {
                        let activeWallpaper = shellTarget.wallpaperRef.currentWallpaperPath || "";
                        shellTarget.wallpaperRef.apply(activeWallpaper, false, schemeId);
                    }
                }
                
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            Button {
                id: shutterBtn
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                Layout.preferredHeight: 48
                Layout.alignment: Qt.AlignLeft
                flat: true
                readonly property bool isActive: shellTarget ? shellTarget.shutterModeActive : false

                background: Rectangle {
                    color: shutterBtn.isActive 
                        ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 0.08)
                        : (shutterBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    border.color: shutterBtn.isActive ? themeAccent : (shutterBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                    border.width: shutterBtn.isActive ? 2 : 1
                    radius: 8
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 24
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: shutterBtn.isActive ? "control_camera" : "camera"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 20
                            color: shutterBtn.isActive ? themeAccent : themeText
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0 
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                        Text {
                            text: "Shutter Mode"
                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                            font.pixelSize: 13
                            font.bold: true
                            color: themeText
                            Layout.fillWidth: true               
                            horizontalAlignment: Text.AlignLeft  
                        }
                        
                        Text {
                            text: shutterBtn.isActive ? "Transparency OFF" : "Transparency ON"
                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                            font.pixelSize: 10
                            color: themeText
                            opacity: shutterBtn.isActive ? 0.6 : 0.4
                            Layout.fillWidth: true               
                            horizontalAlignment: Text.AlignLeft  
                        }
                    }
                    
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 5
                        color: shutterBtn.isActive ? themeAccent : "transparent"
                        border.color: shutterBtn.isActive ? themeAccent : Qt.rgba(themeText.r, themeText.g, themeText.b, 0.3)
                        border.width: shutterBtn.isActive ? 0 : 1
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            text: "done"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 12
                            font.bold: true
                            color: "#0B0F19"
                            anchors.centerIn: parent
                            visible: shutterBtn.isActive
                        }
                    }
                }

                onClicked: {
                    if (shellTarget && typeof shellTarget.toggleShutterMode === "function") {
                        shellTarget.toggleShutterMode();
                    }
                }
                
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            ProfileCard { schemeId: "scheme-tonal-spot"; schemeLabel: "Tonal Spot" }
            ProfileCard { schemeId: "scheme-expressive"; schemeLabel: "Expressive" }
            ProfileCard { schemeId: "scheme-fruit-salad"; schemeLabel: "Fruit Salad" }
            ProfileCard { schemeId: "scheme-rainbow"; schemeLabel: "Rainbow" }
            ProfileCard { schemeId: "scheme-neutral"; schemeLabel: "Neutral" }
            ProfileCard { schemeId: "scheme-monochrome"; schemeLabel: "Monochrome" }
        }
    }
}
