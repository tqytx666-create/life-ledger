// 收件箱图片识别:GLM-4V-Flash 出草稿,只写 draft 不动账本
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
    const { id } = await req.json();
    if (!id) return j({ error: "缺 id" }, 400);

    const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    // 归属校验:调用者只能识别自己的条目
    const auth = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
    const { data: userData } = await svc.auth.getUser(auth);
    const uid = userData?.user?.id;
    if (!uid) return j({ error: "未登录" }, 401);

    const { data: item } = await svc.from("inbox_items").select("*").eq("id", id).single();
    if (!item) return j({ error: "条目不存在" }, 404);
    if (item.owner !== uid) return j({ error: "无权操作" }, 403);
    if (item.kind !== "image" || !item.path) return j({ error: "不是图片条目" }, 400);

    const { data: blob, error: de } = await svc.storage.from("inbox").download(item.path);
    if (de || !blob) return j({ error: "下载失败" }, 500);
    const buf = new Uint8Array(await blob.arrayBuffer());
    let bin = "";
    for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
    const b64 = btoa(bin);

    const prompt = `这是从付款人自己手机上截的支付/账单/订单截图。只输出严格JSON,不要markdown代码块:
{"is_bill":true或false,"amount":数字,"direction":"expense"或"income","merchant":"商户或对方名字","date":"YYYY-MM-DD"或null,"method":"支付方式原文"或null,"category":"餐饮/交通/购物/日用/娱乐/医疗/教育/订阅/人情/房租/其他 选一个","confidence":0到1}
规则:1)金额取"实付/实际支付/交易成功"的数,忽略原价和优惠;2)截图来自付款人手机:出现"对方已收款/xx已收款/支付成功/交易成功"都是本人在花钱,direction=expense;只有明确"收到/入账/别人转给我"才是income;3)微信转账给个人=人情;4)不是账单类图片就 is_bill=false;5)拿不准的字段给低confidence。`;

    const r = await fetch("https://open.bigmodel.cn/api/paas/v4/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("ZHIPU_KEY")}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "glm-4v-flash",
        temperature: 0.1,
        messages: [{
          role: "user",
          content: [
            { type: "image_url", image_url: { url: `data:image/png;base64,${b64}` } },
            { type: "text", text: prompt },
          ],
        }],
      }),
    });
    if (!r.ok) return j({ error: "模型调用失败 " + r.status }, 502);
    const out = await r.json();
    let text: string = out?.choices?.[0]?.message?.content ?? "";
    text = text.replace(/```json|```/g, "").trim();
    let draft: Record<string, unknown>;
    try { draft = JSON.parse(text); } catch { return j({ error: "解析失败", raw: text }, 500); }
    draft.model = "glm-4v-flash";
    draft.at = new Date().toISOString();

    await svc.from("inbox_items").update({ draft }).eq("id", id);
    return j({ draft });
  } catch (e) {
    return j({ error: String(e) }, 500);
  }
});
