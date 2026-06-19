import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: colorsLayoutRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    Grid {
        anchors.fill: parent
        anchors.margins: 10
        columns: 2
        spacing: 12

        component ProfileCard : Button {
            id: cardBtn
            property string schemeId: ""
            property string schemeLabel: ""
            
            width: (parent.width - 12) / 2
            height: 60
            flat: true

            background: Rectangle {
                color: settingsWindow.matugenScheme === schemeId 
                    ? settingsModuleRoot.themeBorder 
                    : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                
                border.color: settingsWindow.matugenScheme === schemeId 
                    ? settingsModuleRoot.themeAccent 
                    : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                border.width: 0
                radius: 8
            }

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "palette"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    color: settingsWindow.matugenScheme === schemeId ? settingsModuleRoot.themeAccent : settingsModuleRoot.themeText
                }

                Text {
                    Layout.fillWidth: true
                    text: schemeLabel
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 14
                    font.bold: true
                    color: settingsModuleRoot.themeText
                    verticalAlignment: Text.AlignVCenter
                }
            }

            onClicked: {
                settingsWindow.matugenScheme = schemeId;
                settingsWindow.pushUpdate();
                
                // 🎯 The Link: Force wallpaper window to regenerate colors instantly
                if (shellTarget && shellTarget.wallpaperRef) {
                    shellTarget.wallpaperRef.triggerMatugen(null, schemeId);
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
