// 账单文件解析:微信xlsx / 支付宝csv(GBK) / 美团csv → 统一行格式
// 行: {date, type: 'income'|'expense', amount, methodRaw, counterparty, note, importId, category}

const CATS = [
  ['教育', /小学|学校|教育|培训|课程/],
  ['房租', /房东/],
  ['餐饮', /餐|饮|食|椰|茶|咖啡|面|粉|饭|烧|烤|火锅|美团|外卖|肯德基|麦当劳|瑞幸|奶茶|小笼包|牛肉/],
  ['交通', /滴滴|出行|加油|停车|租车|地铁|高速|石油|石化|骑行|充电/],
  ['购物', /淘宝|抖音|京东|拼多多|商城|超市|百货|便利|万象|泡泡玛特/],
  ['娱乐', /电玩|影|游戏|KTV|Night|赛博/],
  ['医疗', /医院|药|诊所|健康|大夫/],
  ['差旅', /华住|酒店|民宿|航空|铁路|12306/],
  ['订阅', /Apple|会员|订阅/i],
]
function classify(text, isTransferToPerson, isIncome) {
  if (isTransferToPerson) return isIncome ? '转入' : '转账给人'
  for (const [c, re] of CATS) if (re.test(text)) return c
  return isIncome ? '转入' : '其他'
}
const amt = (s) => Number(String(s).replace(/[¥,\s]/g, '')) || 0

// ===== 微信 xlsx =====
export async function parseWeChat(arrayBuffer) {
  const XLSX = await import('xlsx')
  const wb = XLSX.read(arrayBuffer)
  const grid = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: false })
  const hi = grid.findIndex((r) => r && r[0] === '交易时间')
  if (hi < 0) throw new Error('不是微信账单格式(找不到表头)')
  const H = grid[hi]
  const col = (name) => H.findIndex((h) => String(h || '').includes(name))
  const ci = { time: col('交易时间'), type: col('交易类型'), peer: col('交易对方'), goods: col('商品'),
    io: col('收/支'), amount: col('金额'), method: col('支付方式'), status: col('当前状态'), txid: col('交易单号') }
  const raw = grid.slice(hi + 1).filter((r) => r && r[ci.time])

  // 全额退款对冲:退款收入 与 已全额退款的支出 成对跳过
  const refunds = raw.filter((r) => String(r[ci.type]).includes('退款') || String(r[ci.status]) === '对方已退还')
  const skip = new Set()
  for (const e of raw) {
    if (r_io(e) !== '支出') continue
    const st = String(e[ci.status] || '')
    if (st === '已全额退款' || st.startsWith('已退款')) {
      const m = st.match(/已退款[(（]?¥?([\d.]+)/)
      const refunded = m ? Number(m[1]) : amt(e[ci.amount])
      if (Math.abs(refunded - amt(e[ci.amount])) < 0.01) {
        const inc = refunds.find((x) => !skip.has(x) && Math.abs(amt(x[ci.amount]) - amt(e[ci.amount])) < 0.01)
        if (inc) { skip.add(e); skip.add(inc) }
      }
    }
  }
  function r_io(r) { return String(r[ci.io] || '') }

  const rows = []
  let neutral = 0
  for (const r of raw) {
    if (skip.has(r)) continue
    const io = r_io(r)
    if (io !== '收入' && io !== '支出') { neutral++; continue }
    const a = amt(r[ci.amount]); if (a <= 0) continue
    const peer = String(r[ci.peer] || ''), goods = String(r[ci.goods] || ''), typ = String(r[ci.type] || '')
    const isPerson = typ.startsWith('转账') || typ.includes('红包')
    rows.push({
      date: String(r[ci.time]).slice(0, 10),
      type: io === '收入' ? 'income' : 'expense',
      amount: a,
      methodRaw: String(r[ci.method] || '/') === '/' ? '零钱' : String(r[ci.method]),
      counterparty: peer.slice(0, 20),
      note: '微信|' + (peer + ' ' + goods).replace(/\//g, ' ').trim().slice(0, 44),
      importId: 'wx-' + String(r[ci.txid] || '').trim(),
      category: typ.includes('退款') ? '退款' : classify(peer + goods, isPerson, io === '收入'),
    })
  }
  return { platform: '微信', rows, skipped: { 退款对冲: skip.size, 中性交易: neutral } }
}

// ===== 支付宝 csv(GBK) =====
export function parseAlipay(arrayBuffer) {
  const text = new TextDecoder('gbk').decode(arrayBuffer)
  const lines = text.split(/\r?\n/)
  const hi = lines.findIndex((l) => l.startsWith('交易时间,'))
  if (hi < 0) throw new Error('不是支付宝账单格式')
  const rows = []
  let neutral = 0, closed = 0
  for (const line of lines.slice(hi + 1)) {
    const c = line.split(',').map((x) => x.trim())
    if (c.length < 10 || !c[0]) continue
    const [time, cat0, peer, , goods, io, money, method, status, txid] = c
    if (String(status).includes('交易关闭') || String(status).includes('解冻') || String(status).includes('免押')) { closed++; continue }
    if (io === '不计收支') { neutral++; continue }
    if (io !== '收入' && io !== '支出') continue
    const a = amt(money); if (a <= 0) continue
    const ALI = { 餐饮美食: '餐饮', 交通出行: '交通', 文化休闲: '娱乐', 日用百货: '日用', 商业服务: '经营支出',
      酒店旅游: '差旅', 爱车养车: '交通', 转账红包: io === '收入' ? '转入' : '人情', 信用借还: '其他' }
    rows.push({
      date: time.slice(0, 10),
      type: io === '收入' ? 'income' : 'expense',
      amount: a,
      methodRaw: (method || '账户余额').split('&')[0],
      counterparty: peer.slice(0, 20),
      note: '支付宝|' + (peer + ' ' + goods).replace(/\//g, ' ').trim().slice(0, 44),
      importId: 'ali-' + String(txid || '').trim(),
      category: ALI[cat0] || classify(peer + goods, false, io === '收入'),
    })
  }
  return { platform: '支付宝', rows, skipped: { '内部往来(充值提现理财还贷,建议交给管家处理)': neutral, 关闭或冻结: closed } }
}

// ===== 美团 csv =====
export function parseMeituan(arrayBuffer) {
  let text
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(arrayBuffer) }
  catch { text = new TextDecoder('gbk').decode(arrayBuffer) }
  const lines = text.split(/\r?\n/)
  const hi = lines.findIndex((l) => l.startsWith('交易创建时间'))
  if (hi < 0) throw new Error('不是美团账单格式')
  const rows = []
  let wechatPaid = 0, repay = 0
  for (const line of lines.slice(hi + 1)) {
    const c = line.split(',').map((x) => x.replace(/^"|"\s*$/g, '').trim())
    if (c.length < 9 || !c[0]) continue
    const [time, , typ, title, io, method, , paid, txid] = c
    if (method === '微信支付' || method === '支付宝支付') { wechatPaid++; continue }  // 已在微信/支付宝账单里
    if (typ === '还款') { repay++; continue }  // 月付还款,避免与月付消费重复
    if (io !== '支出' && io !== '收入') continue
    const a = amt(paid); if (a <= 0) continue
    rows.push({
      date: time.slice(0, 10),
      type: io === '收入' ? 'income' : 'expense',
      amount: a,
      methodRaw: method || '美团',
      counterparty: title.slice(0, 20),
      note: '美团|' + title.slice(0, 44),
      importId: 'mt-' + String(txid || '').trim(),
      category: classify(title, false, io === '收入'),
    })
  }
  return { platform: '美团', rows, skipped: { '微信/支付宝支付(已在对应账单)': wechatPaid, 月付还款: repay } }
}

// 按文件名/内容自动判别
export async function parseBill(file) {
  const buf = await file.arrayBuffer()
  const name = file.name
  if (/\.xlsx?$/i.test(name)) return parseWeChat(buf)
  if (/\.csv$/i.test(name)) {
    const head = new TextDecoder('gbk').decode(buf.slice(0, 400))
    if (head.includes('支付宝')) return parseAlipay(buf)
    const head2 = new TextDecoder('utf-8').decode(buf.slice(0, 400))
    if (head2.includes('美团')) return parseMeituan(buf)
    if (head.includes('美团')) return parseMeituan(buf)
    return parseAlipay(buf)
  }
  if (/\.pdf$/i.test(name)) throw new Error('PDF 账单(抖音)请丢到随手拍收件箱,由管家处理')
  throw new Error('不认识的文件格式,支持:微信.xlsx / 支付宝.csv / 美团.csv')
}
