-- 013 · 家庭(户)层:一个家庭一个家主,成员各记各的,家主看全局;支持邀请加入
create table if not exists households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null default '我的家',
  created_at  timestamptz not null default now()
);
create table if not exists household_members (
  household_id uuid not null references households(id),
  user_id      uuid not null,
  role         text not null default 'member' check (role in ('head','member')),
  display_name text not null default '成员',
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);
create unique index if not exists idx_hm_user on household_members(user_id);  -- 一人一户(v1)
create table if not exists invites (
  code         text primary key,
  household_id uuid not null references households(id),
  created_by   uuid not null,
  expires_at   timestamptz not null default now() + interval '7 days',
  used_by      uuid
);

alter table households enable row level security;
alter table household_members enable row level security;
alter table invites enable row level security;
create policy hh_member_read on households for select to authenticated
  using (exists (select 1 from household_members m where m.household_id = id and m.user_id = auth.uid()));
create policy hm_same_house on household_members for select to authenticated
  using (exists (select 1 from household_members me where me.household_id = household_id and me.user_id = auth.uid()));
create policy inv_head on invites for all to authenticated
  using (exists (select 1 from household_members m where m.household_id = invites.household_id and m.user_id = auth.uid() and m.role='head'))
  with check (exists (select 1 from household_members m where m.household_id = invites.household_id and m.user_id = auth.uid() and m.role='head'));

-- 业务表加"家主可读本家庭成员数据"策略
do $$
declare t text;
begin
  foreach t in array array['accounts','transactions','members','batches','batch_expenses',
                           'loans','recurring','savings','save_goals','net_worth_snapshots',
                           'sec_daily','holdings','inbox_items']
  loop
    execute format('drop policy if exists head_read on %I', t);
    execute format($f$create policy head_read on %I for select to authenticated
      using (exists (
        select 1 from household_members me
        join household_members them on them.household_id = me.household_id
        where me.user_id = auth.uid() and me.role = 'head' and them.user_id = %I.owner))$f$, t, t);
  end loop;
end $$;

-- 登录后确保有归属:有邀请码则入伙为成员,否则自立门户当家主(幂等)
create or replace function ensure_household(p_display text default null, p_invite text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_hid uuid; v_role text; v_name text;
  v_inv invites;
begin
  if v_uid is null then raise exception '未登录'; end if;
  select household_id, role into v_hid, v_role from household_members where user_id = v_uid;
  if found then
    select name into v_name from households where id = v_hid;
    return jsonb_build_object('household_id', v_hid, 'name', v_name, 'role', v_role);
  end if;

  if p_invite is not null and p_invite <> '' then
    select * into v_inv from invites where code = upper(p_invite) and used_by is null and expires_at > now();
    if not found then raise exception '邀请码无效或已过期'; end if;
    insert into household_members(household_id, user_id, role, display_name)
      values (v_inv.household_id, v_uid, 'member', coalesce(nullif(p_display,''), '成员'));
    update invites set used_by = v_uid where code = v_inv.code;
    select name into v_name from households where id = v_inv.household_id;
    return jsonb_build_object('household_id', v_inv.household_id, 'name', v_name, 'role', 'member');
  end if;

  v_name := coalesce(nullif(p_display,''), '我') || '的家';
  insert into households(name) values (v_name) returning id into v_hid;
  insert into household_members(household_id, user_id, role, display_name)
    values (v_hid, v_uid, 'head', coalesce(nullif(p_display,''), '家主'));
  return jsonb_build_object('household_id', v_hid, 'name', v_name, 'role', 'head');
end $$;

-- 家主生成邀请码
create or replace function create_invite() returns text
language plpgsql security definer set search_path = public as $$
declare
  v_hid uuid; v_code text;
begin
  select household_id into v_hid from household_members where user_id = auth.uid() and role = 'head';
  if not found then raise exception '只有家主能生成邀请码'; end if;
  v_code := upper(substr(md5(random()::text), 1, 6));
  insert into invites(code, household_id, created_by) values (v_code, v_hid, auth.uid());
  return v_code;
end $$;

-- 家主全家视图:各成员净值与本月收支
create or replace function household_overview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_hid uuid; v_role text; v_name text;
  v_members jsonb := '[]'::jsonb;
  m record;
  v_liquid numeric; v_in numeric; v_out numeric;
  v_month text := to_char(now() at time zone 'Asia/Shanghai', 'YYYY-MM');
begin
  select household_id, role into v_hid, v_role from household_members where user_id = v_uid;
  if not found then return jsonb_build_object('role', null); end if;
  select name into v_name from households where id = v_hid;

  if v_role = 'head' then
    for m in select user_id, display_name, role from household_members where household_id = v_hid order by role desc, joined_at
    loop
      select coalesce(sum(case when a.type='loan' then -a.balance else a.balance end * f.to_cny),0) into v_liquid
        from accounts a join fx_rates f on f.currency=a.currency
        where a.owner = m.user_id and not a.archived and a.type not in ('property','vehicle');
      select v_liquid - coalesce((select sum(l.principal_remaining * f.to_cny)
        from loans l join fx_rates f on f.currency=l.currency
        where l.owner = m.user_id and not l.archived and not l.asset_backed),0) into v_liquid;
      select coalesce(sum(case when t.type='income' then t.amount * f.to_cny end),0),
             coalesce(sum(case when t.type='expense' then t.amount * f.to_cny end),0)
        into v_in, v_out
        from transactions t join accounts a on a.id = t.account_id join fx_rates f on f.currency=a.currency
        where t.owner = m.user_id and to_char(t.occurred_at,'YYYY-MM') = v_month;
      v_members := v_members || jsonb_build_object(
        'display_name', m.display_name, 'role', m.role,
        'liquid', round(v_liquid,2), 'month_income', round(v_in,2), 'month_expense', round(v_out,2));
    end loop;
  end if;
  return jsonb_build_object('household', v_name, 'role', v_role, 'members', v_members);
end $$;

revoke execute on function ensure_household(text,text) from public, anon;
revoke execute on function create_invite() from public, anon;
revoke execute on function household_overview() from public, anon;
grant execute on function ensure_household(text,text) to authenticated;
grant execute on function create_invite() to authenticated;
grant execute on function household_overview() to authenticated;

-- 存量用户落户:南哥(家主)、演示号(自立门户)
do $$
declare
  nange constant uuid := 'be833ea5-699a-4513-8f0a-a821fd663465';
  demo  constant uuid := 'b83ab0a5-7ea4-4528-8836-6f9fff36d4f7';
  h uuid;
begin
  if not exists (select 1 from household_members where user_id = nange) then
    insert into households(name) values ('南哥的家') returning id into h;
    insert into household_members(household_id, user_id, role, display_name) values (h, nange, 'head', '南哥');
  end if;
  if not exists (select 1 from household_members where user_id = demo) then
    insert into households(name) values ('演示之家') returning id into h;
    insert into household_members(household_id, user_id, role, display_name) values (h, demo, 'head', '演示用户');
  end if;
end $$;
