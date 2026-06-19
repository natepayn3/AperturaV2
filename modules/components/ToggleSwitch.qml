import QtQuick

Rectangle {
    id: toggleRoot
    width: 156; height: 56; radius: 28

    property string label: ""
    property string iconName: ""
    property bool checked: false
    property bool isAvailable: true

    signal toggled()

    color: checked ? rootShell.colorText : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
    opacity: isAvailable ? 1.0 : 0.5

    Text {
        text: toggleRoot.label
        font.family: rootShell.shellFont
        font.pixelSize: 13
        font.bold: true
        color: toggleRoot.checked ? rootShell.colorBackground : rootShell.colorText
        anchors.verticalCenter: parent.verticalCenter
        
        // Use fixed points to stop the animation from "chasing" a moving target
        x: toggleRoot.checked ? 16 : 60
        width: 80 
        
        horizontalAlignment: toggleRoot.checked ? Text.AlignLeft : Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        
        // Sync duration exactly with the knob's 200ms animation
        Behavior on x {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
        Behavior on color {
            ColorAnimation { duration: 200 }
        }
    }

    Rectangle {
        id: knob
        width: 48; height: 48; radius: 24
        color: toggleRoot.checked ? rootShell.colorBackground : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
        anchors.verticalCenter: parent.verticalCenter
        x: toggleRoot.checked ? parent.width - width - 4 : 4

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        Text {
            anchors.centerIn: parent
            text: toggleRoot.iconName
            font.family: "Material Symbols Outlined"
            color: toggleRoot.checked ? rootShell.colorText : rootShell.colorSubtext
            font.pixelSize: 22
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: toggleRoot.isAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (toggleRoot.isAvailable) toggleRoot.toggled()
    }
}
