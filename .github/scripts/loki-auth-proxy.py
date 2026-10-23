#!/usr/bin/env python3
"""A Loki in front of the e2e's Loki that wants credentials.

Forwards a push to the real Loki only when the Authorization header is exactly
one of the allowed values and X-Scope-OrgID is exactly the expected tenant;
401 otherwise. The comparison is exact, so a password or token file with a
stray newline fails here as it would at Grafana Cloud. The real Loki runs
without auth and ignores the tenant, so this is where both are proven.

Usage: loki-auth-proxy.py <port> <upstream base url> <tenant> <authorization>...
Logs every request's verdict to stderr: "forwarded <n>" names which allowed
value matched, so the e2e can tell basic auth from a bearer token.
"""
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
UPSTREAM = sys.argv[2].rstrip("/")
TENANT = sys.argv[3]
ALLOWED = sys.argv[4:]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        auth = self.headers.get("Authorization", "")
        tenant = self.headers.get("X-Scope-OrgID", "")
        if auth not in ALLOWED or tenant != TENANT:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            sys.stderr.write(f"proxy: 401 (Authorization={auth!r}, X-Scope-OrgID={tenant!r})\n")
            return
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("content-type", "content-encoding")}
        req = urllib.request.Request(UPSTREAM + self.path, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                status = r.status
        except urllib.error.HTTPError as e:
            status = e.code
        except OSError as e:
            sys.stderr.write(f"proxy: upstream {UPSTREAM} unreachable: {e}\n")
            status = 502
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()
        sys.stderr.write(f"proxy: forwarded {ALLOWED.index(auth)} -> {status}\n")

    def log_message(self, *_):
        pass


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
