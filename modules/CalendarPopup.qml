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
    
    // Unified Hover Logic: Hooks into both background and structural inner content
    property bool isHovered: popupHoverArea.containsMouse || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real maxCardHeight: 440

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)
    opacity: 1.0
    visible: true
    clip: false

    x: rootShell.barPosition === "right" ? hoverOriginX + (maxCardWidth - width) : hoverOriginX
    y: rootShell.barPosition === "bottom" ? hoverOriginY + (maxCardHeight - height) : hoverOriginY

    // --- State Properties ---
    property date currentDateTime: new Date()
    readonly property date baseDate: new Date()
    property int currentMonthOffsetIndex: 50
    property date viewerTargetDate: new Date()

    property string weatherLocationOverride: ""
    property string weatherTemp: "--"
    property string weatherFeelsLike: "--"
    property string weatherDesc: "Loading..."
    property string weatherGlyph: "cloud"

    readonly property var weatherIconMap: {
        "0": "clear_day", "1": "partly_cloudy_day", "2": "partly_cloudy_day", "3": "cloudy",
        "45": "foggy", "48": "foggy", "51": "rainy", "53": "rainy", "55": "rainy", "61": "rainy",
        "63": "rainy", "65": "rainy", "71": "snowing", "73": "snowing", "75": "snowing",
        "77": "snowing", "80": "rainy", "81": "rainy", "82": "rainy", "85": "snowing",
        "86": "snowing", "95": "thunderstorm", "96": "thunderstorm", "99": "thunderstorm"
    }

    readonly property var weatherDescMap: {
        "0": "Clear Sky", "1": "Mainly Clear", "2": "Partly Cloudy", "3": "Overcast",
        "45": "Foggy", "48": "Rime Fog", "51": "Light Drizzle", "53": "Moderate Drizzle",
        "55": "Dense Drizzle", "61": "Slight Rain", "63": "Moderate Rain", "65": "Heavy Rain",
        "71": "Light Snow", "73": "Moderate Snow", "75": "Heavy Snow", "77": "Snow Grains",
        "80": "Light Showers", "81": "Moderate Showers", "82": "Heavy Showers",
        "85": "Light Snow Showers", "86": "Heavy Snow Showers", "95": "Thunderstorm",
        "96": "Storm w/ Hail", "99": "Severe Storm"
    }

    // --- Timers & Logic ---
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: calendarRoot.currentDateTime = new Date()
    }

    Timer {
        id: weatherTimer
        interval: 900000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: weatherFetcher.running = true
    }

    Process {
        id: weatherFetcher
        command: ["curl", "-s", "https://wttr.is/" + calendarRoot.weatherLocationOverride.trim() + "?format=j1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    let current = data.current_condition[0];
                    calendarRoot.weatherTemp = current.temp_F + "°F";
                    calendarRoot.weatherFeelsLike = current.FeelsLikeF + "°F";
                    let code = current.weatherCode.toString();
                    calendarRoot.weatherDesc = calendarRoot.weatherDescMap[code] !== undefined ? calendarRoot.weatherDescMap[code] : current.weatherDesc[0].value;
                    calendarRoot.weatherGlyph = calendarRoot.weatherIconMap[code] !== undefined ? calendarRoot.weatherIconMap[code] : "cloud";
                } catch (e) {}
                weatherFetcher.running = false;
            }
        }
    }

    function updateViewerDate() {
        let monthOffset = calendarRoot.currentMonthOffsetIndex - 50;
        calendarRoot.viewerTargetDate = new Date(calendarRoot.baseDate.getFullYear(), calendarRoot.baseDate.getMonth() + monthOffset, 1);
    }

    onActiveChanged: {
        if (active) {
            currentMonthOffsetIndex = 50;
            updateViewerDate();
            if (weatherTemp === "--") weatherFetcher.running = true;
        }
    }

    // --- Visuals & Animations ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        // Multi-axis anchors to pinpoint the actual screen corners for a diagonal expansion pivot
        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft
            if (rootShell.barPosition === "right") return Item.BottomRight
            if (rootShell.barPosition === "top") return Item.TopRight
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        states: [
            State {
                name: "hidden"
                when: !calendarRoot.active
                PropertyChanges { target: animatedGroup; opacity: 0.0; scale: 0.0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 0.0 }
                
                // Fixed: Explicit multi-axis translations to dictate diagonal slide out vectors
                PropertyChanges { 
                    target: animatedGroup
                    x: rootShell.barPosition === "right" ? 60 : -60
                    y: rootShell.barPosition === "bottom" ? 60 : -60
                }
            },
            State {
                name: "shown"
                when: calendarRoot.active
                PropertyChanges { target: animatedGroup; opacity: 1.0; scale: 1.0; x: 0; y: 0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 1.0 }
            }
        ]

        transitions: [
            Transition {
                from: "hidden"; to: "shown"
                ParallelAnimation {
                    // Restored full Spring Bounce values from WorkspacePreview
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 200 } 
                        NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 200; easing.type: Easing.InQuad }
                    }
                }
            },
            Transition {
                from: "shown"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 100 }
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                }
            }
        ]

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

        // Structural background hover area
        MouseArea { 
            id: popupHoverArea
            anchors.fill: parent 
            hoverEnabled: true 
            z: 1
        }

        // --- Internal Content ---
        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 18
            z: 5

            // Passive tracker captures cross-hierarchy hover changes cleanly
            HoverHandler {
                id: contentHoverHandler
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // Month/Year Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: prevMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                        Text { 
                            anchors.centerIn: parent; text: "chevron_left"
                            font.family: "Material Symbols Outlined"; font.pixelSize: 18
                            color: rootShell.colorAccent
                        }
                        MouseArea { 
                            id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (calendarRoot.currentMonthOffsetIndex > 0) { calendarRoot.currentMonthOffsetIndex--; calendarRoot.updateViewerDate(); } } 
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

                // Divider
                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255,255,255,0.1)
                }

                // Weather Footer
                Item {
                    id: weatherCardSurface
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56

                    RowLayout {
                        anchors.fill: parent; spacing: 14

                        Text {
                            text: calendarRoot.weatherGlyph
                            font.family: "Material Symbols Outlined"; font.pixelSize: 32
                            color: rootShell.colorAccent
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true

                            Text {
                                text: calendarRoot.weatherDesc
                                font.family: rootShell.shellFont; font.pixelSize: 14; font.weight: Font.Bold
                                color: "#ffffff"
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "Feels like " + calendarRoot.weatherFeelsLike
                                font.family: rootShell.shellFont; font.pixelSize: 12
                                color: "#ffffff"; opacity: 0.6
                            }
                        }

                        Text {
                            text: calendarRoot.weatherTemp
                            font.family: rootShell.shellFont; font.pixelSize: 22; font.weight: Font.Bold
                            color: "#ffffff"
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
