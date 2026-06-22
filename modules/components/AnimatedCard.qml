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

    // 🎯 Use Math.round to force integer alignment with the Wayland compositor
    width: Math.round(targetWidth)
    height: Math.round(targetHeight)

    transformOrigin: {
        if (barPosition === "left") return Item.BottomLeft
        if (barPosition === "right") return Item.BottomRight
        if (barPosition === "top") return Item.TopRight
        if (barPosition === "bottom") return Item.BottomRight
        return Item.Center
    }

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
        anchors.fill: parent
        anchors.margins: -1 // 🦇 THE FIX: Bleeds the main body past the fractional Wayland edge
        color: cardRoot.backgroundColor
        z: 2
        
        topLeftRadius:     getCornerRadius("topLeft")
        topRightRadius:    getCornerRadius("topRight")
        bottomLeftRadius:  getCornerRadius("bottomLeft")
        bottomRightRadius: getCornerRadius("bottomRight")

        function getCornerRadius(corner) {
            if (barPosition === "top") return (corner === "bottomLeft") ? radiusValue : 0;
            if (barPosition === "bottom") return (corner === "topLeft") ? radiusValue : 0;
            if (barPosition === "left") return (corner === "topRight") ? radiusValue : 0;
            if (barPosition === "right") return (corner === "topLeft") ? radiusValue : 0;
            return radiusValue;
        }
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

            // --- Bottom-Left Wing ---
            Item {
                // Position the clipping container at the bottom-left of your main card
                x: parent.width; y: parent.height - cardRoot.wingSize
                width: cardRoot.wingSize; height: cardRoot.wingSize; clip: true

                Rectangle {
                    // The circle is larger than the clip area; shift it to show only the corner arc
                    width: cardRoot.wingSize * 6; height: cardRoot.wingSize * 6
                    radius: cardRoot.wingSize * 3
                    color: "transparent"
                    border.color: cardRoot.backgroundColor
                    border.width: cardRoot.wingSize * 2
                    
                    // Offset to align the circle's border with the corner
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
