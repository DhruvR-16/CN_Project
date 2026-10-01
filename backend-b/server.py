from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json

HOST = "0.0.0.0"
PORT = 3002
BACKEND = "B"

class Handler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200, headers=None):
        body = json.dumps(data).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", BACKEND)

        if headers:
            for name, value in headers.items():
                self.send_header(name, value)

        self.end_headers()

        if status != 304:
            self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/api/status"):
            self.send_json({
                "backend": BACKEND,
                "status": "ok"
            })
            return

        if self.path == "/api/cache":
            etag = '"team1-cache-v1"'

            if self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", "public, max-age=60")
                self.end_headers()
            else:
                self.send_json(
                    {
                        "backend": BACKEND,
                        "status": "ok",
                        "message": "cache demo"
                    },
                    headers={
                        "Cache-Control": "public, max-age=60",
                        "ETag": etag
                    }
                )
            return

        self.send_json({"error": "Not Found"}, status=404)

    def log_message(self, format, *args):
        print(f"[Backend B] {self.address_string()} - {format % args}")

server = ThreadingHTTPServer((HOST, PORT), Handler)
print(f"Backend B listening on {HOST}:{PORT}")

try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\nStopping Backend B")
finally:
    server.server_close()
