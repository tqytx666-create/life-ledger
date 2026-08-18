-- 016 · 建议偏好:用户隐藏过的建议类型,记次数并静音,管家学会闭嘴
create table if not exists advice_prefs (
  owner      uuid not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid),
  key        text not null,            -- 如 askbuy:dim:冲动指数
  hides      int not null default 1,   -- 累计隐藏次数
  muted      boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (owner, key)
);
alter table advice_prefs enable row level security;
drop policy if exists owner_all on advice_prefs;
create policy owner_all on advice_prefs for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());
