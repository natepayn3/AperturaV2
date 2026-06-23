import QtQuick

Item {
    id: cardRoot

    property string barPosition: "bottom"
    property color backgroundColor: "transparent"
    
    property bool active: false
    property real targetWidth: parent.width
    property real targetHeight: parent.height
    
    property real radiusValue: 12
    property real wingSize: 14

    property alias isHovered: hoverArea.containsMouse
    default property alias content: innerContent.data

    width: targetWidth
    height: targetHeight

    // 🛠️ FIXED: Converted statement block into a declarative ternary chain to fix the engine crash
    transformOrigin: barPosition === "left" ? Item.BottomLeft :
                     barPosition === "right" ? Item.BottomRight :
                     barPosition === "top" ? Item.TopRight :
                     barPosition === "bottom" ? Item.BottomRight : Item.Center

    opacity: cardRoot.active ? 1.0 : 0.0
    scale: cardRoot.active ? 1.0 : 0.0
    x: cardRoot.active ? 0 : (barPosition === "right" ? 40 : -40)
    y: cardRoot.active ? 0 : (barPosition === "top" ? -40 : 40)
    
    visible: opacity > 0.01

    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

    Rectangle {
        id: cardBody
        anchors.fill: parent
        color: cardRoot.backgroundColor
        z: 2

        layer.enabled: true
        layer.samples: 4
        
        // 🎯 The Anti-Aliasing Buffer: 
        // Forces edge blending to use your background color instead of transparent black
        border.width: 1
        border.color: Qt.rgba(cardRoot.backgroundColor.r, cardRoot.backgroundColor.g, cardRoot.backgroundColor.b, 0.0)
        topLeftRadius:     (barPosition === "right" || barPosition === "bottom") ? Math.round(radiusValue) : 0
        topRightRadius:    (barPosition === "left") ? Math.round(radiusValue) : 0
        bottomLeftRadius:  (barPosition === "top") ? Math.round(radiusValue) : 0
        bottomRightRadius: 0
    }

    Item {
        anchors.fill: parent
        visible: cardRoot.width > 30
        z: 3 

        property real wingShift: Math.max(0, cardRoot.wingSize * (1 - (cardRoot.scale * 4)))
        x: (barPosition === "left") ? -wingShift : (barPosition === "right" ? wingShift : 0)
        y: (barPosition === "top") ? -wingShift : (barPosition === "bottom" ? wingShift : 0)

        // --- Left Bar Wings ---
        Item {
            anchors.fill: parent
            visible: barPosition === "left"

            Item { 
                x: 0; y: -cardRoot.wingSize
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 2); y: -(cardRoot.wingSize * 3)
                }
            }

            // --- Bottom-Right Wing ---
            Item {
                x: parent.width; y: parent.height - cardRoot.wingSize
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true

                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6
                    radius: cardRoot.wingSize * 3
                    color: "transparent"
                    border.color: cardRoot.backgroundColor
                    border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 2); y: -(cardRoot.wingSize * 3)
                }
            }
        }

        // --- Right Bar Wings ---
        Item {
            anchors.fill: parent
            visible: barPosition === "right"

            Item { 
                x: parent.width - cardRoot.wingSize; y: -cardRoot.wingSize
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 3); y: -(cardRoot.wingSize * 3)
                }
            }

            Item { 
                rotation: 90; transformOrigin: Item.TopRight
                x: 0 - cardRoot.wingSize; y: parent.height
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 3); y: -(cardRoot.wingSize * 2)
                }
            }
        }

        // --- Top Bar Wings ---
        Item {
            anchors.fill: parent
            visible: barPosition === "top"
            
            Item { 
                x: -cardRoot.wingSize; y: 0
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 3); y: -(cardRoot.wingSize * 2)
                }
            }
            
            Item { 
                x: parent.width - cardRoot.wingSize; y: parent.height
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 3); y: -(cardRoot.wingSize * 2)
                }
            }
        }

        // --- Bottom Bar Wings ---
        Item {
            anchors.fill: parent
            visible: barPosition === "bottom"

            Item { 
                x: parent.width - cardRoot.wingSize; y: -cardRoot.wingSize
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 3); y: -(cardRoot.wingSize * 3)
                }
            }

            Item { 
                rotation: 180; transformOrigin: Item.TopLeft
                x: 0; y: parent.height
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true
                Rectangle {
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6; radius: cardRoot.wingSize * 3
                    color: "transparent"; border.color: cardRoot.backgroundColor; border.width: cardRoot.wingSize * 2
                    x: -(cardRoot.wingSize * 2); y: -(cardRoot.wingSize * 2)
                }
            }
        }
    }

    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

    Item {
        id: innerContent
        anchors.fill: parent
        z: 5
    }
}
