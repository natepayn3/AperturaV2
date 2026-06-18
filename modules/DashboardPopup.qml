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
    property real maxCardHeight: 760

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
    property real sysDisk: 0.0

    // Properties to store raw values for accurate CPU calculating
    property var lastCpuTotal: 0
    property var lastCpuIdle: 0

    property real currentVolume: 0.0
    property real currentBrightness: 0.0
    property bool hasBrightness: false

    property string mediaTitle: "Not Playing"
    property string mediaArtist: "---"
    property string mediaStatus: "Stopped"

    property bool wifiAvailable: false
    property bool wifiActive: false
    property bool btActive: false
    property bool dndActive: false
    property bool caffeineActive: false 

    // --- Weather Properties ---
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

    onActiveChanged: {
        if (active) {
            sysStatsProc.running = true;
            sysStatsTimer.running = true;
            volFetcher.running = true;
            brightFetcher.running = true;
            wifiStateCheck.running = true;
            btStateCheck.running = true;
            checkHypridleProc.running = true;
            if (weatherTemp === "--") weatherFetcher.running = true;
        } else {
            sysStatsTimer.running = false;
        }
    }

    Component.onCompleted: {
        mediaFollower.running = true;
        volumeEventListener.running = true;
        wifiStateCheck.running = true;
        btStateCheck.running = true;
        checkHypridleProc.running = true;
    }

    HoverHandler {
        id: dashHover
        onHoveredChanged: {
            if (hovered) rootShell.dashboardRef.cancelDismiss();
            else rootShell.dashboardRef.requestDismiss();
        }
    }

    NotificationServer {
        id: notifServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: (notif) => {
            if (!dashboardRoot.dndActive) notif.tracked = true;
            else notif.dismiss();
        }
    }

    Timer {
        id: weatherTimer
        interval: 900000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: weatherFetcher.running = true
    }

    // High-frequency polling timer for unified updates
    Timer {
        id: sysStatsTimer
        interval: 1500; running: false; repeat: true
        onTriggered: {
            if (!sysStatsProc.running) sysStatsProc.running = true;
        }
    }

    Process {
        id: checkHypridleProc
        command: ["systemctl", "--user", "is-active", "hypridle.service"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                dashboardRoot.caffeineActive = (this.text.trim() !== "active");
                checkHypridleProc.running = false;
            }
        }
    }

    Process {
        id: weatherFetcher
        command: ["curl", "-s", "https://wttr.is/" + dashboardRoot.weatherLocationOverride.trim() + "?format=j1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text);
                    let current = data.current_condition[0];
                    dashboardRoot.weatherTemp = current.temp_F + "°F";
                    dashboardRoot.weatherFeelsLike = current.FeelsLikeF + "°F";
                    let code = current.weatherCode.toString();
                    dashboardRoot.weatherDesc = dashboardRoot.weatherDescMap[code] !== undefined ? dashboardRoot.weatherDescMap[code] : current.weatherDesc[0].value;
                    dashboardRoot.weatherGlyph = dashboardRoot.weatherIconMap[code] !== undefined ? dashboardRoot.weatherIconMap[code] : "cloud";
                } catch (e) {}
                weatherFetcher.running = false;
            }
        }
    }

    Process {
        id: volumeEventListener
        command: ["sh", "-c", "pactl subscribe | grep --line-buffered \"sink\""]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                volFetcher.running = true;
            }
        }
    }

    Process {
        id: mediaFollower
        command: ["playerctl", "metadata", "--follow", "--format", "{\"title\": \"{{title}}\", \"artist\": \"{{artist}}\", \"status\": \"{{status}}\"}"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let parsed = JSON.parse(data.trim());
                    dashboardRoot.mediaTitle = parsed.title || "Unknown";
                    dashboardRoot.mediaArtist = parsed.artist || "Unknown";
                    dashboardRoot.mediaStatus = parsed.status || "Stopped";
                } catch(e) {
                    dashboardRoot.mediaTitle = "Not Playing";
                    dashboardRoot.mediaArtist = "---";
                    dashboardRoot.mediaStatus = "Stopped";
                }
            }
        }
    }

    Process {
        id: wifiStateCheck
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device | grep -q '^wifi:' && echo 'AVAILABLE' || echo 'MISSING'; nmcli radio wifi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 1) dashboardRoot.wifiAvailable = (lines[0] === "AVAILABLE");
                if (lines.length >= 2) dashboardRoot.wifiActive = dashboardRoot.wifiAvailable && (lines[1].trim() === "enabled");
                wifiStateCheck.running = false;
            }
        }
    }

    Process {
        id: btStateCheck
        command: ["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo 'ON' || echo 'OFF'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                dashboardRoot.btActive = (this.text.trim() === "ON");
                btStateCheck.running = false;
            }
        }
    }

    Process {
        id: sysStatsProc
        command: ["sh", "-c", "echo \"$(cat /proc/stat | grep 'cpu ')\"; awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print (t-a)/t}' /proc/meminfo; cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || cat /sys/class/hwmon/hwmon*/device/gpu_busy_percent 2>/dev/null || nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0; df / | awk 'NR==2 {print $5}' | sed 's/%//'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let lines = this.text.trim().split("\n");
                    if (lines.length >= 4) {
                        let cpuParts = lines[0].split(/\s+/).filter(Boolean);
                        if (cpuParts.length >= 5) {
                            let user = parseInt(cpuParts[1]) || 0;
                            let nice = parseInt(cpuParts[2]) || 0;
                            let system = parseInt(cpuParts[3]) || 0;
                            let idle = parseInt(cpuParts[4]) || 0;
                            let iowait = parseInt(cpuParts[5]) || 0;
                            let irq = parseInt(cpuParts[6]) || 0;
                            let softirq = parseInt(cpuParts[7]) || 0;
                            
                            let total = user + nice + system + idle + iowait + irq + softirq;
                            let totalDelta = total - dashboardRoot.lastCpuTotal;
                            let idleDelta = idle - dashboardRoot.lastCpuIdle;
                            
                            if (totalDelta > 0) {
                                dashboardRoot.sysCpu = (totalDelta - idleDelta) / totalDelta;
                            }
                            dashboardRoot.lastCpuTotal = total;
                            dashboardRoot.lastCpuIdle = idle;
                        }
                        
                        dashboardRoot.sysRam = parseFloat(lines[1]) || 0.0;
                        
                        let rawGpu = parseFloat(lines[2]) || 0.0;
                        dashboardRoot.sysGpu = rawGpu > 1.0 ? rawGpu / 100.0 : rawGpu;
                        
                        dashboardRoot.sysDisk = (parseFloat(lines[3]) || 0.0) / 100.0;
                    }
                } catch(e) {}
                sysStatsProc.running = false;
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
        command: ["brightnessctl", "-m"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                let found = false;
                for (let i = 0; i < lines.length; i++) {
                    let parts = lines[i].split(",");
                    if (parts.length >= 4 && parts[1] === "backlight") {
                        let pct = parts[3].replace("%", "");
                        let parsedPct = parseFloat(pct);
                        if (!isNaN(parsedPct)) {
                            dashboardRoot.hasBrightness = true;
                            if (!brightSlider.pressed) dashboardRoot.currentBrightness = parsedPct / 100.0;
                            found = true;
                            break;
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
    Process { id: wifiToggleProc; running: false }
    Process { id: btToggleProc; running: false }
    Process { id: caffeineToggleProc; running: false }

    Item {
        anchors.fill: parent
        HoverHandler {
            id: rootHover
            onHoveredChanged: {
                if (hovered) rootShell.dashboardRef.cancelDismiss()
                else if (!volSlider.pressed && !brightSlider.pressed) rootShell.dashboardRef.requestDismiss()
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
        transformOrigin: rootShell.barPosition === "left" ? Item.Left : (rootShell.barPosition === "right" ? Item.Right : (rootShell.barPosition === "top" ? Item.Top : (rootShell.barPosition === "bottom" ? Item.Bottom : Item.Center)))
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
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 24
            z: 5

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                // Time / Date / Weather Section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "h:mm AP"); font.family: rootShell.shellFont; font.pixelSize: 48; font.bold: true; color: rootShell.colorText }
                        Item { Layout.fillWidth: true }
                        ColumnLayout {
                            spacing: -4
                            Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "dddd"); font.family: rootShell.shellFont; font.pixelSize: 22; font.bold: true; color: rootShell.colorText; Layout.alignment: Qt.AlignRight }
                            Text { text: Qt.formatDateTime(rootShell.clockRef.currentTime, "MMMM d"); font.family: rootShell.shellFont; font.pixelSize: 16; color: rootShell.colorSubtext; Layout.alignment: Qt.AlignRight }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: dashboardRoot.weatherGlyph; font.family: "Material Symbols Outlined"; font.pixelSize: 20; color: rootShell.colorAccent }
                        Text { text: dashboardRoot.weatherDesc; font.family: rootShell.shellFont; font.pixelSize: 13; font.bold: true; color: rootShell.colorText }
                        Text { text: "•  Feels like " + dashboardRoot.weatherFeelsLike; font.family: rootShell.shellFont; font.pixelSize: 13; color: rootShell.colorSubtext; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: dashboardRoot.weatherTemp; font.family: rootShell.shellFont; font.pixelSize: 15; font.bold: true; color: rootShell.colorText }
                    }
                }

                // Systems Rings Area (Upsized to 68x68, Horizontally Distributed to Fill Space)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Repeater {
                        model: [
                            { label: "CPU", val: dashboardRoot.sysCpu, color: "#89b4fa" }, 
                            { label: "GPU", val: dashboardRoot.sysGpu, color: "#cba6f7" }, 
                            { label: "RAM", val: dashboardRoot.sysRam, color: "#a6e3a1" },
                            { label: "DISK", val: dashboardRoot.sysDisk, color: "#f38ba8" }
                        ]
                        delegate: Item {
                            id: ringDelegate
                            Layout.fillWidth: true
                            Layout.preferredHeight: 68
                            
                            readonly property real cleanVal: (!isFinite(modelData.val) || isNaN(modelData.val)) ? 0.0 : Math.max(0.0, Math.min(1.0, modelData.val))
                            property real animatedSweep: cleanVal * 360
                            Behavior on animatedSweep { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

                            Shape {
                                width: 68; height: 68
                                anchors.centerIn: parent
                                layer.enabled: true
                                layer.samples: 4
                                
                                ShapePath { 
                                    fillColor: "transparent"; strokeColor: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); strokeWidth: 5; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 34; centerY: 34; radiusX: 29; radiusY: 29; startAngle: 0; sweepAngle: 360 } 
                                }
                                ShapePath { 
                                    fillColor: "transparent"; strokeColor: modelData.color; strokeWidth: 5; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 34; centerY: 34; radiusX: 29; radiusY: 29; startAngle: -90; sweepAngle: ringDelegate.animatedSweep } 
                                }
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: -2
                                    Text { text: Math.round(ringDelegate.cleanVal * 100) + "%"; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: modelData.label; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                }

                // Inline Row Pill Toggles (Upsized to 80x48, Expanded to Fill Layout Width, Text Matching Color)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Wifi Toggle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 24
                        color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.12)
                        opacity: dashboardRoot.wifiAvailable ? 1.0 : 0.5

                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: dashboardRoot.wifiActive ? rootShell.colorText : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                            x: dashboardRoot.wifiActive ? parent.width - width - 4 : 4
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                            Text {
                                anchors.centerIn: parent
                                text: !dashboardRoot.wifiAvailable ? "wifi_off" : "wifi"
                                font.family: "Material Symbols Outlined"
                                color: dashboardRoot.wifiActive ? rootShell.colorBackground : rootShell.colorText
                                font.pixelSize: 20
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: dashboardRoot.wifiAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (dashboardRoot.wifiAvailable) {
                                    dashboardRoot.wifiActive = !dashboardRoot.wifiActive
                                    wifiToggleProc.command = ["sh", "-c", "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"]
                                    wifiToggleProc.running = true
                                }
                            }
                        }
                    }

                    // Bluetooth Toggle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 24
                        color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.12)

                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: dashboardRoot.btActive ? rootShell.colorText : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                            x: dashboardRoot.btActive ? parent.width - width - 4 : 4
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                            Text {
                                anchors.centerIn: parent
                                text: "bluetooth"
                                font.family: "Material Symbols Outlined"
                                color: dashboardRoot.btActive ? rootShell.colorBackground : rootShell.colorText
                                font.pixelSize: 20
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dashboardRoot.btActive = !dashboardRoot.btActive
                                btToggleProc.command = ["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on"]
                                btToggleProc.running = true
                            }
                        }
                    }

                    // DND Toggle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 24
                        color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.12)

                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: dashboardRoot.dndActive ? rootShell.colorText : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                            x: dashboardRoot.dndActive ? parent.width - width - 4 : 4
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                            Text {
                                anchors.centerIn: parent
                                text: "do_not_disturb_on"
                                font.family: "Material Symbols Outlined"
                                color: dashboardRoot.dndActive ? rootShell.colorBackground : rootShell.colorText
                                font.pixelSize: 20
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dashboardRoot.dndActive = !dashboardRoot.dndActive
                                if (dashboardRoot.dndActive) {
                                    let arr = notifServer.trackedNotifications.values;
                                    if (arr && arr.length > 0) {
                                        for (let i = arr.length - 1; i >= 0; i--) {
                                            if (arr[i]) arr[i].dismiss();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Caffeine Toggle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 24
                        color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.12)

                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: dashboardRoot.caffeineActive ? rootShell.colorText : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                            x: dashboardRoot.caffeineActive ? parent.width - width - 4 : 4
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                            Text {
                                anchors.centerIn: parent
                                text: "local_cafe"
                                font.family: "Material Symbols Outlined"
                                color: dashboardRoot.caffeineActive ? rootShell.colorBackground : rootShell.colorText
                                font.pixelSize: 20
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dashboardRoot.caffeineActive = !dashboardRoot.caffeineActive
                                if (dashboardRoot.caffeineActive) {
                                    caffeineToggleProc.command = ["systemctl", "--user", "stop", "hypridle.service"]
                                } else {
                                    caffeineToggleProc.command = ["systemctl", "--user", "start", "hypridle.service"]
                                }
                                caffeineToggleProc.running = true
                            }
                        }
                    }
                }

                // Quick Action Utilities
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); Text { anchors.centerIn: parent; text: "settings"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 } }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); Text { anchors.centerIn: parent; text: "menu"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 } }
                    Rectangle { 
                        Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { screenshotProc.command = ["sh", "-c", "grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +'%s_grim.png')"]; screenshotProc.running = true; rootShell.dashboardRef.forceDismiss() } }
                        Text { anchors.centerIn: parent; text: "screenshot_region"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 22 }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 24; color: Qt.rgba(rootShell.colorClose.r, rootShell.colorClose.g, rootShell.colorClose.b, 0.2); Text { anchors.centerIn: parent; text: "power_settings_new"; font.family: "Material Symbols Outlined"; color: rootShell.colorClose; font.pixelSize: 22 } }
                }

                // Sliders Control Area
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: dashboardRoot.hasBrightness ? 64 : 48
                        Slider {
                            id: volSlider; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 48; value: dashboardRoot.currentVolume
                            onMoved: {
                                dashboardRoot.currentVolume = value;
                                setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", value.toFixed(2)]
                                setVolProc.running = true
                            }
                            background: Rectangle {
                                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); radius: 24
                                Rectangle { width: volSlider.visualPosition * parent.width; height: parent.height; color: rootShell.colorText; radius: 24 }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 16
                                    Text { text: "volume_down"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "volume_up"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter; transform: Translate { y: -3 } }
                                }
                                Text { text: Math.round(volSlider.value * 100) + "%"; color: rootShell.colorBackground; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 14; anchors.centerIn: parent; opacity: volSlider.pressed ? 1.0 : 0.0; Behavior on opacity { NumberAnimation { duration: 200 } } }
                            }
                            handle: Item {} 
                        }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: dashboardRoot.hasBrightness ? 48 : 0; visible: dashboardRoot.hasBrightness
                        Slider {
                            id: brightSlider; anchors.fill: parent; value: dashboardRoot.currentBrightness
                            onMoved: {
                                dashboardRoot.currentBrightness = value;
                                let rawVal = Math.round(value * 100) + "%"
                                setBrightProc.command = ["brightnessctl", "set", rawVal]
                                setBrightProc.running = true
                            }
                            background: Rectangle {
                                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15); radius: 24
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

                // Media Player Area
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 16; color: "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 0; spacing: 16
                        Rectangle { width: 48; height: 48; radius: 8; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2); Text { anchors.centerIn: parent; text: "music_note"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 24 } }
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Text { text: dashboardRoot.mediaTitle; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: dashboardRoot.mediaArtist; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        RowLayout {
                            spacing: 8
                            MouseArea { width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: { mediaControlProc.command = ["playerctl", "previous"]; mediaControlProc.running = true }
                                Text { anchors.centerIn: parent; text: "skip_previous"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
                            }
                            Rectangle { width: 36; height: 36; radius: 18; color: rootShell.colorText
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { mediaControlProc.command = ["playerctl", "play-pause"]; mediaControlProc.running = true } }
                                Text { anchors.centerIn: parent; text: dashboardRoot.mediaStatus === "Playing" ? "pause" : "play_arrow"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20 } 
                            }
                            MouseArea { width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: { mediaControlProc.command = ["playerctl", "next"]; mediaControlProc.running = true }
                                Text { anchors.centerIn: parent; text: "skip_next"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
                            }
                        }
                    }
                }

                // Notifications Area
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: notifList.count <= 0 ? 104 : (notifList.count === 1 ? 104 : 176)
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Notifications"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorText }
                        Item { Layout.fillWidth: true } 
                        Item {
                            implicitWidth: clearText.width + 10; implicitHeight: 20; visible: notifList.count > 0
                            Text { id: clearText; text: "Clear all"; font.family: rootShell.shellFont; font.pixelSize: 11; anchors.centerIn: parent; color: clearMouse.containsMouse ? rootShell.colorText : rootShell.colorAccent }
                            MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (notifServer.trackedNotifications.clear) notifServer.trackedNotifications.clear(); else notifServer.postReload(); } }
                        }
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 16; visible: notifList.count === 0; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                        Text { text: "No notifications"; anchors.centerIn: parent; font.family: rootShell.shellFont; color: rootShell.colorSubtext; font.pixelSize: 12 }
                    }

                    ListView {
                        id: notifList; Layout.fillWidth: true; clip: true; spacing: 8; model: notifServer.trackedNotifications
                        Layout.preferredHeight: notifList.count <= 0 ? 0 : (notifList.count === 1 ? 64 : 136)
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        remove: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; to: 0; duration: 200 } } }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic } }

                        delegate: Rectangle {
                            required property var modelData; width: notifList.width; height: 64; radius: 12; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12; spacing: 12
                                Rectangle {
                                    width: 40; height: 40; radius: 8; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1)
                                    Text { anchors.centerIn: parent; text: "notifications"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20; visible: notifImg.status !== Image.Ready }
                                    Image { id: notifImg; anchors.fill: parent; anchors.margins: 4; source: (modelData.image && modelData.image.startsWith("/")) ? modelData.image : ""; visible: source !== ""; fillMode: Image.PreserveAspectFit }
                                }
                                ColumnLayout {
                                    spacing: 2; Layout.fillWidth: true
                                    Text { text: modelData.summary; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: modelData.body; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true }
                                }
                                MouseArea { width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: modelData.dismiss()
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
