-- 016 · 建议偏好:用户点✕隐藏建议,记录并静音;管家据此闭嘴
create table if not exists advice_prefs (
  owner       uuid not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid),
  key         text not null,          -- 如 tip:wsd / tip:goal:<id> / askbuy:dim:冲动指数
  hides       int not null default 1,
  muted       boolean not null default true,
  updated_at  timestamptz not null default now(),
  primary key (owner, key)
);
alter table advice_prefs enable row level security;
drop policy if exists owner_all on advice_prefs;
create policy owner_all on advice_prefs for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());
