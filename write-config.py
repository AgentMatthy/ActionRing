#!/usr/bin/env python3
"""Write ActionRing config back to disk.

Reads a JSON document from stdin (the *full* desired config, or a partial
patch when --merge is given) and writes it to ~/.config/ActionRing/config.jsonc
as clean, human-readable JSON.

Comments from the original JSONC cannot be perfectly round-tripped, so the
on-disk file is rewritten as ordered, indented JSON. A timestamped backup of
the previous file is kept as config.jsonc.bak so nothing is ever lost.

Usage:
    echo '<json>' | write-config.py            # replace whole config
    echo '<json>' | write-config.py --merge     # merge into existing config
"""
import json
import os
import re
import shutil
import sys

CONFIG_DIR = os.path.expanduser('~/.config/ActionRing')
CONFIG_PATH = os.path.join(CONFIG_DIR, 'config.jsonc')
BACKUP_PATH = os.path.join(CONFIG_DIR, 'config.jsonc.bak')

# Preferred key order so the rewritten file stays readable and predictable.
KEY_ORDER = [
    'installPath',
    'hapticOpen', 'hapticHover', 'hapticSelect', 'hapticClose', 'hapticSubmenu',
    'menuRadius', 'circleSize', 'submenuPullDistance', 'repeatPullDistance',
    'itemColor', 'itemHoverColor', 'iconColor',
    'items', 'submenus',
]


def parse_jsonc(text):
    """Remove // comments from JSONC, respecting string literals."""
    result = []
    in_string = False
    i = 0
    while i < len(text):
        c = text[i]
        if c == '"' and (i == 0 or text[i - 1] != '\\'):
            in_string = not in_string
        if not in_string and i + 1 < len(text) and text[i:i + 2] == '//':
            while i < len(text) and text[i] != '\n':
                i += 1
            continue
        result.append(c)
        i += 1
    cleaned = ''.join(result)
    cleaned = re.sub(r',(\s*[}\]])', r'\1', cleaned)
    return cleaned


def load_existing():
    if not os.path.exists(CONFIG_PATH):
        return {}
    try:
        with open(CONFIG_PATH) as f:
            return json.loads(parse_jsonc(f.read()))
    except Exception:
        return {}


def ordered(cfg):
    """Return an ordered dict following KEY_ORDER, with any extras appended."""
    out = {}
    for key in KEY_ORDER:
        if key in cfg:
            out[key] = cfg[key]
    for key in cfg:
        if key not in out:
            out[key] = cfg[key]
    return out


def main():
    merge = '--merge' in sys.argv[1:]

    raw = sys.stdin.read()
    try:
        incoming = json.loads(raw)
    except Exception as e:
        print(f'write-config: invalid JSON on stdin: {e}', file=sys.stderr)
        sys.exit(1)

    if merge:
        cfg = load_existing()
        cfg.update(incoming)
    else:
        cfg = incoming

    cfg = ordered(cfg)

    os.makedirs(CONFIG_DIR, exist_ok=True)

    # Keep a backup of the previous file.
    if os.path.exists(CONFIG_PATH):
        try:
            shutil.copy2(CONFIG_PATH, BACKUP_PATH)
        except Exception:
            pass

    text = json.dumps(cfg, indent=4, ensure_ascii=False)
    with open(CONFIG_PATH, 'w') as f:
        f.write(text + '\n')

    print('ok')


if __name__ == '__main__':
    main()
