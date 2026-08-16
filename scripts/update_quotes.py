#!/usr/bin/env python3
# 收盘后刷新证券行情:腾讯行情接口 → holdings 价格/市值 → 账户余额 → sec_daily(当日盈亏/收益率)
import json, os, urllib.request, datetime, sys

ENV = {}
for line in open(os.path.expanduser('~/life-ledger/credentials.env')):
    if '=' in line and not line.startswith('#'):
        k, v = line.strip().split('=', 1); ENV[k] = v
BASE, KEY = ENV['SUPABASE_URL'], ENV['SUPABASE_SERVICE_ROLE_KEY']

def api(method, path, body=None, prefer=None):
    req = urllib.request.Request(BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None)
    for h, v in [('apikey', KEY), ('Authorization', 'Bearer ' + KEY),
                 ('Content-Type', 'application/json'), ('User-Agent', 'll/1')]:
        req.add_header(h, v)
    if prefer: req.add_header('Prefer', prefer)
    with urllib.request.urlopen(req, timeout=30) as r:
        t = r.read().decode()
        return json.loads(t) if t else None

# 汇率(港股通折人民币)
fx = {r['currency']: float(r['to_cny']) for r in api('GET', '/rest/v1/fx_rates?select=*')}
HKD = fx.get('HKD', 0.92)

holdings = api('GET', '/rest/v1/holdings?select=*')
quoted = [h for h in holdings if h['kind'] in ('stock',) and h.get('code')]

def qcode(code):
    return ('hk' + code) if len(code) == 5 else ('sh' + code if code.startswith(('6','9','5')) else 'sz' + code)

codes = {h['code']: qcode(h['code']) for h in quoted}
url = 'https://qt.gtimg.cn/q=' + ','.join(codes.values())
raw = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=20).read().decode('gbk', 'ignore')
prices = {}
for line in raw.split(';'):
    if '=' not in line: continue
    key, val = line.split('=', 1)
    parts = val.strip('"').split('~')
    if len(parts) > 4:
        sym = key.strip().replace('v_', '')
        prices[sym] = float(parts[3])

changed = []
for h in quoted:
    sym = codes[h['code']]
    if sym not in prices or prices[sym] <= 0: continue
    px = prices[sym] * (HKD if sym.startswith('hk') else 1.0)  # 统一人民币
    value = round(float(h['qty']) * px, 2)
    api('PATCH', f"/rest/v1/holdings?id=eq.{h['id']}",
        {'price': round(px, 4), 'value': value, 'updated_at': datetime.datetime.utcnow().isoformat()})
    changed.append((h['name'], px, value, float(h['cost'])))

# 账户余额 = 各自 holdings 合计(含现金/负债行)
holdings = api('GET', '/rest/v1/holdings?select=account_id,value,name')
sums = {}
for h in holdings:
    sums[h['account_id']] = round(sums.get(h['account_id'], 0) + float(h['value']), 2)
total = 0
for aid, v in sums.items():
    api('PATCH', f'/rest/v1/accounts?id=eq.{aid}', {'balance': v})
    total += v
total = round(total, 2)

# 当日盈亏 vs 上一条记录
prev_rows = api('GET', '/rest/v1/sec_daily?select=*&order=snap_date.desc&limit=1')
prev = float(prev_rows[0]['total']) if prev_rows else total
day_pnl = round(total - prev, 2)
day_pct = round(day_pnl / prev * 100, 2) if prev else 0
today = (datetime.datetime.utcnow() + datetime.timedelta(hours=8)).date().isoformat()
detail = {n: {'price': round(p, 3), 'value': v, 'cost': c} for n, p, v, c in changed}
api('POST', '/rest/v1/sec_daily', {'snap_date': today, 'total': total, 'day_pnl': day_pnl,
    'day_pct': day_pct, 'detail': detail}, 'resolution=merge-duplicates')
api('POST', '/rest/v1/rpc/snapshot_net_worth', {})

print(f'证券总值 {total:,.2f} | 当日 {day_pnl:+,.2f} ({day_pct:+.2f}%)')
for n, p, v, c in changed:
    sign = '↑' if p >= c else '↓'
    print(f'  {n}: 现价{p:,.2f} 市值{v:,.0f} {sign}')
