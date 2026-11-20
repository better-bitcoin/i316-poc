#!/usr/bin/env python3
# fix-ffm.py — 从 nm 符号 demangle 出 FeatureFlagManager init 的真实参数标签,
# 自动修正 AppDelegate.swift 的调用点 (自愈: 编译永远通过)
import subprocess, re, sys, glob

# 找 CoreUtilities 二进制 (pod install 后在 Pods/)
cu = None
for pat in ['Pods/**/ZendeskSDKCoreUtilities.framework/ZendeskSDKCoreUtilities',
            'dd/Build/Products/**/ZendeskSDKCoreUtilities.framework/ZendeskSDKCoreUtilities']:
    hits = glob.glob(pat, recursive=True)
    if hits:
        cu = hits[0]
        break
if not cu:
    print('fix-ffm: CoreUtilities binary not found')
    sys.exit(0)

print('fix-ffm: bin =', cu)
nm = subprocess.run(['nm', '-gU', cu], capture_output=True, text=True).stdout
mangled = None
for line in nm.split('\n'):
    if 'FeatureFlagManagerC015hipaaAttachmentE026canUserSee' in line and line.strip().endswith('C'):
        mangled = line.split(' ', 1)[-1].strip()
        break
if not mangled:
    print('fix-ffm: 8-param init symbol not found')
    sys.exit(0)

# Swift mangled names 以 _$s 或 $s 开头 — demangle 输入需 $s
sym = mangled if mangled.startswith('$s') else mangled.replace('_$s', '$s', 1)
print('fix-ffm: mangled =', sym[:60], '...')
dem = subprocess.run(['xcrun', 'swift-demangle', sym], capture_output=True, text=True).stdout.strip()
print('fix-ffm: demangled =', dem[:300])

m = re.search(r'init\(([^)]+)\)', dem)
if not m:
    print('fix-ffm: no init(...) in demangled output')
    sys.exit(0)
# 参数形如 "hipaaAttachmentFlag: Swift.Bool, canUserSee...: Swift.Bool"
raw = m.group(1)
labels = [p.split(':')[0].strip() for p in raw.split(',') if ':' in p]
labels = [l.split('.')[-1] for l in labels]  # 去 Swift. 前缀
print('fix-ffm: labels =', labels)

call = 'FeatureFlagManager(\n' + ',\n'.join('            ' + l + ': false' for l in labels) + ')'

src_path = 'PoC/AppDelegate.swift'
src = open(src_path).read()
new_src, n = re.subn(r'FeatureFlagManager\([^)]*\)', lambda _: call, src, count=1, flags=re.S)
if n:
    open(src_path, 'w').write(new_src)
    print('fix-ffm: call site patched with', len(labels), 'labels')
else:
    print('fix-ffm: WARN call site not found')
