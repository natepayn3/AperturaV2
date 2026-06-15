import QtQuick
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: frameWindowItem
    
    property var rootShell: null
    property var targetScreen: null
    property int parentIndex: 0
    
    screen: targetScreen
    WlrLayershell.namespace: "quickshell-frame"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: WlrLayershell.Ignore
    color: Qt.rgba(0, 0, 0, 0)
    mask: Region {}
    
    anchors { 
        left: rootShell.barPosition !== "left" || !rootShell.isDisplayEnabled(parentIndex)
        right: rootShell.barPosition !== "right" || !rootShell.isDisplayEnabled(parentIndex)
        top: rootShell.barPosition !== "top" || !rootShell.isDisplayEnabled(parentIndex)
        bottom: rootShell.barPosition !== "bottom" || !rootShell.isDisplayEnabled(parentIndex) 
    }
    
    property real currentMargin: rootShell.activeLayoutOrientation === "vertical" ? (36.0 * rootShell.verticalFrameProgress) : (36.0 * rootShell.horizontalFrameProgress)
    
    implicitWidth: rootShell.barPosition === "left" || rootShell.barPosition === "right" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.width - currentMargin : 0) : (screen ? screen.width : 0)) : (screen ? screen.width : 0)
    implicitHeight: rootShell.barPosition === "top" || rootShell.barPosition === "bottom" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.height - currentMargin : 0) : (screen ? screen.height : 0)) : (screen ? screen.height : 0)

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        ShapePath {
            fillColor: rootShell.colorBackground
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            PathMove { x: 0; y: 0 }
            PathLine { x: frameWindowItem.width; y: 0 }
            PathLine { x: frameWindowItem.width; y: frameWindowItem.height }
            PathLine { x: 0; y: frameWindowItem.height }
            PathLine { x: 0; y: 0 }
            PathMove { x: 8 + borderFrameLine.radius; y: 8 }
            PathLine { x: frameWindowItem.width - 8 - borderFrameLine.radius; y: 8 }
            PathArc { x: frameWindowItem.width - 8; y: 8 + borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
            PathLine { x: frameWindowItem.width - 8; y: frameWindowItem.height - 8 - borderFrameLine.radius }
            PathArc { x: frameWindowItem.width - 8 - borderFrameLine.radius; y: frameWindowItem.height - 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
            PathLine { x: 8 + borderFrameLine.radius; y: frameWindowItem.height - 8 }
            PathArc { x: 8; y: frameWindowItem.height - 8 - borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
            PathLine { x: 8; y: 8 + borderFrameLine.radius }
            PathArc { x: 8 + borderFrameLine.radius; y: 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
        }
    }
    Rectangle { 
        id: borderFrameLine; x: 8; y: 8; width: parent.width - 16; height: parent.height - 16; 
        color: "transparent"; border.color: rootShell.colorBackground; border.width: 2; radius: 16 
    }
}
