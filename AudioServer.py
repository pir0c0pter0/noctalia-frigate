#!/usr/bin/env python3
"""Serve one bounded audio file briefly to the configured go2rtc host."""
import http.server
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import urllib.parse
import uuid


def main():
    target, path, info_path, *options = sys.argv[1:]
    peer_option = options[0] if options else ""
    if peer_option.startswith("ssh:"):
        return serve_over_ssh(path, info_path, peer_option)
    host = peer_option or urllib.parse.urlsplit(target).hostname
    peer = socket.gethostbyname(host)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
        route.connect((peer, 9))
        local = route.getsockname()[0]
    with open(path, "rb") as audio:
        content = audio.read(10485761)
    if not content or len(content) > 10485760:
        return 1

    served = False

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            nonlocal served
            if self.client_address[0] != peer or self.path != "/clip":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            served = True

        def log_message(self, *_args):
            pass

    with http.server.HTTPServer((local, 0), Handler) as server:
        server.timeout = 30
        temp = info_path + ".tmp"
        with open(temp, "w", encoding="utf-8") as output:
            json.dump({"url": f"http://{local}:{server.server_port}/clip"}, output)
        os.replace(temp, info_path)
        try:
            server.handle_request()
        finally:
            if os.path.exists(info_path):
                os.remove(info_path)
    return 0 if served else 1


def serve_over_ssh(path, info_path, peer_option):
    match = re.fullmatch(r"ssh:([\w.\-]+):(/[\w.\-/]+)", peer_option)
    if not match:
        return 1
    host, directory = match.groups()
    with open(path, "rb") as audio:
        content = audio.read(10485761)
    if not content or len(content) > 10485760:
        return 1
    name = "noctalia-audio-" + uuid.uuid4().hex + ".ogg"
    remote = directory.rstrip("/") + "/" + name
    create = (
        "import os,sys,subprocess; "
        "p=sys.argv[1]; f=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); "
        "os.fdopen(f,'wb').write(sys.stdin.buffer.read()); "
        "subprocess.Popen([sys.executable,'-c',"
        "'import os,sys,time; time.sleep(60); os.path.exists(sys.argv[1]) and os.remove(sys.argv[1])',p],"
        "stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)"
    )
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host]
    command = "python3 -c " + shlex.quote(create) + " " + shlex.quote(remote)
    try:
        result = subprocess.run(ssh + [command], input=content, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=12)
        if result.returncode:
            return 1
        with open(info_path + ".tmp", "w", encoding="utf-8") as output:
            json.dump({"file": "/config/" + name}, output)
        os.replace(info_path + ".tmp", info_path)
        for _ in range(200):
            if os.path.exists(info_path + ".done"):
                break
            time.sleep(0.1)
        return 0
    finally:
        for item in (info_path, info_path + ".done"):
            if os.path.exists(item):
                os.remove(item)
        cleanup = "python3 -c " + shlex.quote("import os,sys; os.path.exists(sys.argv[1]) and os.remove(sys.argv[1])") + " " + shlex.quote(remote)
        try:
            subprocess.run(ssh + [cleanup], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass


if __name__ == "__main__":
    sys.exit(main())
