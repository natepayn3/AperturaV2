import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: fontModuleRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"
    property color themeSubtext: "transparent"

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        TextField {
            id: fontSearchBar
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            placeholderText: "Search fonts..."
            font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
            font.pixelSize: 15
            color: shellTarget ? shellTarget.colorText : "#cdd6f4"
            placeholderTextColor: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
            focus: settingsWindow ? settingsWindow.activeCategory === "Font" : false
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            
            background: Rectangle {
                color: "transparent"
                border.color: fontSearchBar.activeFocus ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorBorder : "#313244")
                border.width: 2
                radius: 8
            }

            onTextChanged: {
                if (settingsWindow) {
                    settingsWindow.fontSearchQuery = text.trim().toLowerCase();
                }
                fontListView.currentIndex = 0;
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Down) {
                    fontListView.incrementCurrentIndex();
                    if (fontListView.currentItem) fontListView.currentItem.triggerSelection();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    fontListView.decrementCurrentIndex();
                    if (fontListView.currentItem) fontListView.currentItem.triggerSelection();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (fontListView.currentItem) {
                        fontListView.currentItem.triggerSelection();
                    }
                    event.accepted = true;
                }
            }
        }

        // --- Font Example Preview Area ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 66
            
            color: Qt.rgba(0, 0, 0, 0.15)
            border.color: shellTarget ? shellTarget.colorBorder : "#313244"
            border.width: 1
            radius: 12

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 2 

                Text {
                    text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"
                    font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
                    font.pixelSize: 14
                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    elide: Text.ElideRight
                    Layout.fillWidth: true 
                }

                Text {
                    text: "0123456789 !@#$%^&*()_+-=[]{}|;':\",./<>?"
                    font.family: settingsWindow ? settingsWindow.selectedFont : "Rubik"
                    font.pixelSize: 13
                    color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: fontListView
                spacing: 4
                keyNavigationEnabled: false
                
                model: {
                    let allFonts = Qt.fontFamilies();
                    if (!settingsWindow || settingsWindow.fontSearchQuery === "") return allFonts;
                    return allFonts.filter(f => f.toLowerCase().includes(settingsWindow.fontSearchQuery));
                }

                function syncActiveIndex() {
                    if (!settingsWindow) return;
                    let currentModel = model;
                    let targetFont = settingsWindow.selectedFont;
                    let targetIdx = currentModel.indexOf(targetFont);
                    
                    if (targetIdx !== -1) {
                        fontListView.currentIndex = targetIdx;
                    }
                }

                Component.onCompleted: syncActiveIndex()
                onModelChanged: syncActiveIndex()
                
                Connections {
                    target: settingsWindow
                    ignoreUnknownSignals: true
                    function onSelectedFontChanged() { fontListView.syncActiveIndex(); }
                }
                
                delegate: ItemDelegate {
                    id: fontDelegate
                    width: fontListView.width
                    height: 38
                    highlighted: fontListView.currentIndex === index || (settingsWindow && settingsWindow.selectedFont === modelData)
                    
                    function triggerSelection() {
                        if (settingsWindow) {
                            settingsWindow.selectedFont = modelData;
                            settingsWindow.pushUpdate();
                        }
                        if (shellTarget && shellTarget.shellFont !== undefined) {
                            shellTarget.shellFont = modelData;
                        }
                    }

                    // 🎯 FIX: Styled with the exact same hover/active micro-interactions from ColorsLayout
                    background: Rectangle {
                        color: fontDelegate.highlighted
                            ? (shellTarget ? Qt.rgba(shellTarget.colorBorder.r, shellTarget.colorBorder.g, shellTarget.colorBorder.b, 0.15) : Qt.rgba(1, 1, 1, 0.08)) 
                            : (fontDelegate.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                        
                        border.color: fontDelegate.highlighted
                            ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                            : (fontDelegate.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                        
                        border.width: fontDelegate.highlighted ? 2 : 1
                        radius: 8
                    }

                    contentItem: Text {
                        text: modelData
                        font.family: modelData
                        font.pixelSize: 16
                        color: settingsWindow && settingsWindow.selectedFont === modelData 
                            ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                            : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                        verticalAlignment: Text.AlignVCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                    }

                    onClicked: {
                        fontListView.currentIndex = index;
                        triggerSelection();
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }
}
