import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtQuick.Shapes
import QtQuick.Effects
import QtMultimedia     // 🎯 Required for the Video playback
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: wallpaperWindow

    property bool active: false
    required property var rootShell

    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    exclusionMode: ExclusionMode.Ignore
    
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: active

    MouseArea {
        anchors.fill: parent
        onClicked: wallpaperWindow.active = false
    }

    FolderListModel {
        id: wallpaperModel
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
        nameFilters: ["*.jpg", "*.png", "*.gif", "*.mp4", "*.webm"]
        showDirs: false
    }

    Process {
        id: wallpaperBackend
        running: false
        property string targetFile: ""

        function apply(filePath) {
            targetFile = filePath;
            let ext = filePath.split('.').pop().toLowerCase();
            
            let sockPath = "/run/user/$(id -u)/${WAYLAND_DISPLAY:-wayland-1}-awww-daemon.sock";
            let script = "";
            
            if (ext === "mp4" || ext === "webm") {
                script = "killall -q mpvpaper; awww kill 2>/dev/null || killall -9 -q awww-daemon; rm -f " + sockPath + "; mpvpaper -vs -o 'loop no-audio' '*' '" + filePath + "'";
            } else {
                // 🎯 Added sleep for Wayland surface handoff, and nohup/disown to detach the daemon
                script = "killall -q mpvpaper; sleep 0.2; if ! pgrep -x 'awww-daemon' > /dev/null; then rm -f " + sockPath + "; nohup awww-daemon >/dev/null 2>&1 & disown; sleep 0.3; fi; awww img '" + filePath + "' --transition-type wipe --transition-step 16 --transition-duration 1";
            }
            command = ["bash", "-c", script];
            
            running = false;
            running = true;

            matugenRunner.targetFile = filePath;
            matugenRunner.running = false;
            matugenRunner.running = true;
        }
    }

    Process {
        id: matugenRunner
        running: false
        property string targetFile: ""
        command: [
            "sh", "-c", 
            "matugen image \"" + targetFile + "\" -t scheme-tonal-spot --prefer=saturation --json hex > \"" + rootShell.matugenFilePath + "\" && sync"
        ]
    }

    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: 80
        height: 450 

        ListView {
            id: carousel
            anchors.centerIn: parent
            width: parent.width - 200
            height: parent.height
            
            orientation: ListView.Horizontal
            property real cardSkew: 35
            spacing: -cardSkew + 5 

            model: wallpaperModel
            focus: true
            clip: true
            interactive: true 

            highlightRangeMode: ListView.ApplyRange
            highlightMoveDuration: 200

            property int hoveredIndex: -1

            Keys.onLeftPressed: if (currentIndex > 0) currentIndex--;
            Keys.onRightPressed: if (currentIndex < count - 1) currentIndex++;
            Keys.onEscapePressed: wallpaperWindow.active = false

            WheelHandler {
                onWheel: (event) => {
                    if (event.angleDelta.y > 0 || event.angleDelta.x > 0) {
                        carousel.currentIndex = Math.max(0, carousel.currentIndex - 1);
                    } else if (event.angleDelta.y < 0 || event.angleDelta.x < 0) {
                        carousel.currentIndex = Math.min(carousel.count - 1, carousel.currentIndex + 1);
                    }
                }
            }

            delegate: Item {
                id: delegateRoot
                height: carousel.height
                
                property bool isFocused: ListView.isCurrentItem
                property bool isActiveTarget: carousel.hoveredIndex !== -1 ? (carousel.hoveredIndex === index) : isFocused
                
                // 🎯 Expands the card width to a full 16:9 ratio, plus the necessary padding to account for the slant
                width: isActiveTarget ? (carousel.height * 0.85 * 1.77 + carousel.cardSkew) : 180 
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                z: isActiveTarget ? 10 : 1 

                property string pathStr: String(filePath).toLowerCase()
                property bool isVideo: pathStr.endsWith(".mp4") || pathStr.endsWith(".webm")
                property string fileName: String(filePath).split('/').pop()
                property string thumbDir: Quickshell.env("HOME") + "/.cache/quickshell_thumbs"
                property string thumbFile: thumbDir + "/" + fileName + ".jpg"
                property string thumbUrl: "file://" + thumbFile
                property bool thumbReady: false
                
                Process {
                    running: delegateRoot.isVideo
                    command: [
                        "bash", "-c", 
                        "mkdir -p '" + thumbDir + "' && if [ ! -f '" + thumbFile + "' ]; then ffmpeg -y -i '" + filePath + "' -ss 00:00:00.100 -vframes 1 -vf 'scale=450:-1' -q:v 2 '" + thumbFile + "' >/dev/null 2>&1; fi"
                    ]
                    onExited: delegateRoot.thumbReady = true
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor 
                    
                    onEntered: carousel.hoveredIndex = index
                    onExited: if (carousel.hoveredIndex === index) carousel.hoveredIndex = -1
                    
                    onClicked: wallpaperBackend.apply(filePath)
                }
                
                Keys.onReturnPressed: if (isFocused) wallpaperBackend.apply(filePath)

                Item {
                    anchors.centerIn: parent
                    width: parent.width 
                    height: parent.height * 0.85 
                    
                    scale: delegateRoot.isActiveTarget ? 1.05 : 0.95
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                    Item {
                        id: cardMask
                        anchors.fill: parent
                        visible: false 
                        layer.enabled: true
                        layer.smooth: true
                        
                        Shape {
                            id: slantyShape 
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            
                            property real r: 12 
                            // 🎯 Reverted the animation; this strictly enforces the permanent parallelogram shape
                            property real sk: carousel.cardSkew
                            
                            ShapePath {
                                fillColor: "white"
                                strokeColor: "transparent"
                                startX: slantyShape.sk + slantyShape.r; startY: 0
                                PathLine { x: slantyShape.width - slantyShape.r; y: 0 }
                                PathQuad { x: slantyShape.width - (slantyShape.r * 0.2); y: slantyShape.r; controlX: slantyShape.width; controlY: 0 }
                                PathLine { x: slantyShape.width - slantyShape.sk + (slantyShape.r * 0.2); y: slantyShape.height - slantyShape.r }
                                PathQuad { x: slantyShape.width - slantyShape.sk - slantyShape.r; y: slantyShape.height; controlX: slantyShape.width - slantyShape.sk; controlY: slantyShape.height }
                                PathLine { x: slantyShape.r; y: slantyShape.height }
                                PathQuad { x: (slantyShape.r * 0.2); y: slantyShape.height - slantyShape.r; controlX: 0; controlY: slantyShape.height }
                                PathLine { x: slantyShape.sk - (slantyShape.r * 0.2); y: slantyShape.r }
                                PathQuad { x: slantyShape.sk + slantyShape.r; y: 0; controlX: slantyShape.sk; controlY: 0 }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        
                        Image {
                            anchors.fill: parent
                            source: delegateRoot.isVideo ? (delegateRoot.thumbReady ? delegateRoot.thumbUrl : "") : fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true 
                            sourceSize: Qt.size(450, 450) 
                            cache: true
                        }

                        Loader {
                            anchors.fill: parent
                            active: delegateRoot.isVideo && delegateRoot.isActiveTarget
                            sourceComponent: Component {
                                Video {
                                    anchors.fill: parent
                                    source: fileUrl
                                    fillMode: VideoOutput.PreserveAspectCrop
                                    loops: MediaPlayer.Infinite
                                    muted: true
                                    Component.onCompleted: play()
                                }
                            }
                        }

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: cardMask
                            maskThresholdMin: 0.3 
                            maskSpreadAtMin: 0.3
                        }
                    }
                }
            }
        }
    }
}
