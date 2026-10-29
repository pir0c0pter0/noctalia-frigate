import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request


with tempfile.TemporaryDirectory() as directory:
    clip = Path(directory) / "clip.ogg"
    info = Path(directory) / "server.json"
    clip.write_bytes(b"audio\x00contents")
    process = subprocess.Popen(["python3", "AudioServer.py", "http://127.0.0.1:1984", str(clip), str(info)])
    try:
        for _ in range(100):
            if info.exists():
                break
            if process.poll() is not None:
                raise AssertionError("server exited before announcing its address")
            time.sleep(0.02)
        url = json.loads(info.read_text())["url"]
        with urllib.request.urlopen(url, timeout=3) as response:
            assert response.read() == clip.read_bytes()
        assert process.wait(timeout=3) == 0
        assert not info.exists()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
print("audio server checks passed")
