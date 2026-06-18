import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: calendarRoot

    property string namespace: "quickshell-calendar-popup"

    // Trigger this from your Bar's Clock component
    property bool active: false
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real maxCardHeight: 370 // 🎯 Adjusted default height since the weather card is gone

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)

    x: rootShell.barPosition === "right" ? hoverOriginX + (maxCardWidth - width - 2) : hoverOriginX
    y: rootShell.barPosition === "bottom" ? hoverOriginY + (maxCardHeight - height) : hoverOriginY

    // --- State Properties ---
    property date currentDateTime: new Date()
    readonly property date baseDate: new Date()
    property int currentMonthOffsetIndex: 50
    property date viewerTargetDate: new Date()

    // --- Timers & Logic ---
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: calendarRoot.currentDateTime = new Date()
    }

    function updateViewerDate() {
        let monthOffset = calendarRoot.currentMonthOffsetIndex - 50;
        calendarRoot.viewerTargetDate = new Date(calendarRoot.baseDate.getFullYear(), calendarRoot.baseDate.getMonth() + monthOffset, 1);
    }

    onActiveChanged: {
        if (active) {
            currentMonthOffsetIndex = 50;
            updateViewerDate();
        }
    }

    // --- Visuals & Animations ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.TopLeft
            if (rootShell.barPosition === "right") return Item.TopRight
            if (rootShell.barPosition === "top") return Item.TopLeft
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        // --- Streamlined Fluid Behavior Hooks ---
        opacity: calendarRoot.active ? 1.0 : 0.0
        scale: calendarRoot.active ? 1.0 : 0.0
        x: calendarRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: calendarRoot.active ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            color: rootShell.colorBackground
            z: 2
            
            border.width: 0
            border.color: "transparent"

            topLeftRadius: 0
            topRightRadius: rootShell.barPosition === "bottom" ? calendarRoot.radiusValue : 0
            bottomLeftRadius: rootShell.barPosition === "right" ? calendarRoot.radiusValue : 0
            bottomRightRadius: (rootShell.barPosition === "top" || rootShell.barPosition === "left") ? calendarRoot.radiusValue : 0
        }

        // --- Wings Component ---
        Item {
            anchors.fill: parent
            visible: calendarRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                Shape {
                    x: 0; y: parent.height
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: calendarRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: calendarRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: 0; y: calendarRoot.wingSize }
                        PathQuad { x: calendarRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"

                Shape {
                    x: 0; y: parent.height
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: calendarRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: calendarRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: 0; y: calendarRoot.wingSize }
                        PathQuad { x: calendarRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"

                Shape {
                    x: 0; y: -calendarRoot.wingSize
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: calendarRoot.wingSize
                        PathLine { x: calendarRoot.wingSize; y: calendarRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: calendarRoot.wingSize }
                        PathLine { x: 0; y: calendarRoot.wingSize }
                    }
                }
                Shape {
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    x: parent.width
                    y: parent.height
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: calendarRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: calendarRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: -calendarRoot.wingSize; y: 0
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: calendarRoot.wingSize; startY: 0
                        PathLine { x: calendarRoot.wingSize; y: calendarRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: calendarRoot.wingSize; controlY: 0 }
                        PathLine { x: calendarRoot.wingSize; y: 0 }
                    }
                }
                
                Shape {
                    x: parent.width - calendarRoot.wingSize; y: parent.height
                    width: calendarRoot.wingSize; height: calendarRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: calendarRoot.wingSize; startY: 0
                        PathLine { x: calendarRoot.wingSize; y: calendarRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: calendarRoot.wingSize; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        // --- Internal Content ---
        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 18
            z: 5

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // Month/Year Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    
                    // Left Arrow
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: prevMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                        Text { 
                            anchors.centerIn: parent; text: "chevron_left"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 18
                            color: rootShell.colorAccent
                        }
                        MouseArea { 
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { 
                                if (calendarRoot.currentMonthOffsetIndex > 0) { 
                                    calendarRoot.currentMonthOffsetIndex--; 
                                    calendarRoot.updateViewerDate(); 
                                } 
                            } 
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                    Text { 
                        text: Qt.formatDateTime(calendarRoot.viewerTargetDate, "MMMM yyyy")
                        font.family: rootShell.shellFont; font.pixelSize: 16; font.weight: Font.Bold
                        color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: nextMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                        Text { 
                            anchors.centerIn: parent; text: "chevron_right"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 18
                            color: rootShell.colorAccent
                        }
                        MouseArea { 
                            id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (calendarRoot.currentMonthOffsetIndex < 100) { calendarRoot.currentMonthOffsetIndex++; calendarRoot.updateViewerDate(); } } 
                        }
                    }
                }

                // The Calendar Grid
                StackLayout {
                    id: calendarDisplayStack
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: calendarRoot.currentMonthOffsetIndex
                    
                    Repeater {
                        model: 101
                        delegate: Item {
                            readonly property int currentVirtualOffset: index - 50
                            readonly property int resolvedMonthPosition: calendarRoot.baseDate.getMonth() + currentVirtualOffset
                            readonly property date loopCalculatedDate: new Date(calendarRoot.baseDate.getFullYear(), resolvedMonthPosition, 1)

                            MonthGrid {
                                id: grid
                                anchors.fill: parent
                                month: parent.loopCalculatedDate.getMonth()
                                year: parent.loopCalculatedDate.getFullYear()
                                font.family: rootShell.shellFont; font.pixelSize: 13
                                
                                delegate: Item {
                                    implicitWidth: 36; implicitHeight: 36
                                    readonly property bool isToday: model.day === calendarRoot.currentDateTime.getDate() && model.month === calendarRoot.currentDateTime.getMonth() && model.year === calendarRoot.currentDateTime.getFullYear()
                                    
                                    Rectangle { 
                                        anchors.fill: parent; anchors.margins: 2; radius: 6
                                        color: parent.isToday ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.2) : "transparent"
                                        border.width: parent.isToday ? 1 : 0
                                        border.color: rootShell.colorAccent
                                    }
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        opacity: model.month === grid.month ? 1.0 : 0.3
                                        text: model.day
                                        color: parent.isToday ? rootShell.colorAccent : "#ffffff"
                                        font.family: grid.font.family; font.pixelSize: grid.font.pixelSize
                                        font.weight: parent.isToday ? Font.Bold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
