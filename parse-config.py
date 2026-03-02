#!/usr/bin/env python3
"""Parse ActionRing JSONC config and output clean JSON to stdout."""
import re, json, os, sys

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
    # Remove trailing commas before } or ]
    cleaned = re.sub(r',(\s*[}\]])', r'\1', cleaned)
    return cleaned

config_path = os.path.expanduser('~/.config/ActionRing/config.jsonc')
if not os.path.exists(config_path):
    print('{}')
    sys.exit(0)

with open(config_path) as f:
    raw = f.read()

try:
    parsed = json.loads(parse_jsonc(raw))
    print(json.dumps(parsed))
except Exception as e:
    print(f'ActionRing: config parse error: {e}', file=sys.stderr)
    print('{}')
