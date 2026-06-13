import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: previewRoot

    property int targetWorkspace: -1
    property bool active: targetWorkspace !== -1
    property var liveClientJson: []

    property int currentActiveWorkspace: -1

    property real radiusValue: 12
    property real wingSize: 14

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real maxCardWidth: viewportFrame.width + 28
    property real maxCardHeight: viewportFrame.calculatedBounds.isVertical ? 380 : 200

    width: Math.round(maxCardWidth * rootShell.previewProgress)
    height: Math.round(maxCardHeight * rootShell.previewProgress)
    opacity: rootShell.previewProgress
    clip: false

    x: rootShell.barPosition === "right" ? hoverOriginX + (maxCardWidth - width) : hoverOriginX
    y: hoverOriginY

    onTargetWorkspaceChanged: {
        if (targetWorkspace !== -1) {
            clientQueryProcess.running = true;
        } else {
            liveClientJson = [];
            currentActiveWorkspace = -1;
        }
    }

    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) { if (previewRoot.active) clientQueryProcess.running = true; }
    }

    Process {
        id: clientQueryProcess
        command: ["hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanText = text.trim();
                if (!cleanText || cleanText === "[]") return;
                try { previewRoot.liveClientJson = JSON.parse(cleanText); } catch(e) {}
            }
        }
    }

    Process { id: switchWorkspace; running: false }

    function getCleanIconName(className) {
        if (!className) return "application-x-executable";
        let lowerClass = className.toLowerCase().trim();
        if (lowerClass.includes("chrome")) return "google-chrome";
        if (lowerClass.includes("kitty")) return "kitty";
        if (lowerClass.includes("terminal")) return "utilities-terminal";
        if (lowerClass.includes("codium")) return "vscodium";
        if (lowerClass.includes("code")) return "vscode";
        if (lowerClass.includes("signal")) return "signal-desktop";
        return lowerClass;
    }

    // Main Card Body Background Plate
    Rectangle {
        id: cardMainBody
        anchors.fill: parent
        color: rootShell.colorBackground
        z: 2
        
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "bottom") ? previewRoot.radiusValue : 0
        bottomRightRadius: (rootShell.barPosition === "top" || rootShell.barPosition === "left") ? previewRoot.radiusValue : 0
    }

    // Fixed: A dedicated container layer that clips out everything outside the strict window boundary
    Item {
        id: borderClippingMask
        anchors.fill: parent
        clip: rootShell.barPosition === "right" // Only clip when right-aligned to protect other modes
        z: 3

        Rectangle {
            id: borderFrame
            // Expands the canvas width out to the right so the stroke loop draws outside the clipping viewport
            width: rootShell.barPosition === "right" ? parent.width + 4 : parent.width
            height: parent.height
            color: "transparent"
            border.color: rootShell.colorBorder
            border.width: 2

            // Retains perfect native hardware anti-aliasing curves
            topLeftRadius: cardMainBody.topLeftRadius
            topRightRadius: cardMainBody.topRightRadius
            bottomLeftRadius: cardMainBody.bottomLeftRadius
            bottomRightRadius: cardMainBody.bottomRightRadius

            // Internal sub-pixel masks erase overlapping stroke lines cleanly on contacting panels
            Rectangle { visible: rootShell.barPosition === "top"; x: 0; y: 0; width: parent.width; height: 2; color: rootShell.colorBackground }
            Rectangle { visible: rootShell.barPosition === "top" || rootShell.barPosition === "left"; x: 0; y: 0; width: 2; height: parent.height; color: rootShell.colorBackground }
            Rectangle { visible: rootShell.barPosition === "bottom"; x: 0; y: parent.height - 2; width: parent.width; height: 2; color: rootShell.colorBackground }
            Rectangle { visible: rootShell.barPosition === "right"; x: parent.width - 2; y: 0; width: 2; height: parent.height; color: rootShell.colorBackground }
        }
    }

    // Explicit Orientation Wing Blocks (Renders exclusively matching active panel geometry channels)
    Item {
        anchors.fill: parent
        visible: previewRoot.width > 30
        z: 1 

        // TOP ORIENTATION WINGS
        Item {
            anchors.fill: parent
            visible: rootShell.barPosition === "top"

            Shape {
                x: 0; y: parent.height - 2
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: 0
                    PathLine { x: previewRoot.wingSize; y: 0 }
                    PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
            Shape {
                x: parent.width - 2; y: 0
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: 0
                    PathLine { x: 0; y: previewRoot.wingSize }
                    PathQuad { x: previewRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }

        // LEFT ORIENTATION WINGS
        Item {
            anchors.fill: parent
            visible: rootShell.barPosition === "left"

            Shape {
                x: 0; y: parent.height - 2
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: 0
                    PathLine { x: previewRoot.wingSize; y: 0 }
                    PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
            Shape {
                x: parent.width - 2; y: 0
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: 0
                    PathLine { x: 0; y: previewRoot.wingSize }
                    PathQuad { x: previewRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }

        // BOTTOM ORIENTATION WINGS
        Item {
            anchors.fill: parent
            visible: rootShell.barPosition === "bottom"

            Shape {
                x: 0; y: -previewRoot.wingSize + 2
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: previewRoot.wingSize
                    PathLine { x: previewRoot.wingSize; y: previewRoot.wingSize }
                    PathQuad { x: 0; y: 0; controlX: 0; controlY: previewRoot.wingSize }
                    PathLine { x: 0; y: previewRoot.wingSize }
                }
            }
            Shape {
                x: parent.width - 2; y: parent.height - previewRoot.wingSize
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: 0; startY: 0
                    PathLine { x: previewRoot.wingSize; y: 0 }
                    PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }

        // RIGHT ORIENTATION WINGS
        Item {
            anchors.fill: parent
            visible: rootShell.barPosition === "right"

            Shape {
                x: -previewRoot.wingSize + 2; y: 0
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: previewRoot.wingSize; startY: 0
                    PathLine { x: previewRoot.wingSize; y: previewRoot.wingSize }
                    PathQuad { x: 0; y: 0; controlX: previewRoot.wingSize; controlY: 0 }
                    PathLine { x: previewRoot.wingSize; y: 0 }
                }
            }
            
            Shape {
                x: parent.width - previewRoot.wingSize; y: parent.height - 2
                width: previewRoot.wingSize; height: previewRoot.wingSize
                ShapePath {
                    fillColor: rootShell.colorBackground; strokeColor: rootShell.colorBorder; strokeWidth: 2
                    startX: previewRoot.wingSize; startY: 0
                    PathLine { x: previewRoot.wingSize; y: previewRoot.wingSize }
                    PathQuad { x: 0; y: 0; controlX: previewRoot.wingSize; controlY: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }
    }

    MouseArea { 
        anchors.fill: parent 
        hoverEnabled: true 
        acceptedButtons: Qt.NoButton
        z: 4
    }

    Item {
        id: layoutContentWrapper
        width: Math.round(previewRoot.maxCardWidth)
        height: Math.round(previewRoot.maxCardHeight)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        opacity: rootShell.previewProgress > 0.6 ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 60 } }
        z: 5

        Item {
            anchors.fill: parent
            anchors.margins: 14

            Text {
                id: titleLabel
                text: "Workspace " + previewRoot.targetWorkspace
                font.family: rootShell.shellFont
                font.pixelSize: 13
                font.bold: true
                color: rootShell.colorAccent
                x: 0; y: 0
            }

            RowLayout {
                x: titleLabel.x + titleLabel.implicitWidth + 24
                y: 2; height: titleLabel.implicitHeight; spacing: 8
                
                Repeater {
                    model: viewportFrame.workspaceWindows
                    delegate: Image {
                        visible: (modelData.class || "") !== "" && modelData.mapped
                        source: Quickshell.iconPath(getCleanIconName(modelData.class))
                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }

            Rectangle {
                id: headerDivider
                width: parent.width - 4; height: 1
                color: rootShell.colorBorder
                x: 0; y: 20
            }

            Rectangle {
                id: viewportFrame
                x: 0; anchors.top: headerDivider.bottom; anchors.topMargin: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                color: Qt.rgba(0, 0, 0, 0.2); radius: 4; clip: true

                property var workspaceWindows: previewRoot.liveClientJson.filter(w => w.workspace.id === previewRoot.targetWorkspace)

                property var calculatedBounds: {
                    if (!workspaceWindows || workspaceWindows.length === 0) {
                        return { "w": 1920, "h": 1080, "isVertical": false, "originX": 0, "originY": 0 };
                    }
                    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                    for (let i = 0; i < workspaceWindows.length; i++) {
                        let win = workspaceWindows[i];
                        if (!win.at || !win.size) continue;
                        if (win.at[0] < minX) minX = win.at[0];
                        if (win.at[1] < minY) minY = win.at[1];
                        if ((win.at[0] + win.size[0]) > maxX) maxX = win.at[0] + win.size[0];
                        if ((win.at[1] + win.size[1]) > maxY) maxY = win.at[1] + win.size[1];
                    }
                    let spanX = maxX - minX, spanY = maxY - minY;
                    let verticalDetected = spanY > spanX;
                    let normW = verticalDetected ? 1080 : 1920;
                    let normH = verticalDetected ? 1920 : 1080;
                    if (spanX > 0 && Math.abs(spanX - normW) > 100) normW = spanX;
                    if (spanY > 0 && Math.abs(spanY - normH) > 100) normH = spanY;
                    return { "w": normW, "h": normH, "isVertical": verticalDetected, "originX": minX, "originY": minY };
                }

                width: Math.round(height * (calculatedBounds.w / calculatedBounds.h))
                property real scaleX: width / calculatedBounds.w
                property real scaleY: height / calculatedBounds.h

                Repeater {
                    model: viewportFrame.workspaceWindows
                    delegate: Rectangle {
                        id: windowDelegate
                        x: Math.round((modelData.at[0] - viewportFrame.calculatedBounds.originX) * viewportFrame.scaleX)
                        y: Math.round((modelData.at[1] - viewportFrame.calculatedBounds.originY) * viewportFrame.scaleY)
                        width: Math.max(4, Math.round(modelData.size[0] * viewportFrame.scaleX))
                        height: Math.max(4, Math.round(modelData.size[1] * viewportFrame.scaleY))
                        visible: modelData.mapped
                        color: Qt.rgba(0, 0, 0, 0.6)
                        border.color: rootShell.colorBorder; border.width: 1; radius: 2; clip: true

                        property var wlToplevel: {
                            if (!modelData || !modelData.address) return null;
                            let targetAddr = modelData.address.trim().toLowerCase();
                            let match = Hyprland.toplevels.values.find(t => t.lastIpcObject && t.lastIpcObject.address && t.lastIpcObject.address.trim().toLowerCase() === targetAddr);
                            return match ? match.wayland : null;
                        }

                        Loader {
                            anchors.fill: parent
                            active: windowDelegate.wlToplevel !== null
                            sourceComponent: ScreencopyView {
                                captureSource: windowDelegate.wlToplevel
                                live: true; paintCursor: false
                            }
                        }

                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: Math.min(14, parent.height * 0.25)
                            color: "#cc11111b"
                            visible: parent.height > 20 && parent.width > 35; z: 10

                            Text {
                                text: (modelData.title && modelData.title.trim() !== "" && modelData.title !== "~") ? modelData.title : (modelData.class || "")
                                font.family: rootShell.shellFont; font.pixelSize: 8; font.bold: true; color: "#ffffff"
                                anchors.centerIn: parent; width: parent.width - 4; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
