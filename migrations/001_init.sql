-- 001_init.sql · AI 记账本(人生总账本) 初始 schema
-- 项目: oznaumvwecurqmfjqwne (ap-southeast-1) · 2026-08-17
-- 原则: 真实资金数据,RLS 默认拒绝,仅登录用户(authenticated)可读写

-- ========== 账户 ==========
create table if not exists accounts (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  type        text not null check (type in ('cash','bank','stock','fund','loan')),
  currency    text not null default 'CNY' check (currency in ('CNY','HKD','USD')),
  balance     numeric(14,2) not null default 0,   -- loan 类型存剩余本金(负债,存正数,折算时取负)
  note        text default '',
  sort        int not null default 0,
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ========== 流水 ==========
create table if not exists transactions (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references accounts(id),
  type          text not null check (type in ('income','expense','transfer_out','transfer_in','adjust')),
  amount        numeric(14,2) not null check (amount >= 0), -- 恒为正,方向看 type
  category      text not null default '其他',
  note          text default '',
  occurred_at   date not null default (now() at time zone 'Asia/Shanghai')::date,
  peer_account_id uuid references accounts(id),  -- 转账对手方
  transfer_gid  uuid,                            -- 同一笔转账两条腿共用
  batch_id      uuid,                            -- 关联家庭批次(给钱那笔)
  loan_id       uuid,                            -- 关联贷款(月供/提前还款)
  recurring_id  uuid,                            -- 关联固定支出(自动记账来源)
  created_at    timestamptz not null default now()
);
create index if not exists idx_tx_account on transactions(account_id, occurred_at desc);
create index if not exists idx_tx_date on transactions(occurred_at desc);

-- ========== 家庭成员 ==========
create table if not exists members (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  relation    text not null default '',   -- 配偶/孩子/父母…
  sort        int not null default 0,
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ========== 给钱批次 ==========
create table if not exists batches (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid not null references members(id),
  title       text not null default '',            -- 如"2026年8月生活费"
  amount      numeric(14,2) not null check (amount > 0),
  currency    text not null default 'CNY' check (currency in ('CNY','HKD','USD')),
  given_at    date not null default (now() at time zone 'Asia/Shanghai')::date,
  note        text default '',
  closed      boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists idx_batches_member on batches(member_id, given_at desc);

-- 批次内花销(家人报的账,不动户主自己账户,只扣批次剩余预估)
create table if not exists batch_expenses (
  id          uuid primary key default gen_random_uuid(),
  batch_id    uuid not null references batches(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0),
  note        text default '',
  spent_at    date not null default (now() at time zone 'Asia/Shanghai')::date,
  created_at  timestamptz not null default now()
);
create index if not exists idx_bexp_batch on batch_expenses(batch_id, spent_at desc);

-- ========== 按揭贷款 ==========
create table if not exists loans (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  currency            text not null default 'CNY' check (currency in ('CNY','HKD','USD')),
  principal_remaining numeric(14,2) not null,          -- 剩余本金
  rate_annual         numeric(7,4) not null default 0, -- 年利率 % (如 3.55)
  monthly_payment     numeric(14,2) not null,          -- 月供
  payment_day         int not null default 1 check (payment_day between 1 and 28),
  pay_account_id      uuid references accounts(id),    -- 从哪个账户扣月供
  -- 每月结算游标: 已结算到的最后一个月(YYYY-MM)。用游标不用"今天",防漏结算
  settled_through     text not null default '',
  note                text default '',
  archived            boolean not null default false,
  created_at          timestamptz not null default now()
);

-- ========== 固定支出 ==========
create table if not exists recurring (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,               -- 订阅/保险/房租…
  amount      numeric(14,2) not null check (amount > 0),
  currency    text not null default 'CNY' check (currency in ('CNY','HKD','USD')),
  category    text not null default '固定支出',
  account_id  uuid not null references accounts(id),
  period      text not null default 'monthly' check (period in ('monthly','yearly')),
  run_day     int not null default 1 check (run_day between 1 and 28),  -- 每月几号(yearly 时配 run_month)
  run_month   int check (run_month between 1 and 12),
  -- 游标: 已生成到的最后周期(monthly=YYYY-MM, yearly=YYYY)
  settled_through text not null default '',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ========== 汇率(可编辑,折 CNY) ==========
create table if not exists fx_rates (
  currency    text primary key check (currency in ('CNY','HKD','USD')),
  to_cny      numeric(12,6) not null,
  updated_at  timestamptz not null default now()
);
insert into fx_rates(currency, to_cny) values
  ('CNY', 1), ('HKD', 0.92), ('USD', 7.12)
on conflict (currency) do nothing;

-- ========== 净资产快照(仪表盘走势) ==========
create table if not exists net_worth_snapshots (
  snap_date   date primary key,
  total_cny   numeric(16,2) not null,
  detail      jsonb not null default '{}'::jsonb  -- 各账户折算明细
);

-- ========== RLS: 默认拒绝,仅 authenticated 全权 ==========
do $$
declare t text;
begin
  foreach t in array array['accounts','transactions','members','batches','batch_expenses','loans','recurring','fx_rates','net_worth_snapshots']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists auth_all on %I', t);
    execute format($p$create policy auth_all on %I for all to authenticated using (true) with check (true)$p$, t);
  end loop;
end $$;
