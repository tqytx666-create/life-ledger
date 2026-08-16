-- 005_holdings.sql · 证券持仓明细(股票/基金/现金/融资负债),账户余额=各行合计
create table if not exists holdings (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references accounts(id),
  kind        text not null default 'stock' check (kind in ('stock','fund','cash','debt')),
  name        text not null,
  code        text default '',
  qty         numeric(16,4) not null default 0,   -- 股数/份额(cash/debt 为 1)
  cost        numeric(14,4) not null default 0,   -- 成本价
  price       numeric(14,4) not null default 0,   -- 最近记录价
  value       numeric(14,2) not null default 0,   -- 市值(debt 存负数)
  updated_at  timestamptz not null default now()
);
create index if not exists idx_holdings_acc on holdings(account_id);

alter table holdings enable row level security;
drop policy if exists auth_all on holdings;
create policy auth_all on holdings for all to authenticated using (true) with check (true);
