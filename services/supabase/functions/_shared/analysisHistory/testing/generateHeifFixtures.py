"""Generate only synthetic local ImageIO HEIC fixtures on macOS.

Run with one NEW output directory; nothing is installed or sent over the network.
The input pixels are deterministic. Encoder output may differ by OS/hardware;
review and retain exact bytes/hashes before replacing any checked-in fixture.
"""
import base64
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import zlib


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


def generate(root):
    root.mkdir(exist_ok=False)
    os_version = subprocess.check_output(
        ["/usr/bin/sw_vers", "-productVersion"], text=True).strip()
    vectors = []
    for width, height in [(64, 48), (1024, 768)]:
        raw = b"".join(b"\0" + bytes(v for x in range(width) for v in (
            (x // 16 % 2) * 180 + 30, (y // 16 % 2) * 160 + 40, 90))
            for y in range(height))
        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
        source = root / f"pattern-{width}.png"
        output = root / f"pattern-{width}.heic"
        source.write_bytes(png)
        with (root / f"encode-{width}.log").open("w") as log:
            subprocess.run(["/usr/bin/sips", "-s", "format", "heic", str(source),
                            "--out", str(output)], stdout=log, stderr=subprocess.STDOUT,
                           check=True)
        data = output.read_bytes()
        vectors.append({"name": f"macos-imageio-{width}x{height}",
                        "content_type": "image/heic", "width": width, "height": height,
                        "encoder": f"macOS {os_version} /usr/bin/sips format heic",
                        "pixel_source": "deterministic RGB checker; no personal media",
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "base64": base64.b64encode(data).decode()})
    (root / "heif-native-containers.json").write_text(json.dumps(vectors, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: generateHeifFixtures.py NEW_OUTPUT_DIRECTORY")
    generate(Path(sys.argv[1]))
