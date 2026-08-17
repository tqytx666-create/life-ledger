-- 012 · 多用户数据隔离:所有业务表加 owner,RLS 按 auth.uid() 过滤
-- 背景:要开演示账号/家人账号,不能再"登录即全权"。南哥 uid: be833ea5-699a-4513-8f0a-a821fd663465
-- fx_rates 保持全局共享(汇率是客观数据),但只允许南哥改

do $$
declare
  t text;
  nange constant uuid := 'be833ea5-699a-4513-8f0a-a821fd663465';
begin
  foreach t in array array['accounts','transactions','members','batches','batch_expenses',
                           'loans','recurring','savings','save_goals','net_worth_snapshots',
                           'sec_daily','holdings','inbox_items']
  loop
    -- 加 owner:默认取登录者;service_role(auth.uid() 为空)时回落到南哥
    execute format($f$alter table %I add column if not exists owner uuid
      not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid)$f$, t);
    execute format('update %I set owner = %L where owner is null', t, nange);
    -- RLS 改为按 owner
    execute format('drop policy if exists auth_all on %I', t);
    execute format($f$create policy owner_all on %I for all to authenticated
      using (owner = auth.uid()) with check (owner = auth.uid())$f$, t);
  end loop;
end $$;

-- 快照表主键改为 (owner, snap_date)
alter table net_worth_snapshots drop constraint if exists net_worth_snapshots_pkey;
alter table net_worth_snapshots add primary key (owner, snap_date);
alter table sec_daily drop constraint if exists sec_daily_pkey;
alter table sec_daily add primary key (owner, snap_date);

-- 汇率:所有人可读,只有南哥可写
drop policy if exists auth_all on fx_rates;
drop policy if exists fx_read on fx_rates;
drop policy if exists fx_write on fx_rates;
create policy fx_read on fx_rates for select to authenticated using (true);
create policy fx_write on fx_rates for all to authenticated
  using (auth.uid() = 'be833ea5-699a-4513-8f0a-a821fd663465')
  with check (auth.uid() = 'be833ea5-699a-4513-8f0a-a821fd663465');

-- ===== record_tx:owner 从账户继承,并校验调用者只能动自己的账户 =====
create or replace function record_tx(
  p_account_id uuid, p_type text, p_amount numeric,
  p_category text default '其他', p_note text default '',
  p_occurred_at date default null, p_peer_account_id uuid default null,
  p_batch_id uuid default null, p_loan_id uuid default null,
  p_recurring_id uuid default null, p_import_id text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_date date := coalesce(p_occurred_at, (now() at time zone 'Asia/Shanghai')::date);
  v_gid uuid; v_id uuid;
  v_cur1 text; v_cur2 text;
  v_owner uuid;
begin
  if p_amount <= 0 then raise exception '金额必须为正'; end if;
  select owner, currency into v_owner, v_cur1 from accounts where id = p_account_id;
  if v_owner is null then raise exception '账户不存在'; end if;
  if auth.uid() is not null and v_owner <> auth.uid() then raise exception '无权操作该账户'; end if;

  if p_import_id is not null then
    select id into v_id from transactions
      where owner = v_owner and import_id in (p_import_id, p_import_id || '-out') limit 1;
    if found then return v_id; end if;
  end if;

  if p_type = 'income' then
    insert into transactions(owner,account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id,import_id)
      values (v_owner,p_account_id,'income',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id,p_import_id)
      returning id into v_id;
    update accounts set balance = balance + p_amount where id = p_account_id;
  elsif p_type = 'expense' then
    insert into transactions(owner,account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id,import_id)
      values (v_owner,p_account_id,'expense',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id,p_import_id)
      returning id into v_id;
    update accounts set balance = balance - p_amount where id = p_account_id;
  elsif p_type = 'transfer' then
    if p_peer_account_id is null then raise exception '转账缺对手账户'; end if;
    select currency into v_cur2 from accounts where id = p_peer_account_id and owner = v_owner;
    if v_cur2 is null then raise exception '对手账户不存在或不属于同一用户'; end if;
    if v_cur1 <> v_cur2 then raise exception '跨币种请分两笔记(支出+收入)'; end if;
    v_gid := gen_random_uuid();
    insert into transactions(owner,account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid,import_id)
      values (v_owner,p_account_id,'transfer_out',p_amount,p_category,p_note,v_date,p_peer_account_id,v_gid,
              case when p_import_id is null then null else p_import_id || '-out' end)
      returning id into v_id;
    insert into transactions(owner,account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid,import_id)
      values (v_owner,p_peer_account_id,'transfer_in',p_amount,p_category,p_note,v_date,p_account_id,v_gid,
              case when p_import_id is null then null else p_import_id || '-in' end);
    update accounts set balance = balance - p_amount where id = p_account_id;
    update accounts set balance = balance + p_amount where id = p_peer_account_id;
  elsif p_type = 'adjust' then
    insert into transactions(owner,account_id,type,amount,category,note,occurred_at,import_id)
      values (v_owner,p_account_id,'adjust',p_amount,p_category,p_note,v_date,p_import_id)
      returning id into v_id;
    if p_category = '-' then
      update accounts set balance = balance - p_amount where id = p_account_id;
    else
      update accounts set balance = balance + p_amount where id = p_account_id;
    end if;
  else
    raise exception '未知类型 %', p_type;
  end if;
  return v_id;
end $$;

-- ===== delete_tx:校验归属 =====
create or replace function delete_tx(p_tx_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  r transactions; n int := 0;
begin
  select * into r from transactions where id = p_tx_id;
  if not found then return 0; end if;
  if auth.uid() is not null and r.owner <> auth.uid() then raise exception '无权操作'; end if;

  if r.transfer_gid is not null then
    for r in select * from transactions where transfer_gid = (select transfer_gid from transactions where id = p_tx_id)
    loop
      if r.type = 'transfer_out' then
        update accounts set balance = balance + r.amount where id = r.account_id;
      else
        update accounts set balance = balance - r.amount where id = r.account_id;
      end if;
      delete from transactions where id = r.id;
      n := n + 1;
    end loop;
    return n;
  end if;

  if r.type = 'income' then
    update accounts set balance = balance - r.amount where id = r.account_id;
  elsif r.type = 'expense' then
    update accounts set balance = balance + r.amount where id = r.account_id;
  elsif r.type = 'adjust' then
    if r.category = '-' then
      update accounts set balance = balance + r.amount where id = r.account_id;
    else
      update accounts set balance = balance - r.amount where id = r.account_id;
    end if;
  end if;
  delete from transactions where id = p_tx_id;
  return 1;
end $$;

-- ===== snapshot_net_worth:逐 owner 分别快照 =====
create or replace function snapshot_net_worth() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  o record;
  v_total numeric; v_liquid numeric; v_detail jsonb;
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  v_ret numeric := 0;
begin
  for o in select distinct owner from accounts
  loop
    select coalesce(sum(case when a.type = 'loan' then -a.balance else a.balance end * f.to_cny), 0)
      into v_total
    from accounts a join fx_rates f on f.currency = a.currency
    where not a.archived and a.owner = o.owner;
    select v_total - coalesce((select sum(l.principal_remaining * f.to_cny)
      from loans l join fx_rates f on f.currency = l.currency
      where not l.archived and l.owner = o.owner), 0) into v_total;

    select coalesce(sum(case when a.type = 'loan' then -a.balance else a.balance end * f.to_cny), 0)
      into v_liquid
    from accounts a join fx_rates f on f.currency = a.currency
    where not a.archived and a.owner = o.owner and a.type not in ('property','vehicle');
    select v_liquid - coalesce((select sum(l.principal_remaining * f.to_cny)
      from loans l join fx_rates f on f.currency = l.currency
      where not l.archived and not l.asset_backed and l.owner = o.owner), 0) into v_liquid;

    select jsonb_object_agg(x.name, x.cny) into v_detail from (
      select a.name, round(case when a.type='loan' then -a.balance else a.balance end * f.to_cny, 2) as cny
      from accounts a join fx_rates f on f.currency = a.currency
      where not a.archived and a.owner = o.owner
      union all
      select l.name, round(-l.principal_remaining * f.to_cny, 2)
      from loans l join fx_rates f on f.currency = l.currency
      where not l.archived and l.owner = o.owner
    ) x;

    insert into net_worth_snapshots(owner, snap_date, total_cny, liquid_cny, detail)
      values (o.owner, v_today, round(v_total,2), round(v_liquid,2), coalesce(v_detail,'{}'::jsonb))
    on conflict (owner, snap_date) do update
      set total_cny = excluded.total_cny, liquid_cny = excluded.liquid_cny, detail = excluded.detail;

    if auth.uid() is not null and o.owner = auth.uid() then v_ret := round(v_liquid,2); end if;
    if auth.uid() is null and o.owner = 'be833ea5-699a-4513-8f0a-a821fd663465' then v_ret := round(v_liquid,2); end if;
  end loop;
  return v_ret;
end $$;

-- ===== prepay_loan:校验归属 =====
create or replace function prepay_loan(p_loan_id uuid, p_amount numeric, p_note text default '')
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  l loans; v_pay numeric;
begin
  select * into l from loans where id = p_loan_id;
  if not found then raise exception '贷款不存在'; end if;
  if auth.uid() is not null and l.owner <> auth.uid() then raise exception '无权操作'; end if;
  v_pay := least(p_amount, l.principal_remaining);
  perform record_tx(l.pay_account_id, 'expense', v_pay, '提前还款',
    l.name || ' 提前还款 ' || coalesce(nullif(p_note,''),''), null, null, null, p_loan_id, null);
  update loans set principal_remaining = principal_remaining - v_pay where id = p_loan_id;
  perform snapshot_net_worth();
  return (select principal_remaining from loans where id = p_loan_id);
end $$;
