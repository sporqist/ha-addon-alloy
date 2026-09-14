#!/usr/bin/env python3
"""A metrics endpoint that answers only to one exact bearer token.

Stands in for Home Assistant's /api/prometheus in the e2e: 200 and one metric
when the Authorization header is exactly "Bearer <token>", 401 otherwise. The
comparison is exact, so a token file with a trailing newline (header
"Bearer xxx\\n") is a 401 here just as it would be at Home Assistant.

Usage: metrics-stub.py <port> <token>
Logs every request's verdict to stderr so a failing run says why.
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
TOKEN = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {TOKEN}":
            body = b"# HELP e2e_stub_up The stub answered an authenticated scrape.\n# TYPE e2e_stub_up gauge\ne2e_stub_up 1\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            verdict = "200 authenticated"
        else:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            verdict = f"401 (Authorization={auth!r})"
        sys.stderr.write(f"stub: {self.path} -> {verdict}\n")

    def log_message(self, *_):
        pass


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
