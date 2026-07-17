#!/usr/bin/env python3
"""Minimal local webhook receiver to inspect Secure Application notification payloads.

Usage:
    python3 scripts/webhook-receiver.py [--port 9000] [--path /]

Then point a Secure Application notification rule at:
    http://<your-host>:9000/

It prints the method, headers, and pretty-printed JSON (or raw body) for every
request it receives, so you can see exactly what the platform sends.
"""
import argparse
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _handle(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else b""

        ts = datetime.now(timezone.utc).isoformat()
        print(f"\n{'=' * 70}")
        print(f"[{ts}] {self.command} {self.path} from {self.client_address[0]}")
        print("-- headers " + "-" * 59)
        for key, value in self.headers.items():
            print(f"{key}: {value}")

        print("-- body " + "-" * 62)
        if body:
            try:
                parsed = json.loads(body)
                print(json.dumps(parsed, indent=2, ensure_ascii=False))
            except json.JSONDecodeError:
                print(body.decode("utf-8", errors="replace"))
        else:
            print("(empty body)")
        print("=" * 70)

        # Respond 200 so the sender considers delivery successful.
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"received"}')

    # Accept whatever verb the sender uses.
    do_POST = _handle
    do_PUT = _handle
    do_GET = _handle

    def log_message(self, *args):
        pass  # silence default per-request logging; we print our own


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9000, help="Port to listen on (default: 9000)")
    parser.add_argument("--host", default="0.0.0.0", help="Interface to bind (default: 0.0.0.0)")
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Listening on http://{args.host}:{args.port}/  (Ctrl-C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
