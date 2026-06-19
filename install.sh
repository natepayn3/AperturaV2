#!/usr/bin/env bash
set -e

echo "🚀 Bootstrapping AperturaV2..."

# Detect active AUR helper
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    echo "❌ Neither yay nor paru found. Please install an AUR helper."
    exit 1
fi

# Define core repository dependencies
OFFICIAL_PKGS=(
    "qt6-wayland"
    "qt6-declarative"
    "qt6-svg"
    "pipewire"
    "wireplumber"
    "bluez"
    "bluez-utils"
    "playerctl"
    "satty"
    "grim"
    "slurp"
    "socat"
    "jq"
)

AUR_PKGS=(
    "quickshell-git"
    "ttf-material-symbols-variable-git"
)

# Install official packages via pacman
echo "📦 Installing official dependencies..."
sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}"

# Install custom shell and icon fonts via AUR
echo "📦 Installing AUR dependencies..."
$AUR_HELPER -S --needed --noconfirm "${AUR_PKGS[@]}"

# Enable and start required hardware daemons
echo "⚙️ Configuring services..."
sudo systemctl enable --now bluetooth.service
systemctl --user enable --now pipewire.socket
systemctl --user enable --now wireplumber.service
systemctl --user enable --now playerctld.service

# Deploy the configuration to the default Quickshell directory
CONFIG_DIR="$HOME/.config/quickshell"
echo "📂 Deploying shell files to $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR"
cp -r ./* "$CONFIG_DIR/"

# Inject Hyprland layer and window rules using a standard multiline string
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
echo "⚙️ Injecting QuickShell & Satty rules into $HYPR_LUA..."

# Ensure the directory exists before appending
mkdir -p "$(dirname "$HYPR_LUA")"

echo '
-- AperturaV2 Rules
-- Combined rule handles all quickshell layer panels (Bar, Settings HUD, etc.)
hl.layer_rule({
    name         = "quickshell-all",
    match        = { namespace = "^quickshell-.*" },
    blur         = true,
    xray         = true,
    ignore_alpha = 0.7, -- 🧪 Background blur masks to your sharp QML card shape automatically!
})

-- Satty always floats
hl.window_rule({
    name  = "satty-screenshot-floating",
    match = { class = "com.gabm.satty" },
    float = true,
})' >> "$HYPR_LUA"

echo "✅ Installation complete! Launch via 'quickshell' or bind it in your hyprland config."
