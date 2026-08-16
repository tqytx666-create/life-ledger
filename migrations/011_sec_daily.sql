-- 011 · 证券每日行情快照:总市值/当日盈亏/收益率(定时任务收盘后写入)
create table if not exists sec_daily (
  snap_date   date primary key,
  total       numeric(16,2) not null,
  day_pnl     numeric(14,2) not null default 0,
  day_pct     numeric(8,4) not null default 0,
  detail      jsonb not null default '{}'::jsonb
);
alter table sec_daily enable row level security;
drop policy if exists auth_all on sec_daily;
create policy auth_all on sec_daily for all to authenticated using (true) with check (true);
