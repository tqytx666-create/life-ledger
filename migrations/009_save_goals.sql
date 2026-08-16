-- 009 · 省钱作战:分领域支出上限目标(cats按分类匹配/kw按备注关键词匹配)
create table if not exists save_goals (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  icon        text not null default '🎯',
  cats        jsonb not null default '[]'::jsonb,  -- 匹配的支出分类数组
  kw          text not null default '',            -- 或备注关键词
  cap         numeric(12,2) not null,              -- 月度上限
  strategy    text not null default '',            -- 省钱策略一句话
  sort        int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table save_goals enable row level security;
drop policy if exists auth_all on save_goals;
create policy auth_all on save_goals for all to authenticated using (true) with check (true);

insert into save_goals (name, icon, cats, kw, cap, strategy, sort)
select * from (values
  ('Apple订阅内购', '🍎', '["订阅"]'::jsonb, 'Apple', 500::numeric, '设置→订阅全面清一遍;内购前想三秒,月均曾高达1930', 1),
  ('抖音购物', '🛒', '["购物"]'::jsonb, '抖音电商', 2000::numeric, '深夜别下单,先加购物车睡一觉;大件让我比价', 2),
  ('娱乐夜场', '🌃', '["娱乐","生活服务"]'::jsonb, '', 2000::numeric, '电玩/KTV/洗浴给个总预算,超了下月扣回来', 3),
  ('外卖餐饮', '🍜', '["餐饮"]'::jsonb, '', 2500::numeric, '用券省的记「省下」,但别为凑单多点', 4)
) v(name, icon, cats, kw, cap, strategy, sort)
where not exists (select 1 from save_goals);
