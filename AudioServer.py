#!/usr/bin/env python3
"""Serve one bounded audio file briefly to the configured go2rtc host."""
import http.server
import json
import os
import socket
import sys
import urllib.parse


def main():
    target, path, info_path = sys.argv[1:]
    host = urllib.parse.urlsplit(target).hostname
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


if __name__ == "__main__":
    sys.exit(main())
