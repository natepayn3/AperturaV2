import QtQuick
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: frameWindowItem
    property real scaleFactor: rootShell.scale || 1.0

    function snap(value) {
        return Math.round(value * scaleFactor) / scaleFactor
    }
    
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
    
    property real currentMargin: Math.ceil(rootShell.activeLayoutOrientation === "vertical" ? 
        (36.0 * rootShell.verticalFrameProgress) : (36.0 * rootShell.horizontalFrameProgress))
    
    implicitWidth: snap(rootShell.barPosition === "left" || rootShell.barPosition === "right" ? 
        (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.width - currentMargin : 0) : (screen ? screen.width : 0)) : (screen ? screen.width : 0))
    implicitHeight: snap(rootShell.barPosition === "top" || rootShell.barPosition === "bottom" ? 
        (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.height - currentMargin : 0) : (screen ? screen.height : 0)) : (screen ? screen.height : 0))
        
    // 🎯 Unified Source of Truth
    property real baseOuterMargin: snap(8)
    property real baseRadius: snap(16)
    property real gapOverlap: snap(1)
    
    property real shapeW: snap(frameWindowItem.width)
    property real shapeH: snap(frameWindowItem.height)
    property real shapeHm: baseOuterMargin + gapOverlap 
    property real shapeHr: Math.max(0, baseRadius - gapOverlap)
    
    // 🎯 Extract Color and Alpha for Layer Flattening
    property color bgColor: rootShell.colorBackground
    // Create a 100% solid version of the background color
    property color solidBgColor: Qt.rgba(bgColor.r, bgColor.g, bgColor.b, 1.0)

    // Wrap both geometries to flatten them into a single unified texture
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        // Apply the transparency to the combined flattened result!
        opacity: bgColor.a 
        
        Shape {
            anchors.fill: parent
            // layer.enabled is moved to the parent Item
            
            ShapePath {
                // Use the 100% solid color
                fillColor: solidBgColor
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                
                // Outer Bounds
                PathMove { x: 0; y: 0 }
                PathLine { x: shapeW; y: 0 }
                PathLine { x: shapeW; y: shapeH }
                PathLine { x: 0; y: shapeH }
                PathLine { x: 0; y: 0 }
                
                // Inner Cutout
                PathMove { x: shapeHm + shapeHr; y: shapeHm }
                PathLine { x: shapeW - shapeHm - shapeHr; y: shapeHm }
                PathArc { x: shapeW - shapeHm; y: shapeHm + shapeHr; radiusX: shapeHr; radiusY: shapeHr }
                PathLine { x: shapeW - shapeHm; y: shapeH - shapeHm - shapeHr }
                PathArc { x: shapeW - shapeHm - shapeHr; y: shapeH - shapeHm; radiusX: shapeHr; radiusY: shapeHr }
                PathLine { x: shapeHm + shapeHr; y: shapeH - shapeHm }
                PathArc { x: shapeHm; y: shapeH - shapeHm - shapeHr; radiusX: shapeHr; radiusY: shapeHr }
                PathLine { x: shapeHm; y: shapeHm + shapeHr }
                PathArc { x: shapeHm + shapeHr; y: shapeHm; radiusX: shapeHr; radiusY: shapeHr }
            }
        }
        
        Rectangle { 
            id: borderFrameLine
            x: baseOuterMargin; y: baseOuterMargin
            width: snap(parent.width - (baseOuterMargin * 2)) 
            height: snap(parent.height - (baseOuterMargin * 2)) 
            color: "transparent" 
            // Use the 100% solid color
            border.color: solidBgColor 
            border.width: snap(2)
            radius: baseRadius
            antialiasing: true 
        }
    }
}
