-- 003_savings.sql · 省钱记录(忍住没买/优惠券省下等,不动账户余额,独立成账)
create table if not exists savings (
  id          uuid primary key default gen_random_uuid(),
  amount      numeric(14,2) not null check (amount > 0),
  way         text not null default '其他',   -- 忍住没买/找到替代/优惠券/满减折扣/比价/其他
  note        text default '',
  saved_at    date not null default (now() at time zone 'Asia/Shanghai')::date,
  created_at  timestamptz not null default now()
);
create index if not exists idx_savings_date on savings(saved_at desc);

alter table savings enable row level security;
drop policy if exists auth_all on savings;
create policy auth_all on savings for all to authenticated using (true) with check (true);
