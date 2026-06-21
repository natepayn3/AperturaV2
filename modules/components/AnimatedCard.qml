import QtQuick
import QtQuick.Shapes

Item {
    id: cardRoot

    // 🎯 Use primitive values directly to bypass QML object-binding failures
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
        anchors.margins: -1
        color: cardRoot.backgroundColor
        z: 2
        
        // 🎯 Force a physical pixel bleed on the main body
        border.width: 1
        border.color: cardRoot.backgroundColor

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
        anchors.margins: -1
        visible: cardRoot.width > 30
        z: 2 

        property real wingShift: Math.max(0, cardRoot.wingSize * (1 - (cardRoot.scale * 4)))
        x: (barPosition === "left") ? -wingShift : (barPosition === "right" ? wingShift : 0)
        y: (barPosition === "top") ? -wingShift : (barPosition === "bottom" ? wingShift : 0)

        Item {
            anchors.fill: parent
            visible: barPosition === "left"
            Shape { x: 0; y: -cardRoot.wingSize; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: 0; startY: cardRoot.wingSize; PathLine { x: cardRoot.wingSize; y: cardRoot.wingSize } PathQuad { x: 0; y: 0; controlX: 0; controlY: cardRoot.wingSize } PathLine { x: 0; y: cardRoot.wingSize } } }
            Shape { rotation: -90; transformOrigin: Item.TopLeft; x: parent.width; y: parent.height; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: 0; startY: 0; PathLine { x: cardRoot.wingSize; y: 0 } PathQuad { x: 0; y: cardRoot.wingSize; controlX: 0; controlY: 0 } PathLine { x: 0; y: 0 } } }
        }

        Item {
            anchors.fill: parent
            visible: barPosition === "right"
            Shape { x: parent.width - cardRoot.wingSize; y: -cardRoot.wingSize; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: cardRoot.wingSize; startY: cardRoot.wingSize; PathLine { x: 0; y: cardRoot.wingSize } PathQuad { x: cardRoot.wingSize; y: 0; controlX: cardRoot.wingSize; controlY: cardRoot.wingSize } PathLine { x: cardRoot.wingSize; y: cardRoot.wingSize } } }
            Shape { rotation: 90; transformOrigin: Item.TopRight; x: 0 - cardRoot.wingSize; y: parent.height; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: cardRoot.wingSize; startY: 0; PathLine { x: 0; y: 0 } PathQuad { x: cardRoot.wingSize; y: cardRoot.wingSize; controlX: cardRoot.wingSize; controlY: 0 } PathLine { x: cardRoot.wingSize; y: 0 } } }
        }

        Item {
            anchors.fill: parent
            visible: barPosition === "top"
            Shape { x: -cardRoot.wingSize; y: 0; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: cardRoot.wingSize; startY: 0; PathLine { x: cardRoot.wingSize; y: cardRoot.wingSize } PathQuad { x: 0; y: 0; controlX: cardRoot.wingSize; controlY: 0 } PathLine { x: cardRoot.wingSize; y: 0 } } }
            Shape { x: parent.width - cardRoot.wingSize; y: parent.height; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: cardRoot.wingSize; startY: 0; PathLine { x: cardRoot.wingSize; y: cardRoot.wingSize } PathQuad { x: 0; y: 0; controlX: cardRoot.wingSize; controlY: 0 } PathLine { x: 0; y: 0 } } }
        }

        Item {
            anchors.fill: parent
            visible: barPosition === "bottom" 
            Shape { x: parent.width - cardRoot.wingSize; y: -cardRoot.wingSize; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: cardRoot.wingSize; startY: cardRoot.wingSize; PathLine { x: 0; y: cardRoot.wingSize } PathQuad { x: cardRoot.wingSize; y: 0; controlX: cardRoot.wingSize; controlY: cardRoot.wingSize } PathLine { x: cardRoot.wingSize; y: cardRoot.wingSize } } }
            Shape { rotation: 180; transformOrigin: Item.TopLeft; x: 0; y: parent.height; width: cardRoot.wingSize; height: cardRoot.wingSize; ShapePath { fillColor: cardRoot.backgroundColor; strokeColor: "transparent"; strokeWidth: 0; startX: 0; startY: 0; PathLine { x: cardRoot.wingSize; y: 0 } PathQuad { x: 0; y: cardRoot.wingSize; controlX: 0; controlY: 0 } PathLine { x: 0; y: 0 } } }
        }
    }

    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

    Item {
        id: innerContent
        anchors.fill: parent
        z: 5
    }
}
