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

### Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/AgentMatthy/ActionRing/main/install.sh | bash
```

This will clone the repo, set up the config file, and print the remaining steps.

### Manual installation

#### 1. Clone the repo

```bash
git clone https://github.com/AgentMatthy/ActionRing.git
cd ActionRing
```

#### 2. Install dependencies

Make sure [QuickShell](https://quickshell.outfoxxed.me/) and [Hyprland](https://hyprland.org/) are installed and running.

Install the Python haptic library (optional, for MX Master 4 haptic feedback):

```bash
pip install hidapi
```

Install [Symbols Nerd Font](https://www.nerdfonts.com/) for the menu icons.

#### 3. Set up the config file

Create the configuration directory and file:

```bash
mkdir -p ~/.config/ActionRing
cp config.jsonc.example ~/.config/ActionRing/config.jsonc
```

Edit `~/.config/ActionRing/config.jsonc` and set `installPath` to where you cloned the repo.
The config file contains all settings: menu items, submenus, colors, layout, and haptic patterns.

> **Note:** If you skip this step, ActionRing will try to auto-detect its install location, but you won't have any menu items configured.

#### 4. HID device permissions (for haptic feedback)

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
./actionmenu-ctl config    # Open the configuration GUI
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

### Configuration GUI

The fastest way to shape your ring is the built-in editor:

```bash
./actionmenu-ctl config     # or bind it to a key
```

A floating panel lets you, without touching a config file:

- **Switch menus** — jump between the main ring and any submenu, or create/delete submenus
- **Add & remove entries** — build out each ring slot, reorder with the up/down arrows
- **Set the entry type** — `Command`, `Submenu`, `Exit Submenu`, or `Empty` (spacer)
- **Set the icon** — paste any Nerd Font glyph; a live preview shows how it looks
- **Set the command** — for command entries, with a roomy multi-line field
- **Toggle repeated action** — flip a switch to enable pull-to-pump for volume/brightness-style actions

Hit **Save** and the running menu hot-reloads instantly — no restart required. Your previous
config is backed up to `config.jsonc.bak` on every save.

> **Note:** Saving rewrites `config.jsonc` as clean, indented JSON. Comments in the file are not
> preserved across a GUI save, but every setting (colors, sizes, haptics) is kept intact.

You can bind it in Hyprland just like the menu:

```ini
bind = SUPER, period, exec, /path/to/actionring/actionmenu-ctl config
```

### Manual editing

All customization also lives in **`~/.config/ActionRing/config.jsonc`**. Open it and make it yours.

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


