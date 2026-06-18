import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: sliderRoot
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    property string iconLow: ""
    property string iconHigh: ""
    property real value: 0.0
    property bool isPressed: slider.pressed

    signal moved(real newValue)

    Slider {
        id: slider
        anchors.fill: parent
        value: sliderRoot.value
        onMoved: sliderRoot.moved(value)

        background: Rectangle {
            color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); radius: 24
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; color: rootShell.colorText; radius: 24 }
            
            RowLayout {
                anchors.fill: parent; anchors.margins: 16
                Text { text: sliderRoot.iconLow; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                Item { Layout.fillWidth: true }
                Text { 
                    text: sliderRoot.iconHigh === "" ? Math.round(slider.value * 100) + "%" : sliderRoot.iconHigh
                    font.family: sliderRoot.iconHigh === "" ? rootShell.shellFont : "Material Symbols Outlined"
                    font.bold: sliderRoot.iconHigh === ""
                    color: sliderRoot.iconHigh === "" ? rootShell.colorBackground : rootShell.colorSubtext
                    font.pixelSize: sliderRoot.iconHigh === "" ? 12 : 20
                    Layout.alignment: Qt.AlignVCenter
                    transform: Translate { y: sliderRoot.iconHigh === "" ? 0 : -3 } 
                }
            }
            
            // Large center readout when sliding (optional for volume style)
            Text { 
                text: Math.round(slider.value * 100) + "%"
                color: rootShell.colorBackground; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 14
                anchors.centerIn: parent
                opacity: (sliderRoot.iconHigh !== "" && slider.pressed) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }
        handle: Item {} 
    }
}
