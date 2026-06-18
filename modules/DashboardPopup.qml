import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Notifications
// Explicitly import your components directory if it's not implicitly in the search path
import "components" 

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
                if (parts.length >= 2 && !volSlider.isPressed) {
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
                            if (!brightSlider.isPressed) dashboardRoot.currentBrightness = parsedPct / 100.0;
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
                else if (!volSlider.isPressed && !brightSlider.isPressed) rootShell.dashboardRef.requestDismiss()
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
            anchors.fill: parent
            z: 3
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
                        PathLine { x: parent.width; y: dashboardRoot.wingSize }
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

                // Systems Rings Area
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    SysRing { label: "CPU"; value: dashboardRoot.sysCpu; ringColor: "#89b4fa" }
                    SysRing { label: "GPU"; value: dashboardRoot.sysGpu; ringColor: "#cba6f7" }
                    SysRing { label: "RAM"; value: dashboardRoot.sysRam; ringColor: "#a6e3a1" }
                    SysRing { label: "DISK"; value: dashboardRoot.sysDisk; ringColor: "#f38ba8" }
                }

                // Toggle Grid
                GridLayout {
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 12
                    Layout.alignment: Qt.AlignHCenter

                    ToggleSwitch {
                        label: "Wi-Fi"
                        iconName: !dashboardRoot.wifiAvailable ? "wifi_off" : "wifi"
                        checked: dashboardRoot.wifiActive
                        isAvailable: dashboardRoot.wifiAvailable
                        onToggled: {
                            dashboardRoot.wifiActive = !dashboardRoot.wifiActive
                            wifiToggleProc.command = ["sh", "-c", "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"]
                            wifiToggleProc.running = true
                        }
                    }

                    ToggleSwitch {
                        label: "Bluetooth"
                        iconName: "bluetooth"
                        checked: dashboardRoot.btActive
                        onToggled: {
                            dashboardRoot.btActive = !dashboardRoot.btActive
                            btToggleProc.command = ["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on"]
                            btToggleProc.running = true
                        }
                    }

                    ToggleSwitch {
                        label: "DND"
                        iconName: "do_not_disturb_on"
                        checked: dashboardRoot.dndActive
                        onToggled: {
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

                    ToggleSwitch {
                        label: "Caffeine"
                        iconName: "local_cafe"
                        checked: dashboardRoot.caffeineActive
                        onToggled: {
                            dashboardRoot.caffeineActive = !dashboardRoot.caffeineActive
                            caffeineToggleProc.command = dashboardRoot.caffeineActive 
                                ? ["systemctl", "--user", "stop", "hypridle.service"]
                                : ["systemctl", "--user", "start", "hypridle.service"];
                            caffeineToggleProc.running = true
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
                        DashboardSlider {
                            id: volSlider
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: 48
                            iconLow: "volume_down"
                            iconHigh: "volume_up"
                            value: dashboardRoot.currentVolume
                            onMoved: (newValue) => {
                                dashboardRoot.currentVolume = newValue;
                                setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", newValue.toFixed(2)]
                                setVolProc.running = true
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: dashboardRoot.hasBrightness ? 48 : 0
                        visible: dashboardRoot.hasBrightness
                        DashboardSlider {
                            id: brightSlider
                            anchors.fill: parent
                            iconLow: "light_mode"
                            iconHigh: "" // Passing empty triggers the right-aligned percentage readout block 
                            value: dashboardRoot.currentBrightness
                            onMoved: (newValue) => {
                                dashboardRoot.currentBrightness = newValue;
                                let rawVal = Math.round(newValue * 100) + "%"
                                setBrightProc.command = ["brightnessctl", "set", rawVal]
                                setBrightProc.running = true
                            }
                        }
                    }
                }

                // Media Player Area
                MediaControl {
                    onPlayPauseClicked: {
                        mediaControlProc.command = ["playerctl", "play-pause"]
                        mediaControlProc.running = true
                    }
                    onPrevClicked: {
                        mediaControlProc.command = ["playerctl", "previous"]
                        mediaControlProc.running = true
                    }
                    onNextClicked: {
                        mediaControlProc.command = ["playerctl", "next"]
                        mediaControlProc.running = true
                    }
                }

                // Notifications Area
                NotificationCenter {}
            }
        }
    }
}
