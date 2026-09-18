#!/usr/bin/env python3
"""Generate the shared, pinned Unicode reaction catalog. No network at build time."""
import argparse
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'resources/emoji/emoji-test-17.0.txt'
OUTPUTS = [ROOT / 'services/supabase/functions/_shared/emojiCatalog.json',
           ROOT / 'apps/ios/Merian/Resources/ExploreEmojiCatalog.json']

def catalog():
    entries = []
    by_sequence = {}
    group = ''
    for line in SOURCE.read_text().splitlines():
        if line.startswith('# group: '):
            group = line.removeprefix('# group: ')
        if not line or line.startswith('#'):
            continue
        codes, rest = line.split(';', 1)
        status, description = rest.split('#', 1)
        emoji = ''.join(chr(int(code, 16)) for code in codes.split())
        # FE0F qualification aliases preserve ZWJ, gender, and skin-tone identity.
        key = emoji.replace('\ufe0f', '')
        if status.strip() == 'fully-qualified':
            name = description.strip().split(' ', 2)[2]
            entry = {'emoji': emoji, 'name': name, 'category': group,
                     'keywords': name.replace(':', ' ').replace('-', ' '),
                     'aliases': [emoji], 'order': len(entries)}
            entries.append(entry)
            by_sequence[key] = entry
        elif status.strip() in ('minimally-qualified', 'unqualified'):
            by_sequence[key]['aliases'].append(emoji)
    keywords = {}
    for path in [ROOT / 'resources/emoji/cldr-48-en.xml', ROOT / 'resources/emoji/cldr-48-en-derived.xml']:
        for annotation in ET.parse(path).iter('annotation'):
            if annotation.get('type') != 'tts' and annotation.text:
                keywords[annotation.get('cp', '').replace('\ufe0f', '')] = annotation.text
    for entry in entries:
        entry['keywords'] += ' ' + keywords.get(entry['emoji'].replace('\ufe0f', ''), '')
    return {'version': '17.0', 'entries': entries}

def main():
    args = argparse.ArgumentParser()
    args.add_argument('--check', action='store_true')
    options = args.parse_args()
    content = json.dumps(catalog(), ensure_ascii=False, indent=2) + '\n'
    content = subprocess.run(['deno', 'fmt', '--ext=json', '-'], input=content, text=True, capture_output=True, check=True).stdout
    for path in OUTPUTS:
        if options.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f'Stale emoji catalog: {path.relative_to(ROOT)}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print('Unicode 17.0 emoji catalogs verified' if options.check else 'Generated Unicode 17.0 emoji catalogs')

if __name__ == '__main__':
    main()
