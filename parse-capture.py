#!/usr/bin/env python3
# parse-capture.py — 解析 webhook.site 收到的请求摘要
import json
try:
    d = json.load(open('wh-requests.json'))
    print('总请求数:', d.get('total', 0))
    for r in d.get('data', [])[:15]:
        method = r.get('method', '?')
        path = r.get('path') or ''
        print('-', method, path[:60])
        c = r.get('content') or ''
        if 'assertion' in c or 'jwt' in c.lower():
            print('  BODY:', c[:300])
except Exception as e:
    print('parse err:', e)
