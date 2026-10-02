#!/usr/bin/env bash
set +x
set -euo pipefail
photo_primary_screen_repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
exec python3 -I - "$photo_primary_screen_repository" "$@" <<'PY'
import getpass
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import warnings

stage = 'preflight'
try:
    if len(sys.argv) != 3:
        raise ValueError()
    repository = Path(sys.argv[1]).resolve(strict=True)
    supplied = Path(sys.argv[2])
    packet = supplied.resolve(strict=True)
    if supplied.is_symlink() or repository == packet or repository in packet.parents or packet in repository.parents:
        raise ValueError()
    if any(c in str(p) for p in (repository, packet) for c in (',', '\n', '\r')):
        raise ValueError()
    if stat.S_IMODE(packet.stat().st_mode) != 0o700 or packet.stat().st_uid != os.getuid():
        raise ValueError()
    deno = shutil.which('deno')
    if not deno or not (packet / 'screen-manifest.json').is_file():
        raise ValueError()
    authorization = packet.parent / '.photo-primary-screen-authorizations'
    authorization.mkdir(mode=0o700, exist_ok=True)
    if authorization.is_symlink() or stat.S_IMODE(authorization.stat().st_mode) != 0o700 or authorization.stat().st_uid != os.getuid():
        raise ValueError()
    environment = {n: os.environ[n] for n in ('PATH', 'HOME', 'DENO_DIR') if n in os.environ}
    common = [deno, 'run', '--frozen', '--no-prompt', '--cached-only', '--config', 'services/supabase/functions/deno.json',
              '--allow-read=' + str(repository) + ',' + str(packet) + ',' + str(authorization),
              '--allow-write=' + str(packet) + ',' + str(authorization), '--allow-run=git']
    entry = 'services/supabase/scripts/evaluate_photo_primary_screen.ts'
    def offline(mode):
        result = subprocess.run(common + ['--deny-net', '--deny-env', entry, mode, str(packet)], cwd=repository,
                                env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if result.returncode:
            raise ValueError()
        return result.stdout.strip()
    offline('report')
    stage = 'key_entry'
    keys = {name: os.environ.get(name) for name in ('OPENAI_EVALUATION_API_KEY',)}
    if not all(keys.values()):
        warnings.simplefilter('error', getpass.GetPassWarning)
        with open('/dev/tty', 'r') as terminal:
            if not terminal.isatty():
                raise ValueError()
        keys = {'OPENAI_EVALUATION_API_KEY': getpass.getpass('Naturebook OpenAI key (hidden): ')}
    if any(not key or len(key) > 512 or any(c.isspace() for c in key) for key in keys.values()):
        raise ValueError()
    # Only the paid child receives the hidden OpenAI credential.
    stage = 'evaluation'
    for _ in range(41):
        arm = offline('next')
        if arm == 'complete':
            print('Photo primary development screen collection complete. Review the private report.')
            break
        if arm not in ('released', 'primary'):
            raise ValueError()
        child = dict(environment)
        child['OPENAI_EVALUATION_API_KEY'] = keys['OPENAI_EVALUATION_API_KEY']
        permissions = ['--allow-net=api.openai.com:443', '--allow-env=OPENAI_EVALUATION_API_KEY',
            '--deny-env=SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY']
        result = subprocess.run(common + permissions + [entry, '--one-live', str(packet), arm], cwd=repository,
                                env=child, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        child.clear()
        if result.returncode:
            raise ValueError()
    else:
        raise ValueError()
    keys.clear()
except (Exception, KeyboardInterrupt):
    print('photo_primary_screen_launcher_stopped:' + stage + '; inspect private accounting; never retry a claimed slot', file=sys.stderr)
    sys.exit(1)
PY
