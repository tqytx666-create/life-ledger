-- 021 · 卖出复盘:记录已卖出的股票(卖价/数量),每日行情脚本更新现价,算"卖掉比拿着少亏多少"
create table if not exists sold_positions (
  id          uuid primary key default gen_random_uuid(),
  owner       uuid not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid),
  name        text not null,
  code        text not null,
  qty         numeric(16,2) not null,
  sell_price  numeric(14,4) not null,      -- 卖出均价(原币种)
  currency    text not null default 'CNY', -- CNY / HKD
  sell_date   date not null,
  price_note  text not null default '',    -- 卖价来源说明(成交明细 / 由盈亏反推)
  cur_price   numeric(14,4),               -- 最新价(原币种),脚本每个交易日写入
  price_at    timestamptz,
  created_at  timestamptz not null default now()
);
alter table sold_positions enable row level security;
drop policy if exists owner_all on sold_positions;
create policy owner_all on sold_positions for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());
