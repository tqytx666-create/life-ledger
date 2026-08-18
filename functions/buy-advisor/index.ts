// 买前问一嘴 v2:两段式 —— 视觉识别商品 → 服务端规则定判决 → 模型只负责解释
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const j = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

async function zhipu(model: string, content: unknown, temperature = 0.2) {
  const r = await fetch("https://open.bigmodel.cn/api/paas/v4/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${Deno.env.get("ZHIPU_KEY")}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, temperature, messages: [{ role: "user", content }] }),
  });
  if (!r.ok) throw new Error("模型调用失败 " + r.status);
  const out = await r.json();
  return String(out?.choices?.[0]?.message?.content ?? "").replace(/```json|```/g, "").trim();
}

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

    // ===== 第一段:识别商品(视觉) =====
    const recogPrompt = `识别${text ? "「" + text + "」" : "图中商品"}。只输出严格JSON:
{"product":"商品名(简短)","price":数字(实付价,识别不出就用文字里说的),"category":"餐饮|服饰|数码|美妆|家居|运动|购物|娱乐|订阅|教育|医疗|交通|其他 选一","necessity":"刚需|生产力工具|改善型|纯欲望 选一"}`;
    const c1: unknown[] = [];
    if (image_b64) c1.push({ type: "image_url", image_url: { url: image_b64 } });
    c1.push({ type: "text", text: recogPrompt });
    let item: { product: string; price: number; category: string; necessity: string };
    try { item = JSON.parse(await zhipu("glm-4v-flash", c1)); }
    catch { return j({ error: "没认出商品,试试打字描述+价格" }, 422); }
    const price = Number(item.price) || 0;

    // ===== 财务上下文 =====
    const now = new Date(Date.now() + 8 * 3600e3);
    const month = now.toISOString().slice(0, 7);
    const dayOfMonth = now.getUTCDate();
    const daysInMonth = new Date(now.getUTCFullYear(), now.getUTCMonth() + 1, 0).getDate();
    const pace = dayOfMonth / daysInMonth;
    const hour = now.getUTCHours();

    const [goalsR, txR, wsdR] = await Promise.all([
      svc.from("save_goals").select("*").eq("owner", uid).eq("active", true),
      svc.from("transactions").select("type,amount,category,note,occurred_at").eq("owner", uid).gte("occurred_at", month + "-01"),
      svc.from("accounts").select("balance").eq("owner", uid).eq("name", "网商贷"),
    ]);
    let mIn = 0, mOut = 0, similar30d = 0;
    for (const t of txR.data ?? []) {
      if (t.type === "income") mIn += Number(t.amount);
      if (t.type === "expense") {
        mOut += Number(t.amount);
        if (t.category === item.category || (item.category === "服饰" && t.category === "购物")) similar30d++;
      }
    }
    const mNet = mIn - mOut;
    const wsdOwed = wsdR.data?.length ? Math.max(-Number(wsdR.data[0].balance), 0) : 0;

    // 找命中的预算战区(品类映射宽松:服饰/数码/美妆/家居/运动 都算购物系)
    const shopLike = ["服饰", "数码", "美妆", "家居", "运动", "购物"];
    let hitGoal: { name: string; cap: number; spent: number } | null = null;
    for (const g of goalsR.data ?? []) {
      const cats: string[] = Array.isArray(g.cats) ? g.cats : JSON.parse(g.cats || "[]");
      const match = cats.includes(item.category) ||
        (shopLike.includes(item.category) && cats.some((c: string) => shopLike.includes(c)));
      if (!match) continue;
      let spent = 0;
      for (const t of txR.data ?? []) {
        if (t.type !== "expense") continue;
        if (cats.includes(t.category) || (g.kw && String(t.note).includes(g.kw))) spent += Number(t.amount);
      }
      hitGoal = { name: g.name, cap: Number(g.cap), spent };
      break;
    }

    // ===== 第二段:确定性规则打分(判决不交给模型) =====
    const dims: { name: string; pass: boolean; fact: string }[] = [];
    // ①预算余量:命中战区看"花完这笔是否仍在上限内"
    let budgetPass: boolean, budgetFact: string;
    if (hitGoal) {
      const after = hitGoal.spent + price;
      budgetPass = after <= hitGoal.cap;
      budgetFact = `命中「${hitGoal.name}」战区:已花${hitGoal.spent.toFixed(0)}/上限${hitGoal.cap.toFixed(0)},买完变${after.toFixed(0)},${budgetPass ? "仍在预算内" : `超线${(after - hitGoal.cap).toFixed(0)}元`}`;
    } else {
      budgetPass = price <= Math.max(mNet, 0) * 0.05 + 500;
      budgetFact = `没有对应预算战区;金额${price}元 vs 本月净结余${mNet.toFixed(0)}元`;
    }
    if (!budgetPass && price <= 100) { budgetPass = true; budgetFact += "(百元内小额豁免)"; }
    dims.push({ name: "预算余量", pass: budgetPass, fact: budgetFact });
    // ②消费节奏:买完后战区进度 vs 时间进度
    let pacePass = true, paceFact = `本月时间已过${(pace * 100).toFixed(0)}%`;
    if (hitGoal && hitGoal.cap > 0) {
      const afterPct = (hitGoal.spent + price) / hitGoal.cap;
      pacePass = afterPct <= pace + 0.25;
      paceFact = `买完后该战区用掉${(afterPct * 100).toFixed(0)}%额度,时间才过${(pace * 100).toFixed(0)}%,${pacePass ? "节奏健康" : "花得比日子快"}`;
    }
    dims.push({ name: "消费节奏", pass: pacePass, fact: paceFact });
    // ③债务机会成本:只对大额非必需较真
    const isNeed = item.necessity === "刚需" || item.necessity === "生产力工具";
    const debtPass = wsdOwed <= 0 || price <= 3000 || isNeed;
    const debtDays = wsdOwed > 0 ? (price / (wsdOwed * 0.12 / 365)).toFixed(1) : "0";
    dims.push({ name: "债务机会成本", pass: debtPass, fact: wsdOwed > 0 ? `网商贷还欠${wsdOwed.toFixed(0)},这笔=约${debtDays}天利息${debtPass ? ",在可容忍范围" : ",大额非必需建议先还债"}` : "无高息债,此项不扣分" });
    // ④重复消费
    const repeatPass = similar30d < 6 || price < 200;
    dims.push({ name: "重复消费", pass: repeatPass, fact: `本月同类消费已${similar30d}笔${repeatPass ? ",不算频繁" : ",有点上头了"}` });
    // ⑤冲动指数
    const impulsePass = !(hour >= 0 && hour < 6 && item.necessity === "纯欲望" && price > 500);
    dims.push({ name: "冲动指数", pass: impulsePass, fact: impulsePass ? "时间和金额都正常" : `现在是凌晨${hour}点,纯欲望大额,冲动高危` });

    const passes = dims.filter((d) => d.pass).length;
    let verdict: string;
    if (!budgetPass) verdict = price > Math.max(mNet, 3000) * 0.3 ? "skip" : "wait";
    else if (passes >= 4) verdict = "buy";
    else if (passes === 3) verdict = isNeed ? "buy" : "wait";
    else verdict = "wait";
    if (wsdOwed > 0 && item.necessity === "纯欲望" && price > Math.max(mNet, 0) * 0.3 && price > 5000) verdict = "skip";

    // ===== 第三段:模型只写"人话"(判决与事实已锁死) =====
    const explainPrompt = `你是他的私人财务管家,懂行、像朋友、不说教。商品:${item.product} ${price}元(${item.necessity})。
系统判决(不可更改):${verdict === "buy" ? "买" : verdict === "wait" ? "缓一缓" : "别买"}。
五维事实(pass表示该维度OK):${JSON.stringify(dims)}
补充:本月净结余${mNet.toFixed(0)}元${wsdOwed > 0 ? ",网商贷还欠" + wsdOwed.toFixed(0) + "元(年化12%)" : ""}。
只输出严格JSON:{"title":"一句话结论,口语化带态度","comments":["对应五维各一句话点评,顺序一致,基于事实别编数"],"math":["1-2条有冲击力的等价换算"],"advice":"两三句具体可执行的建议${verdict !== "buy" ? ",给出'缓24小时/找平替/等大促'这类动作" : ",痛快买的话提一句怎么买更划算"}"}`;
    let ex: { title: string; comments: string[]; math: string[]; advice: string };
    try { ex = JSON.parse(await zhipu("glm-4-flash", [{ type: "text", text: explainPrompt }], 0.4)); }
    catch { ex = { title: verdict === "buy" ? "预算内,买吧" : "先缓缓", comments: dims.map((d) => d.fact), math: [], advice: "" }; }

    return j({
      result: {
        product: item.product, price, verdict,
        title: ex.title,
        dimensions: dims.map((d, i) => ({ name: d.name, pass: d.pass, comment: ex.comments?.[i] || d.fact })),
        math: ex.math || [], advice: ex.advice || "",
        blocking: !budgetPass && hitGoal ? `拦你的是「${hitGoal.name}」预算(${hitGoal.spent.toFixed(0)}/${hitGoal.cap.toFixed(0)})——觉得上限不合理可以让管家调` : null,
      },
    });
  } catch (e) {
    return j({ error: String(e) }, 500);
  }
});
