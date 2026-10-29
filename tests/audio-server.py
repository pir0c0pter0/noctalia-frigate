import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request
import importlib.util
from unittest.mock import patch


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

spec = importlib.util.spec_from_file_location("audio_server", "AudioServer.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    clip = Path(directory) / "clip.ogg"
    info = Path(directory) / "server.json"
    clip.write_bytes(b"audio\x00contents")
    Path(str(info) + ".done").touch()
    with patch.object(module.subprocess, "run") as run:
        run.return_value.returncode = 0
        assert module.serve_over_ssh(str(clip), str(info), "ssh:server:/srv/frigate/config") == 0
        assert run.call_count == 2
        assert run.call_args_list[0].kwargs["input"] == clip.read_bytes()
        assert not info.exists() and not Path(str(info) + ".done").exists()
    assert module.serve_over_ssh(str(clip), str(info), "ssh:server:relative") == 1
print("SSH audio transfer checks passed")
