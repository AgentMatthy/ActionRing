#!/bin/bash
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

info()  { echo -e "${CYAN}::${RESET} $1"; }
ok()    { echo -e "${GREEN}✓${RESET} $1"; }
warn()  { echo -e "${YELLOW}!${RESET} $1"; }
err()   { echo -e "${RED}✗${RESET} $1"; }
step()  { echo -e "\n${BOLD}$1${RESET}"; }

# ─── Header ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  ActionRing Installer${RESET}"
echo -e "${DIM}  Radial action menu for Hyprland + MX Master 4${RESET}"
echo ""

# ─── Preflight ───────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    err "git is not installed. Please install git and try again."
    exit 1
fi

# ─── Install location ───────────────────────────────────────────────
DEFAULT_DIR="$HOME/.local/share/ActionRing"

step "Where should ActionRing be installed?"
echo -e "  ${DIM}default: ${DEFAULT_DIR}${RESET}"
printf "  > "
read -r INSTALL_DIR </dev/tty || INSTALL_DIR=""
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"

# Expand ~ if the user typed it
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

if [ -d "$INSTALL_DIR/.git" ]; then
    warn "ActionRing is already installed at ${BOLD}$INSTALL_DIR${RESET}"
    printf "  Reinstall? [y/N] "
    read -r CONFIRM </dev/tty || CONFIRM=""
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi
    rm -rf "$INSTALL_DIR"
elif [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    err "$INSTALL_DIR exists and is not empty."
    exit 1
fi

# ─── Clone ───────────────────────────────────────────────────────────
step "Cloning ActionRing..."
mkdir -p "$(dirname "$INSTALL_DIR")"
git clone https://github.com/AgentMatthy/ActionRing.git "$INSTALL_DIR" 2>&1 | while read -r line; do
    echo -e "  ${DIM}${line}${RESET}"
done
ok "Cloned to ${BOLD}$INSTALL_DIR${RESET}"

# ─── Config file ─────────────────────────────────────────────────────
step "Setting up config..."
CONFIG_DIR="$HOME/.config/ActionRing"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
{
    // Path to the ActionRing installation directory
    "installPath": "$INSTALL_DIR"
}
EOF
ok "Created ${BOLD}$CONFIG_FILE${RESET}"

# ─── Make scripts executable ─────────────────────────────────────────
chmod +x "$INSTALL_DIR/actionmenu-ctl"
chmod +x "$INSTALL_DIR/mx4haptic-daemon.py"
chmod +x "$INSTALL_DIR/mx4haptic.py"
ok "Made scripts executable"

# ─── Done ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ✓ ActionRing installed!${RESET}"
echo ""

# ─── Next steps ───────────────────────────────────────────────────────
step "Next steps:"
echo ""

echo -e "  ${BOLD}1. Install dependencies${RESET}"
echo -e "     Make sure ${CYAN}QuickShell${RESET} and ${CYAN}Hyprland${RESET} are installed."
echo -e "     Install ${CYAN}Symbols Nerd Font${RESET} for menu icons: ${DIM}https://www.nerdfonts.com/${RESET}"
echo -e "     For haptic feedback: ${DIM}pip install hidapi${RESET}"
echo ""

echo -e "  ${BOLD}2. Set up HID permissions${RESET} ${DIM}(only for MX Master 4 haptics)${RESET}"
echo -e "     Run these commands:"
echo ""
echo -e "     ${DIM}sudo tee /etc/udev/rules.d/99-mx-master-4.rules << 'UDEV'"
echo -e "     SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"046d\", MODE=\"0666\""
echo -e "     UDEV"
echo -e "     sudo udevadm control --reload-rules && sudo udevadm trigger${RESET}"
echo ""
echo -e "     Then unplug and replug your mouse receiver."
echo ""

echo -e "  ${BOLD}3. Start ActionRing${RESET}"
echo -e "     ${DIM}# Optional: start the haptic daemon"
echo -e "     $INSTALL_DIR/mx4haptic-daemon.py --daemon &"
echo -e ""
echo -e "     # Launch the menu"
echo -e "     qs -p $INSTALL_DIR${RESET}"
echo ""

echo -e "  ${BOLD}4. Add keybindings${RESET} ${DIM}(in your hyprland.conf)${RESET}"
echo ""
echo -e "     ${DIM}# Hold to open, release to select (e.g. thumb button)"
echo -e "     bind = , mouse:276, exec, $INSTALL_DIR/actionmenu-ctl open"
echo -e "     bindrl = , mouse:276, exec, $INSTALL_DIR/actionmenu-ctl select"
echo -e ""
echo -e "     # Or toggle with a keyboard shortcut"
echo -e "     bind = SUPER, space, exec, $INSTALL_DIR/actionmenu-ctl toggle${RESET}"
echo ""

echo -e "  ${BOLD}5. Customize${RESET}"
echo -e "     Edit ${CYAN}$INSTALL_DIR/Config.qml${RESET} to change"
echo -e "     menu items, colors, layout, and haptic patterns."
echo ""
