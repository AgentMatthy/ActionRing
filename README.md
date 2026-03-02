# ActionRing

A radial action menu for Hyprland, built for the Logitech MX Master 4 — complete with haptic feedback.

Hold a button, flick toward an action, release. That's it.

---

## Features

- **Radial menu overlay** — appears at your cursor, fades in with a smooth animation
- **Submenus** — pull outward to dive into nested menus (media, display, apps, etc.)
- **Repeat actions** — hold and pump for volume, brightness, and more
- **Haptic feedback** — feel every hover, select, and menu transition through your MX Master 4
- **Fully customizable** — change icons, actions, colors, sizes, and haptic patterns
- **IPC controlled** — bind it to any key, gesture, or mouse button

---

## Requirements

| Requirement | What it's for |
|---|---|
| [Hyprland](https://hyprland.org/) | Wayland compositor (required) |
| [QuickShell](https://quickshell.outfoxxed.me/) | Runtime for the menu |
| Python 3 + `hidapi` | Haptic feedback on the MX Master 4 |
| [Symbols Nerd Font](https://www.nerdfonts.com/) | Menu icons |

> **Note:** The menu itself works on any Hyprland setup. Haptic feedback is MX Master 4-specific.

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/AgentMatthy/ActionRing.git
cd ActionRing
```

### 2. Install dependencies

Make sure [QuickShell](https://quickshell.outfoxxed.me/) and [Hyprland](https://hyprland.org/) are installed and running.

Install the Python haptic library (optional, for MX Master 4 haptic feedback):

```bash
pip install hidapi
```

Install [Symbols Nerd Font](https://www.nerdfonts.com/) for the menu icons.

### 3. Set up the path

Set the `ACTIONMENU_PATH` environment variable to point to where you cloned the repo:

```bash
export ACTIONMENU_PATH="$HOME/path/to/actionring"
```

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) so it persists.

### 4. Update haptic paths

If you want haptic feedback, open `RadialMenu.qml` and replace all occurrences of `/home/matthy/Dev/ActionMenu/` with your actual install path.

### 5. HID device permissions (for haptic feedback)

Your user needs access to the MX Master 4 HID device. Create a udev rule:

```bash
sudo tee /etc/udev/rules.d/99-mx-master-4.rules << 'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", MODE="0666"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Unplug and replug your mouse receiver for the rule to take effect.

---

## Usage

### Start the menu service

```bash
# Start the haptic daemon (optional, for MX Master 4)
./mx4haptic-daemon.py --daemon &

# Start ActionRing
qs -p /path/to/actionring
```

### Control the menu

Use `actionmenu-ctl` to open, close, and interact with the menu:

```bash
./actionmenu-ctl open      # Open the menu at your cursor
./actionmenu-ctl close     # Close without selecting
./actionmenu-ctl toggle    # Toggle open/close
./actionmenu-ctl select    # Confirm the hovered action
./actionmenu-ctl status    # Check if the menu is open
```

### Bind to your mouse or keyboard

Add keybindings in your Hyprland config (`hyprland.conf`):

```ini
# Example: bind to a mouse button (hold to open, release to select)
bind = , mouse:276, exec, /path/to/actionring/actionmenu-ctl open
bindrl = , mouse:276, exec, /path/to/actionring/actionmenu-ctl select

# Example: bind to a keyboard shortcut
bind = SUPER, space, exec, /path/to/actionring/actionmenu-ctl toggle
```

> **Tip for MX Master 4 users:** Bind the gesture button (thumb button) so you can hold it, move toward an action, and release to confirm.

---

## Customization

All customization lives in **`Config.qml`**. Open it and make it yours.

### Menu items

Each item in the menu can have:
- **`icon`** — a Nerd Font symbol
- **`action`** — a shell command to run when selected
- **`submenu`** — opens a nested menu instead of running a command
- **`repeat`** — enables pull-to-pump for repeated actions (great for volume/brightness)

### Colors

| Setting | Default | Description |
|---|---|---|
| `itemColor` | `#000000` | Circle background |
| `itemHoverColor` | `#3C3836` | Circle background on hover |
| `iconColor` | `#D5C4A1` | Icon color |

### Layout

| Setting | Default | Description |
|---|---|---|
| `menuRadius` | `90` | Distance from center to items |
| `circleSize` | `58` | Size of each item circle |

### Haptic patterns

Customize what you feel on your MX Master 4 for each interaction:

| Event | Default | Description |
|---|---|---|
| `hapticOpen` | *(none)* | Menu opens |
| `hapticHover` | `tick` | Hovering a new item |
| `hapticSelect` | `soft` | Selecting an item |
| `hapticClose` | `buzz` | Menu closes |
| `hapticSubmenu` | `bump` | Entering a submenu |

Available patterns: `click`, `soft`, `bump`, `tick`, `pulse`, `double`, `triple`, `ramp`, `buzz`, `alert`, `notify`, `success`, `error`, `warning`, `strong`

---

## How it works

1. **Open** — the menu appears as a ring of icons around your cursor
2. **Hover** — move your mouse toward an action; items highlight as you aim at them
3. **Select** — left-click or release your bound button to execute the action
4. **Submenus** — hover over a submenu item and pull outward to open it
5. **Repeat actions** — hover over a repeat item (like volume) and keep pulling outward to fire it repeatedly
6. **Cancel** — right-click or press Escape to close without doing anything


