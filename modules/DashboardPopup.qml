import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Notifications

Item {
    id: dashboardRoot

    property bool active: false
    property bool isHovered: dashHover.hovered || bridgeHover.hovered

    property real radiusValue: 24
    property real wingSize: 14

    property real maxCardWidth: 380
    property real maxCardHeight: 780

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)

    anchors.verticalCenter: parent.verticalCenter
    anchors.left: rootShell.barPosition === "left" ? parent.left : undefined
    anchors.right: rootShell.barPosition === "right" ? parent.right : undefined
    anchors.leftMargin: rootShell.barPosition === "left" ? 46 : 0
    anchors.rightMargin: rootShell.barPosition === "right" ? 46 : 0

    // --- Live Data Tracking ---
    property real sysCpu: 0.0
    property real sysGpu: 0.0
    property real sysRam: 0.0

    property real currentVolume: 0.0
    property real currentBrightness: 0.0
    property bool hasBrightness: false // Start hidden for desktops

    property string mediaTitle: "Not Playing"
    property string mediaArtist: "---"
    property string mediaStatus: "Stopped"

    HoverHandler {
        id: dashHover
        // Use a simple check: is the mouse inside the dashboard root?
        onHoveredChanged: {
            if (hovered) {
                rootShell.dashboardRef.cancelDismiss();
            } else {
                // Add a slight delay before requesting dismissal
                // to allow moving back to the trigger area if needed
                rootShell.dashboardRef.requestDismiss();
            }
        }
    }

    // --- Native Notification Server ---
    NotificationServer {
        id: notifServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true // Tell apps we can hold notifications indefinitely
        
        // Force Quickshell to track every incoming broadcast
        onNotification: (notif) => {
            notif.tracked = true; 
        }
    }

    // --- Data Fetching Engine ---
    Timer {
        interval: 2000
        running: dashboardRoot.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sysStatsProc.running = true;
            mediaFetcher.running = true;
            volFetcher.running = true;
            brightFetcher.running = true;
        }
    }

    Process {
        id: sysStatsProc
        command: ["sh", "-c", "echo \"{\\\"cpu\\\": $(top -bn1 | awk '/%Cpu/ {print (100-$8)/100}'), \\\"ram\\\": $(free | awk '/Mem/ {print $3/$2}'), \\\"gpu\\\": $(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null | awk '{print $1/100}' || echo 0)}\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    dashboardRoot.sysCpu = data.cpu || 0.0;
                    dashboardRoot.sysRam = data.ram || 0.0;
                    dashboardRoot.sysGpu = data.gpu || 0.0;
                } catch(e) {}
                sysStatsProc.running = false;
            }
        }
    }

    Process {
        id: mediaFetcher
        command: ["playerctl", "metadata", "--format", "{\"title\": \"{{title}}\", \"artist\": \"{{artist}}\", \"status\": \"{{status}}\"}"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    dashboardRoot.mediaTitle = data.title || "Unknown";
                    dashboardRoot.mediaArtist = data.artist || "Unknown";
                    dashboardRoot.mediaStatus = data.status || "Stopped";
                } catch(e) {
                    dashboardRoot.mediaTitle = "Not Playing";
                    dashboardRoot.mediaArtist = "---";
                    dashboardRoot.mediaStatus = "Stopped";
                }
                mediaFetcher.running = false;
            }
        }
    }

    Process {
        id: volFetcher
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split(" ");
                if (parts.length >= 2 && !volSlider.pressed) {
                    dashboardRoot.currentVolume = parseFloat(parts[1]);
                }
                volFetcher.running = false;
            }
        }
    }

    Process {
    id: brightFetcher
    // Use -d to target your specific backlight device if you know the name (e.g., intel_backlight)
    // Otherwise, filter by class in the logic
    command: ["brightnessctl", "-m"]
    running: false
    stdout: StdioCollector {
        onStreamFinished: {
            let lines = this.text.trim().split("\n");
            let found = false;
            
            for (let i = 0; i < lines.length; i++) {
                let parts = lines[i].split(",");
                // Only act if the device class (parts[1]) is 'backlight'
                if (parts.length >= 4 && parts[1] === "backlight") {
                    let pct = parts[3].replace("%", "");
                    let parsedPct = parseFloat(pct);
                    if (!isNaN(parsedPct)) {
                        dashboardRoot.hasBrightness = true;
                        if (!brightSlider.pressed) {
                            dashboardRoot.currentBrightness = parsedPct / 100.0;
                        }
                        found = true;
                        break; // Stop after finding the first valid backlight
                    }
                }
            }
            if (!found) dashboardRoot.hasBrightness = false;
            brightFetcher.running = false;
        }
    }
}

    Process { id: setVolProc; running: false }
    Process { id: setBrightProc; running: false }
    Process { id: mediaControlProc; running: false }
    Process { id: screenshotProc; running: false }

    Item {
        anchors.fill: parent
        HoverHandler {
            id: rootHover
            // The hover state is true as long as you are anywhere within the Popup's rect
            onHoveredChanged: {
                if (hovered) {
                    rootShell.dashboardRef.cancelDismiss()
                } else {
                    // ONLY dismiss if you aren't clicking a slider or the button
                    if (!volSlider.pressed && !brightSlider.pressed) {
                        rootShell.dashboardRef.requestDismiss()
                    }
                }
            }
        }
    }

    Item {
        width: 46; height: 64 
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: rootShell.barPosition === "left" ? parent.left : undefined
        anchors.left: rootShell.barPosition === "right" ? parent.right : undefined
        
        HoverHandler {
            id: bridgeHover
            onHoveredChanged: {
                if (hovered) rootShell.dashboardRef.cancelDismiss()
                else rootShell.dashboardRef.requestDismiss()
            }
        }
    }

    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.Left
            if (rootShell.barPosition === "right") return Item.Right
            if (rootShell.barPosition === "top") return Item.Top
            if (rootShell.barPosition === "bottom") return Item.Bottom
            return Item.Center
        }

        opacity: dashboardRoot.active ? 1.0 : 0.0
        scale: dashboardRoot.active ? 1.0 : 0.0
        x: dashboardRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : (rootShell.barPosition === "left" ? -40 : 0))
        y: dashboardRoot.active ? 0 : (rootShell.barPosition === "bottom" ? 40 : (rootShell.barPosition === "top" ? -40 : 0))
        
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            color: rootShell.colorBackground
            z: 2
            
            topLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "top") ? 0 : dashboardRoot.radiusValue
            bottomLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "bottom") ? 0 : dashboardRoot.radiusValue
            topRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "top") ? 0 : dashboardRoot.radiusValue
            bottomRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "bottom") ? 0 : dashboardRoot.radiusValue
        }

        Item {
            anchors.fill: parent
            z: 2 
            visible: dashboardRoot.width > 30

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"

                Shape {
                    x: 0; y: -dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: dashboardRoot.wingSize
                        PathLine { x: dashboardRoot.wingSize; y: dashboardRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: dashboardRoot.wingSize }
                        PathLine { x: 0; y: dashboardRoot.wingSize }
                    }
                }
                Shape {
                    x: 0; y: parent.height
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: dashboardRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: dashboardRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: parent.width - dashboardRoot.wingSize; y: -dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: dashboardRoot.wingSize
                        PathLine { x: dashboardRoot.wingSize; y: dashboardRoot.wingSize }
                        PathLine { x: dashboardRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: dashboardRoot.wingSize; controlX: dashboardRoot.wingSize; controlY: dashboardRoot.wingSize }
                    }
                }
                Shape {
                    x: parent.width - dashboardRoot.wingSize; y: parent.height
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: dashboardRoot.wingSize; y: 0 }
                        PathLine { x: dashboardRoot.wingSize; y: dashboardRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: dashboardRoot.wingSize; controlY: 0 }
                    }
                }
            }
        }

        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 24
            z: 5

            ColumnLayout {
                anchors.fill: parent
                spacing: 20

                // 1. Header Spanning Full Width
                RowLayout {
                    Layout.fillWidth: true
                    
                    Text { 
                        text: Qt.formatDateTime(rootShell.clockRef.currentTime, "hh:mm") 
                        font.family: rootShell.shellFont; font.pixelSize: 64; font.bold: true; color: rootShell.colorText 
                    }
                    
                    Item { Layout.fillWidth: true } // Flex spacer pushes the stack to the right
                    
                    ColumnLayout {
                        spacing: -4
                        Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "dddd"); font.family: rootShell.shellFont; font.pixelSize: 26; font.bold: true; color: rootShell.colorText; Layout.alignment: Qt.AlignRight }
                        Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "MMMM d"); font.family: rootShell.shellFont; font.pixelSize: 20; color: rootShell.colorSubtext; Layout.alignment: Qt.AlignRight }
                    }
                }

                // 2. Resource Rings Centered Below Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24
                    
                    Repeater {
                        model: [
                            { label: "CPU", val: dashboardRoot.sysCpu, color: "#89b4fa" }, 
                            { label: "GPU", val: dashboardRoot.sysGpu, color: "#cba6f7" }, 
                            { label: "RAM", val: dashboardRoot.sysRam, color: "#a6e3a1" } 
                        ]
                        delegate: Item {
                            id: ringDelegate
                            width: 52; height: 52
                            
                            property real animatedSweep: isNaN(modelData.val) ? 0 : (modelData.val * 360)
                            Behavior on animatedSweep { NumberAnimation { duration: 500; easing.type: Easing.OutQuad } }

                            Shape {
                                anchors.centerIn: parent; width: 52; height: 52
                                ShapePath { fillColor: "transparent"; strokeColor: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1); strokeWidth: 4; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 26; centerY: 26; radiusX: 24; radiusY: 24; startAngle: 0; sweepAngle: 360 } }
                                ShapePath { 
                                    fillColor: "transparent"; strokeColor: modelData.color; strokeWidth: 4; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 26; centerY: 26; radiusX: 24; radiusY: 24; startAngle: -90; sweepAngle: ringDelegate.animatedSweep } 
                                }
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: -2
                                    Text { text: Math.round((isNaN(modelData.val) ? 0 : modelData.val) * 100); color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: modelData.label; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                }

                // 3. Quick Toggles Grid 
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 12

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 32; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1)
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle { width: 40; height: 40; radius: 20; color: rootShell.colorAccent; Text { anchors.centerIn: parent; text: "wifi"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20 } }
                            ColumnLayout { 
                                spacing: 0
                                Text { text: "Wi-Fi"; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13 }
                                Text { text: "Home Network"; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11 } 
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 32; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle { width: 40; height: 40; radius: 20; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1); Text { anchors.centerIn: parent; text: "bluetooth"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 20 } }
                            ColumnLayout { 
                                spacing: 0
                                Text { text: "Bluetooth"; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13 }
                                Text { text: "Off"; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11 } 
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 32; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle { width: 40; height: 40; radius: 20; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1); Text { anchors.centerIn: parent; text: "do_not_disturb_on"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 20 } }
                            ColumnLayout { 
                                spacing: 0
                                Text { text: "Do Not Disturb"; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13 }
                                Text { text: "Off"; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11 } 
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 32; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1)
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle { width: 40; height: 40; radius: 20; color: rootShell.colorAccent; Text { anchors.centerIn: parent; text: "local_cafe"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20 } }
                            ColumnLayout { 
                                spacing: 0
                                Text { text: "Caffeine"; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13 }
                                Text { text: "Active"; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11 } 
                            }
                        }
                    }
                }

                // 4. Action Button Row 
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Rectangle { 
                        Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        Text { anchors.centerIn: parent; text: "settings"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 }
                    }
                    Rectangle { 
                        Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        Text { anchors.centerIn: parent; text: "menu"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 }
                    }
                    Rectangle { 
                        Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                screenshotProc.command = ["sh", "-c", "grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +'%s_grim.png')"]
                                screenshotProc.running = true
                                rootShell.dashboardRef.forceDismiss()
                            }
                        }
                        Text { anchors.centerIn: parent; text: "screenshot_region"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 }
                    }
                    Rectangle { 
                        Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorClose.r, rootShell.colorClose.g, rootShell.colorClose.b, 0.1)
                        Text { anchors.centerIn: parent; text: "power_settings_new"; font.family: "Material Symbols Outlined"; color: rootShell.colorClose; font.pixelSize: 22 }
                    }
                }

                // 5. Sliders
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    
                    Item {
                        Layout.fillWidth: true
                        // If brightness exists, 48 (vol) + 16 (gap) = 64. If not, just 48.
                        Layout.preferredHeight: dashboardRoot.hasBrightness ? 64 : 48

                        Slider {
                            id: volSlider
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 48
                            
                            value: dashboardRoot.currentVolume
                            
                            // Add this to prevent event bubbling
                            MouseArea {
                                anchors.fill: parent
                                propagateComposedEvents: false
                                hoverEnabled: true
                                // This stops the click from "falling through" to your dismiss logic
                                onClicked: (mouse) => {
                                    mouse.accepted = true;
                                    // Ensure the volume change logic is triggered here
                                }
                            }

                            onMoved: {
                                dashboardRoot.currentVolume = value;
                                setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", value.toFixed(2)]
                                setVolProc.running = true
                            }

                            background: Rectangle {
                                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                                radius: 24
                                
                                // Progress fill
                                Rectangle { 
                                    width: volSlider.visualPosition * parent.width; height: parent.height
                                    color: rootShell.colorText; radius: 24 
                                }
                                
                                // Icons (Static Layout)
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 16
                                    Text { text: "volume_down"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "volume_up"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                                }
                                
                                // Percentage Overlay (Appears centered during drag)
                                Text {
                                    text: Math.round(volSlider.value * 100) + "%"
                                    color: rootShell.colorBackground
                                    font.family: rootShell.shellFont
                                    font.bold: true
                                    font.pixelSize: 14
                                    anchors.centerIn: parent
                                    opacity: volSlider.pressed ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }
                            handle: Item {} 
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: dashboardRoot.hasBrightness ? 48 : 0
                        visible: dashboardRoot.hasBrightness

                        Slider {
                            id: brightSlider
                            anchors.fill: parent
                            value: dashboardRoot.currentBrightness
                            
                            onMoved: {
                                dashboardRoot.currentBrightness = value;
                                let rawVal = Math.round(value * 100) + "%"
                                setBrightProc.command = ["brightnessctl", "set", rawVal]
                                setBrightProc.running = true
                            }

                            background: Rectangle {
                                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                                radius: 24
                                Rectangle { width: brightSlider.visualPosition * parent.width; height: parent.height; color: rootShell.colorText; radius: 24 }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 16
                                    Text { text: "light_mode"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                                    Item { Layout.fillWidth: true }
                                    Text { text: Math.round(brightSlider.value * 100) + "%"; color: rootShell.colorBackground; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignVCenter }
                                }
                            }
                            handle: Item {}
                        }
                    }
                }

                // 6. Media Player
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 16; color: "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 0; spacing: 16
                        Rectangle { width: 48; height: 48; radius: 8; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1); Text { anchors.centerIn: parent; text: "music_note"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 24 } }
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Text { text: dashboardRoot.mediaTitle; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: dashboardRoot.mediaArtist; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        RowLayout {
                            spacing: 8
                            MouseArea {
                                width: 24; height: 24; cursorShape: Qt.PointingHandCursor
                                onClicked: { mediaControlProc.command = ["playerctl", "previous"]; mediaControlProc.running = true; mediaFetcher.running = true }
                                Text { anchors.centerIn: parent; text: "skip_previous"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
                            }
                            Rectangle { 
                                width: 36; height: 36; radius: 18; color: rootShell.colorText
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { mediaControlProc.command = ["playerctl", "play-pause"]; mediaControlProc.running = true; mediaFetcher.running = true }
                                }
                                Text { anchors.centerIn: parent; text: dashboardRoot.mediaStatus === "Playing" ? "pause" : "play_arrow"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20 } 
                            }
                            MouseArea {
                                width: 24; height: 24; cursorShape: Qt.PointingHandCursor
                                onClicked: { mediaControlProc.command = ["playerctl", "next"]; mediaControlProc.running = true; mediaFetcher.running = true }
                                Text { anchors.centerIn: parent; text: "skip_next"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
                            }
                        }
                    }
                }

                // 7. Notifications Area (Native Service Integration)
                ColumnLayout {
                    id: notifAreaLayout
                    Layout.fillWidth: true

                    property real targetHeight: {
                        let count = notifList.count;
                        if (count <= 1) return 64 + 40;  
                        return 136 + 40;
                    }

                    // Height logic: 0/1 count = 64px, 2+ count = 128px. 
                    // We add 40px for the Header text + spacing.
                    Layout.preferredHeight: {
                        let count = notifList.count;
                        if (count <= 1) return 64 + 40;  
                        return 136 + 40; // Updated from 128 to 136 to include the 8px spacing
                    }

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.InOutQuad
                        }
                    }
                    
                    spacing: 12

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        // FORCE vertical alignment to the center, overriding baseline
                        Layout.alignment: Qt.AlignVCenter 

                        Text { 
                            text: "Notifications"
                            font.family: rootShell.shellFont
                            font.pixelSize: 14
                            font.bold: true
                            color: rootShell.colorText 
                            Layout.alignment: Qt.AlignVCenter // Ensure this specific text is centered
                        }
                        
                        Item { Layout.fillWidth: true } // Flex spacer

                        Item {
                            id: clearBtn
                            implicitWidth: clearText.width + 10
                            implicitHeight: 20
                            Layout.alignment: Qt.AlignVCenter // Force the button container to center
                            visible: notifList.count > 0

                            Text {
                                id: clearText
                                text: "Clear all"
                                font.family: rootShell.shellFont
                                font.pixelSize: 11
                                anchors.centerIn: parent // Centers text inside the button container
                                color: clearMouse.containsMouse ? rootShell.colorText : rootShell.colorAccent
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: (mouse) => {
                                    mouse.accepted = true;
                                    
                                    // Safely pull the underlying array from the ObjectModel
                                    let notificationsArray = notifServer.trackedNotifications.values;
                                    
                                    if (notificationsArray && notificationsArray.length > 0) {
                                        // Loop backwards through the JavaScript array
                                        for (let i = notificationsArray.length - 1; i >= 0; i--) {
                                            let notif = notificationsArray[i];
                                            if (notif && typeof notif.dismiss === "function") {
                                                notif.dismiss();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Placeholder - Only visible when empty
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: 16
                        visible: notifList.count === 0
                        color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        
                        Text { 
                            text: "No notifications"
                            anchors.centerIn: parent
                            font.family: rootShell.shellFont
                            color: rootShell.colorSubtext
                            font.pixelSize: 12 
                        }
                    }

                    // The List - Only visible when count > 0
                    ListView {
                        id: notifList
                        Layout.fillWidth: true
                        Layout.preferredHeight: {
                            let count = notifList.count;
                            // Base 30 covers header and internal spacing.
                            if (count <= 1) return 64 + 30;
                            return 136 + 30;
                        }
                        visible: notifList.count > 0
                        clip: true
                        spacing: 8
                        model: notifServer.trackedNotifications

                        // --- 1. ADD DISAPPEARING TRANSITIONS HERE ---
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 200; easing.type: Easing.InOutQuad }
                                NumberAnimation { property: "scale"; to: 0.8; duration: 200; easing.type: Easing.InOutQuad }
                                NumberAnimation { property: "height"; to: 0; duration: 250; easing.type: Easing.InOutQuad }
                            }
                        }

                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutCubic }
                        }

                        // --- 2. UPDATED WRAPPER DELEGATE ---
                        delegate: Item {
                            required property var modelData 
                            width: notifList.width
                            // Tracks the height of your actual card container so it can collapse down to 0
                            height: cardBody.height

                            Rectangle {
                                id: cardBody
                                width: parent.width
                                height: 64
                                radius: 12
                                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                                transformOrigin: Item.Center

                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                                    
                                    Rectangle {
                                        width: 40; height: 40; radius: 8; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1)
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: "notifications"
                                            font.family: "Material Symbols Outlined"
                                            color: rootShell.colorText
                                            font.pixelSize: 20
                                            visible: notifImg.status !== Image.Ready
                                        }
                                        
                                        Image {
                                            id: notifImg
                                            anchors.fill: parent; anchors.margins: 4
                                            source: (modelData.image && modelData.image.startsWith("/")) ? modelData.image : ""
                                            visible: source !== ""
                                            fillMode: Image.PreserveAspectFit
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2; Layout.fillWidth: true
                                        Text { text: modelData.summary; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Text { text: modelData.body; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true }
                                    }
                                    
                                    MouseArea {
                                        width: 24; height: 24; cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.dismiss()
                                        Text { anchors.centerIn: parent; text: "close"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 16 }
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
