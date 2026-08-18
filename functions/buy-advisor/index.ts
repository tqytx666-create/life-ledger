// 买前问一嘴:商品截图/文字 + 本人财务上下文 → 五维购买建议
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const j = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { image_b64, text } = await req.json();
    if (!image_b64 && !text) return j({ error: "给张商品截图或说下商品和价格" }, 400);

    const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const auth = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
    const { data: ud } = await svc.auth.getUser(auth);
    const uid = ud?.user?.id;
    if (!uid) return j({ error: "未登录" }, 401);

    // ===== 财务上下文(全部服务端算好,模型只负责判断) =====
    const month = new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 7);
    const [snapR, goalsR, txR, savR, wsdR] = await Promise.all([
      svc.from("net_worth_snapshots").select("liquid_cny,total_cny").eq("owner", uid).order("snap_date", { ascending: false }).limit(1),
      svc.from("save_goals").select("*").eq("owner", uid).eq("active", true),
      svc.from("transactions").select("type,amount,category,note,occurred_at").eq("owner", uid).gte("occurred_at", month + "-01"),
      svc.from("savings").select("amount").eq("owner", uid).gte("saved_at", month + "-01"),
      svc.from("accounts").select("name,balance").eq("owner", uid).eq("name", "网商贷"),
    ]);
    const liquid = Number(snapR.data?.[0]?.liquid_cny ?? snapR.data?.[0]?.total_cny ?? 0);
    let mIn = 0, mOut = 0;
    const recentBuys: string[] = [];
    for (const t of txR.data ?? []) {
      if (t.type === "income") mIn += Number(t.amount);
      if (t.type === "expense") {
        mOut += Number(t.amount);
        if (["购物", "娱乐", "订阅", "教育"].includes(t.category)) recentBuys.push(`${t.occurred_at} ${t.category} ¥${t.amount} ${String(t.note).slice(0, 22)}`);
      }
    }
    const goals = (goalsR.data ?? []).map((g) => {
      const cats = Array.isArray(g.cats) ? g.cats : JSON.parse(g.cats || "[]");
      let spent = 0;
      for (const t of txR.data ?? []) {
        if (t.type !== "expense") continue;
        if (cats.includes(t.category) || (g.kw && String(t.note).includes(g.kw))) spent += Number(t.amount);
      }
      return `${g.name}:本月已花${spent.toFixed(0)}/上限${Number(g.cap).toFixed(0)}`;
    });
    const saved = (savR.data ?? []).reduce((s, x) => s + Number(x.amount), 0);
    const wsdOwed = wsdR.data?.length ? -Number(wsdR.data[0].balance) : 0;
    const dayOfMonth = new Date(Date.now() + 8 * 3600e3).getDate();

    const ctx = `【他的本月财务实况】
- 可动净资产:${liquid.toFixed(0)}元${liquid < 0 ? "(还是负的,正在还债翻身期)" : ""}
- 本月(已过${dayOfMonth}天):收入${mIn.toFixed(0)},支出${mOut.toFixed(0)},净结余${(mIn - mOut).toFixed(0)}
- 省钱目标战区:${goals.join(";") || "未设置"}
- 本月已省下:${saved.toFixed(0)}元
${wsdOwed > 0 ? `- 高息负债:网商贷还欠${wsdOwed.toFixed(0)}元(年化12%,每月白烧利息${(wsdOwed * 0.01).toFixed(0)}元)` : ""}
- 近期购物/娱乐消费:${recentBuys.slice(0, 12).join(" | ") || "无"}
- 当前时刻:${new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 16).replace("T", " ")}(深夜下单要提醒冲动)`;

    const ask = `${ctx}

【任务】他想买${text ? "「" + text + "」" : "图中的商品"}。先识别商品和价格(有图以图为准),然后从五个维度分析该不该买,只输出严格JSON(不要markdown):
{"product":"商品名","price":数字,"verdict":"buy|wait|skip","title":"一句话结论(口语化,像懂钱的老哥)","dimensions":[{"name":"预算余量","pass":true/false,"comment":"一句话"},{"name":"省钱目标","pass":..,"comment":".."},{"name":"债务机会成本","pass":..,"comment":"换算成网商贷利息说"},{"name":"重复消费","pass":..,"comment":"结合近期消费清单"},{"name":"冲动指数","pass":..,"comment":"结合时间和价格占结余比例"}],"math":["这笔钱=网商贷X天利息","=本月结余的X%","其他有冲击力的换算"],"advice":"两三句实操建议(可以给'缓24小时'/'找平替'/'直接买'这类具体动作)"}
原则:刚需和生产力工具宽容,纯欲望消费严格;高息债没清时大额非必需品倾向wait/skip;金额小于结余2%且预算内可以痛快buy。语气像朋友,不说教。`;

    const content: unknown[] = [];
    if (image_b64) content.push({ type: "image_url", image_url: { url: image_b64 } });
    content.push({ type: "text", text: ask });

    const r = await fetch("https://open.bigmodel.cn/api/paas/v4/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("ZHIPU_KEY")}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "glm-4v-flash", temperature: 0.3, messages: [{ role: "user", content }] }),
    });
    if (!r.ok) return j({ error: "模型调用失败 " + r.status }, 502);
    const out = await r.json();
    let t2: string = out?.choices?.[0]?.message?.content ?? "";
    t2 = t2.replace(/```json|```/g, "").trim();
    try { return j({ result: JSON.parse(t2) }); } catch { return j({ error: "解析失败", raw: t2 }, 500); }
  } catch (e) {
    return j({ error: String(e) }, 500);
  }
});
