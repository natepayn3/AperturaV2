import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "components" 

Item {
    id: dashboardRoot

    property bool active: false
    property bool isHovered: dashHover.hovered || bridgeHover.hovered

    property real radiusValue: 24
    property real wingSize: 14

    // Dynamic responsive dimensions
    property bool isHorizontal: rootShell.barPosition === "top" || rootShell.barPosition === "bottom"
    property real maxCardWidth: isHorizontal ? 720 : 380
    width: Math.round(maxCardWidth)
    height: mainColumn.implicitHeight + 32

    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    // Explicit coordinate mapping against the fullscreen PanelWindow parent
    x: {
        if (rootShell.barPosition === "left") return 46;
        if (rootShell.barPosition === "right") return Math.round(parent.width - width - 46); // 🛠️ Round absolute delta
        return Math.round((parent.width - width) / 2);
    }

    y: {
        if (rootShell.barPosition === "top") return 46;
        if (rootShell.barPosition === "bottom") return Math.round(parent.height - height - 46); // 🛠️ Round absolute delta
        return Math.round((parent.height - height) / 2);
    }

    // --- Live Data Tracking ---
    property real sysCpu: 0.0
    property real sysGpu: 0.0
    property real sysRam: 0.0
    property real sysDisk: 0.0

    property var lastCpuTotal: 0
    property var lastCpuIdle: 0

    property real currentVolume: 0.0
    property real currentBrightness: 0.0
    property bool hasBrightness: false

    property string mediaTitle: "Not Playing"
    property string mediaArtist: "---"
    property string mediaStatus: "Stopped"
    property string mediaArtUrl: ""
    

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
            diskGpuProc.running = true;
            sysStatsTimer.running = true;
            cpuStatReader.reload();
            memInfoReader.reload();
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
        interval: 5000; running: false; repeat: true
        onTriggered: {
            cpuStatReader.reload();
            memInfoReader.reload();
            if (!diskGpuProc.running) diskGpuProc.running = true;
        }
    }

    // --- Native SysStats Readers ---
    FileView {
        id: memInfoReader
        path: "/proc/meminfo"
        onTextChanged: {
            let lines = text().split('\n');
            let total = 0, avail = 0;
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("MemTotal:")) total = parseInt(lines[i].replace(/\D/g, ''));
                if (lines[i].startsWith("MemAvailable:")) avail = parseInt(lines[i].replace(/\D/g, ''));
                if (total && avail) break; 
            }
            if (total > 0) dashboardRoot.sysRam = (total - avail) / total;
        }
    }

    FileView {
        id: cpuStatReader
        path: "/proc/stat"
        onTextChanged: {
            let cpuLine = text().split('\n')[0];
            let parts = cpuLine.split(/\s+/).filter(Boolean);
            if (parts.length >= 5) {
                let user = parseInt(parts[1]) || 0;
                let nice = parseInt(parts[2]) || 0;
                let system = parseInt(parts[3]) || 0;
                let idle = parseInt(parts[4]) || 0;
                let iowait = parseInt(parts[5]) || 0;
                let irq = parseInt(parts[6]) || 0;
                let softirq = parseInt(parts[7]) || 0;

                let total = user + nice + system + idle + iowait + irq + softirq;
                let totalDelta = total - dashboardRoot.lastCpuTotal;
                let idleDelta = idle - dashboardRoot.lastCpuIdle;

                if (totalDelta > 0) dashboardRoot.sysCpu = (totalDelta - idleDelta) / totalDelta;
                dashboardRoot.lastCpuTotal = total;
                dashboardRoot.lastCpuIdle = idle;
            }
        }
    }

    Process {
        id: diskGpuProc
        command: ["sh", "-c", "cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || cat /sys/class/hwmon/hwmon*/device/gpu_busy_percent 2>/dev/null || nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0; df / | awk 'NR==2 {print $5}' | sed 's/%//'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let lines = this.text.trim().split("\n");
                    if (lines.length >= 2) {
                        let rawGpu = parseFloat(lines[0]) || 0.0;
                        dashboardRoot.sysGpu = rawGpu > 1.0 ? rawGpu / 100.0 : rawGpu;
                        dashboardRoot.sysDisk = (parseFloat(lines[1]) || 0.0) / 100.0;
                    }
                } catch(e) {}
                diskGpuProc.running = false;
            }
        }
    }

    // --- System & Utilities Processes ---
    Process {
        id: checkHypridleProc
        command: ["pgrep", "-x", "hypridle"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                dashboardRoot.caffeineActive = (this.text.trim() === "");
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
            onRead: (data) => volFetcher.running = true
        }
    }

    Process {
        id: mediaFollower
        command: ["playerctl", "metadata", "--follow", "--format", "{\"title\": \"{{title}}\", \"artist\": \"{{artist}}\", \"status\": \"{{status}}\", \"artUrl\": \"{{mpris:artUrl}}\"}"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let parsed = JSON.parse(data.trim());
                    
                    if (parsed.status === "Stopped") {
                        dashboardRoot.mediaTitle = "Not Playing";
                        dashboardRoot.mediaArtist = "---";
                        dashboardRoot.mediaStatus = "Stopped";
                        dashboardRoot.mediaArtUrl = "";
                    } else {
                        dashboardRoot.mediaTitle = parsed.title || "Unknown";
                        dashboardRoot.mediaArtist = parsed.artist || "Unknown";
                        dashboardRoot.mediaStatus = parsed.status || "Stopped";
                        dashboardRoot.mediaArtUrl = parsed.artUrl || "";
                    }
                } catch(e) {
                    dashboardRoot.mediaTitle = "Not Playing";
                    dashboardRoot.mediaArtist = "---";
                    dashboardRoot.mediaStatus = "Stopped";
                    dashboardRoot.mediaArtUrl = "";
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
        id: volFetcher
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split(" ");
                if (parts.length >= 2 && !volSlider.isPressed) dashboardRoot.currentVolume = parseFloat(parts[1]);
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
        z: 1
        HoverHandler {
            id: dashHover
            onHoveredChanged: {
                if (hovered) {
                    rootShell.dashboardRef.cancelDismiss();
                } else if (!bridgeHover.hovered && !volSlider.isPressed && !brightSlider.isPressed) {
                    rootShell.dashboardRef.requestDismiss();
                }
            }
        }
    }

    Item {
        width: dashboardRoot.isHorizontal ? 120 : 46
        height: dashboardRoot.isHorizontal ? 46 : 120 

        x: {
            if (rootShell.barPosition === "left") return -46;
            if (rootShell.barPosition === "right") return dashboardRoot.width;
            return (dashboardRoot.width - width) / 2;
        }
        
        y: {
            if (rootShell.barPosition === "top") return -46;
            if (rootShell.barPosition === "bottom") return dashboardRoot.height;
            return (dashboardRoot.height - height) / 2;
        }

        HoverHandler {
            id: bridgeHover
            onHoveredChanged: {
                if (hovered) {
                    rootShell.dashboardRef.cancelDismiss();
                } else if (!dashHover.hovered) {
                    rootShell.dashboardRef.requestDismiss();
                }
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

        // 🎯 FIX 1: Main Body ON TOP with NO negative margins (Wayland handles the outer corners)
        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            anchors.leftMargin: rootShell.barPosition === "left" ? -2 : 0
            anchors.rightMargin: rootShell.barPosition === "right" ? -2 : 0
            anchors.topMargin: rootShell.barPosition === "top" ? -2 : 0
            anchors.bottomMargin: rootShell.barPosition === "bottom" ? -2 : 0
            color: rootShell.colorBackground
            border.width: 0 
            z: 3 
            
            topLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "top") ? 0 : dashboardRoot.radiusValue
            topRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "top") ? 0 : dashboardRoot.radiusValue
            bottomLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "bottom") ? 0 : dashboardRoot.radiusValue
            bottomRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "bottom") ? 0 : dashboardRoot.radiusValue
        }

        // 🎯 FIX 2: Wings underneath (Z:2), no rotation, tucked 1px inside the main body
        Item {
            anchors.fill: parent
            z: 2 
            visible: dashboardRoot.width > 30

            // --- Vertical Wings ---
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"

                // Top Wing (Tucked DOWN 1px) - Bite at Top-Left
                Item { 
                    rotation: 90
                    x: 0; y: -dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 3); y: -(dashboardRoot.wingSize * 3) 
                    }
                }

                // Bottom Wing (Tucked UP 1px) - Bite at Bottom-Left
                Item { 
                    rotation: -90
                    x: 0; y: parent.height
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 3); y: -(dashboardRoot.wingSize * 2) 
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                // Top Wing (Tucked DOWN 1px) - Bite at Top-Right
                Item { 
                    rotation: -90
                    x: parent.width - dashboardRoot.wingSize; y: -dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 2); y: -(dashboardRoot.wingSize * 3) 
                    }
                }

                // Bottom Wing (Tucked UP 1px) - Bite at Bottom-Right
                Item { 
                    rotation: 90
                    x: parent.width - dashboardRoot.wingSize; y: parent.height
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 2); y: -(dashboardRoot.wingSize * 2) 
                    }
                }
            }

            // --- Horizontal Wings ---
            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                // Left Wing (Tucked RIGHT 1px) - Bite at Top-Left
                Item { 
                    rotation: -90
                    x: -dashboardRoot.wingSize; y: 0
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 3); y: -(dashboardRoot.wingSize * 3) 
                    }
                }

                // Right Wing (Tucked LEFT 1px) - Bite at Top-Right
                Item { 
                    rotation: 90
                    x: parent.width; y: 0
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 2); y: -(dashboardRoot.wingSize * 3) 
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"

                // Left Wing (Tucked RIGHT 1px) - Bite at Bottom-Left
                Item { 
                    rotation: 90
                    x: -dashboardRoot.wingSize; y: parent.height - dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 3); y: -(dashboardRoot.wingSize * 2) 
                    }
                }

                // Right Wing (Tucked LEFT 1px) - Bite at Bottom-Right
                Item { 
                    rotation: -90
                    x: parent.width; y: parent.height - dashboardRoot.wingSize
                    width: dashboardRoot.wingSize; height: dashboardRoot.wingSize; clip: true
                    Rectangle {
                        width: dashboardRoot.wingSize * 6; height: dashboardRoot.wingSize * 6; radius: dashboardRoot.wingSize * 3
                        color: "transparent"; border.color: rootShell.colorBackground; border.width: dashboardRoot.wingSize * 2
                        x: -(dashboardRoot.wingSize * 2); y: -(dashboardRoot.wingSize * 2) 
                    }
                }
            }
        }

        Item {
            id: layoutContentWrapper
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            z: 5

            ColumnLayout {
                id: mainColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 16

                GridLayout {
                    Layout.fillWidth: true
                    columns: dashboardRoot.isHorizontal ? 2 : 1
                    rowSpacing: 24
                    columnSpacing: 16

                    ColumnLayout {
                        Layout.alignment: dashboardRoot.isHorizontal ? (Qt.AlignVCenter | Qt.AlignLeft) : Qt.AlignHCenter
                        Layout.fillWidth: true 
                        spacing: 4

                        RowLayout {
                            spacing: 16
                            
                            Text { 
                                text: Qt.formatDateTime(rootShell.clockRef.currentTime, "h:mm AP")
                                font.family: rootShell.shellFont
                                font.pixelSize: 48
                                font.bold: true
                                color: rootShell.colorText 
                            }
                            
                            ColumnLayout {
                                spacing: -4
                                Layout.alignment: Qt.AlignVCenter
                                
                                Text { 
                                    text: Qt.formatDateTime(rootShell.clockRef.currentTime, "dddd")
                                    font.family: rootShell.shellFont
                                    font.pixelSize: 22
                                    font.bold: true
                                    color: rootShell.colorText
                                }
                                Text { 
                                    text: Qt.formatDateTime(rootShell.clockRef.currentTime, "MMMM d")
                                    font.family: rootShell.shellFont
                                    font.pixelSize: 16
                                    color: rootShell.colorSubtext
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            
                            Text { text: dashboardRoot.weatherGlyph; font.family: "Material Symbols Outlined"; font.pixelSize: 20; color: rootShell.colorAccent }
                            Text { text: dashboardRoot.weatherDesc; font.family: rootShell.shellFont; font.pixelSize: 13; font.bold: true; color: rootShell.colorText }
                            Text { text: "•  Feels like " + dashboardRoot.weatherFeelsLike; font.family: rootShell.shellFont; font.pixelSize: 13; color: rootShell.colorSubtext }
                            Text { text: dashboardRoot.weatherTemp; font.family: rootShell.shellFont; font.pixelSize: 15; font.bold: true; color: rootShell.colorText }
                        }
                    }

                    RowLayout {
                        Layout.alignment: dashboardRoot.isHorizontal ? (Qt.AlignVCenter | Qt.AlignRight) : Qt.AlignHCenter
                        Layout.minimumWidth: implicitWidth 
                        spacing: 16

                        SysRing { label: "CPU"; value: dashboardRoot.sysCpu; ringColor: "#89b4fa" }
                        SysRing { label: "GPU"; value: dashboardRoot.sysGpu; ringColor: "#cba6f7" }
                        SysRing { label: "RAM"; value: dashboardRoot.sysRam; ringColor: "#a6e3a1" }
                        SysRing { label: "DISK"; value: dashboardRoot.sysDisk; ringColor: "#f38ba8" }
                    }
                }

                GridLayout {
                    columns: dashboardRoot.isHorizontal ? 4 : 2
                    rowSpacing: 12
                    columnSpacing: 12
                    Layout.fillWidth: true

                    ToggleSwitch {
                        Layout.fillWidth: true
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
                        Layout.fillWidth: true
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
                        Layout.fillWidth: true
                        label: "Focus"
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
                        Layout.fillWidth: true
                        label: "Caffeine"
                        iconName: "local_cafe"
                        checked: dashboardRoot.caffeineActive
                        onToggled: {
                            dashboardRoot.caffeineActive = !dashboardRoot.caffeineActive
                            caffeineToggleProc.command = dashboardRoot.caffeineActive 
                                ? ["pkill", "-x", "hypridle"]
                                : ["hyprctl", "dispatch", "hl.dsp.exec_cmd('hypridle')"];
                            caffeineToggleProc.running = true
                        }
                    }
                }

                Item {
                    id: utilitiesWrapper
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    clip: true 

                    property bool menuExpanded: false
                    onVisibleChanged: { if (!visible) menuExpanded = false; }

                    RowLayout {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width
                        spacing: 12

                        x: utilitiesWrapper.menuExpanded ? -parent.width - 16 : 0
                        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        // 1. Settings Button (First from left)
                        Rectangle { 
                            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                            color: actionHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: actionHover }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.requestDismiss(); rootShell.settingsAppRef.windowVisible = true; } }
                            Text { anchors.centerIn: parent; text: "settings"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 } 
                        }

                        // 2. Wallpaper Picker Button (Second from left)
                        Rectangle { 
                            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                            color: wallpaperHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: wallpaperHover }
                            MouseArea { 
                                anchors.fill: parent; 
                                cursorShape: Qt.PointingHandCursor; 
                                onClicked: { 
                                    rootShell.dashboardRef.requestDismiss(); 
                                    rootShell.wallpaperRef.active = true; // Fixed reference and property name
                                } 
                            }
                            Text { anchors.centerIn: parent; text: "wallpaper"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 } 
                        }

                        // 3. App Launcher Button
                        Rectangle { 
                            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                            color: launcherHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: launcherHover }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.requestDismiss(); rootShell.launcherRef.active = !rootShell.launcherRef.active; } }
                            Text { anchors.centerIn: parent; text: "apps"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 } 
                        }

                        // 4. Satty Screenshot Tool Button
                        Rectangle { 
                            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                            color: snipHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: snipHover }
                            MouseArea { 
                                anchors.fill: parent; 
                                cursorShape: Qt.PointingHandCursor; 
                                onClicked: { 
                                    rootShell.dashboardRef.forceDismiss();
                                    Quickshell.execDetached(["bash", "-c", "sleep 0.1 && grim -g \"$(slurp)\" -t ppm - | satty --filename -"]);
                                } 
                            }
                            Text { anchors.centerIn: parent; text: "screenshot_region"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 } 
                        }

                        // 5. Power Action Button (Far right slot)
                        Rectangle { 
                            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                            color: powerHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: powerHover }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: utilitiesWrapper.menuExpanded = true }
                            Text { anchors.centerIn: parent; text: "power_settings_new"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 } 
                        }
                    }

                    Item {
                        id: slideOverlay
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width
                        
                        x: utilitiesWrapper.menuExpanded ? 0 : parent.width + 16
                        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                                color: backHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                HoverHandler { id: backHover }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: utilitiesWrapper.menuExpanded = false }
                                Text { anchors.centerIn: parent; text: "arrow_back"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                                color: suspHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                HoverHandler { id: suspHover }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.forceDismiss(); Quickshell.execDetached(["systemctl", "suspend"]); } }
                                Text { anchors.centerIn: parent; text: "bedtime"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                                color: logoutHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                HoverHandler { id: logoutHover }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.forceDismiss(); Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]); } }
                                Text { anchors.centerIn: parent; text: "logout"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                                color: rebootHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                HoverHandler { id: rebootHover }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.forceDismiss(); Quickshell.execDetached(["systemctl", "reboot"]); } }
                                Text { anchors.centerIn: parent; text: "restart_alt"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 30
                                color: powerOffHover.hovered ? Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.25) : Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                HoverHandler { id: powerOffHover }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { rootShell.dashboardRef.forceDismiss(); Quickshell.execDetached(["systemctl", "poweroff"]); } }
                                Text { anchors.centerIn: parent; text: "power_settings_new"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 26 }
                            }
                        }
                    }
                }

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
                            iconHigh: ""
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

                GridLayout {
                    Layout.fillWidth: true
                    
                    columns: dashboardRoot.isHorizontal ? 2 : 1
                    rowSpacing: 16
                    columnSpacing: 16

                    MediaControl {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0     
                        Layout.preferredWidth: 0   
                        Layout.alignment: Qt.AlignVCenter 
                        
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

                    NotificationCenter {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0     
                        Layout.preferredWidth: 0   
                        Layout.alignment: Qt.AlignTop
                        Layout.fillHeight: dashboardRoot.isHorizontal
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
