-- 002_rpc.sql · 核心 RPC:原子记账/删账/每日结算/净资产快照
-- 原则: 余额变更与流水插入必须同事务;结算游标用"已结算到的最后周期",不用"今天"

-- ========== 原子记一笔 ==========
create or replace function record_tx(
  p_account_id uuid,
  p_type text,               -- income|expense|transfer|adjust
  p_amount numeric,
  p_category text default '其他',
  p_note text default '',
  p_occurred_at date default null,
  p_peer_account_id uuid default null,  -- transfer 必填
  p_batch_id uuid default null,
  p_loan_id uuid default null,
  p_recurring_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_date date := coalesce(p_occurred_at, (now() at time zone 'Asia/Shanghai')::date);
  v_gid uuid;
  v_id uuid;
  v_cur1 text; v_cur2 text;
begin
  if p_amount <= 0 then raise exception '金额必须为正'; end if;

  if p_type = 'income' then
    insert into transactions(account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id)
      values (p_account_id,'income',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id)
      returning id into v_id;
    update accounts set balance = balance + p_amount where id = p_account_id;

  elsif p_type = 'expense' then
    insert into transactions(account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id)
      values (p_account_id,'expense',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id)
      returning id into v_id;
    update accounts set balance = balance - p_amount where id = p_account_id;

  elsif p_type = 'transfer' then
    if p_peer_account_id is null then raise exception '转账缺对手账户'; end if;
    select currency into v_cur1 from accounts where id = p_account_id;
    select currency into v_cur2 from accounts where id = p_peer_account_id;
    if v_cur1 <> v_cur2 then raise exception '跨币种请分两笔记(支出+收入)'; end if;
    v_gid := gen_random_uuid();
    insert into transactions(account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid)
      values (p_account_id,'transfer_out',p_amount,p_category,p_note,v_date,p_peer_account_id,v_gid)
      returning id into v_id;
    insert into transactions(account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid)
      values (p_peer_account_id,'transfer_in',p_amount,p_category,p_note,v_date,p_account_id,v_gid);
    update accounts set balance = balance - p_amount where id = p_account_id;
    update accounts set balance = balance + p_amount where id = p_peer_account_id;

  elsif p_type = 'adjust' then
    -- 余额校准:amount 存差值绝对值,note 里说明,方向由 category 传 '+'/'-'
    insert into transactions(account_id,type,amount,category,note,occurred_at)
      values (p_account_id,'adjust',p_amount,p_category,p_note,v_date)
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

-- ========== 原子删一笔(反向回滚余额;转账删两条腿) ==========
create or replace function delete_tx(p_tx_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  r transactions;
  n int := 0;
begin
  select * into r from transactions where id = p_tx_id;
  if not found then return 0; end if;

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
  -- 月供/固定支出流水删除时回滚游标由人工处理(极少发生,避免自动改游标引入新坑)
  delete from transactions where id = p_tx_id;
  return 1;
end $$;

-- ========== 净资产快照(按当日汇率折 CNY;loan 账户与 loans 表取负) ==========
create or replace function snapshot_net_worth() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_total numeric := 0;
  v_detail jsonb;
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
begin
  select
    coalesce(sum(case when a.type = 'loan' then -a.balance else a.balance end * f.to_cny), 0)
    into v_total
  from accounts a join fx_rates f on f.currency = a.currency
  where not a.archived;

  select v_total - coalesce((
    select sum(l.principal_remaining * f.to_cny)
    from loans l join fx_rates f on f.currency = l.currency
    where not l.archived), 0)
  into v_total;

  select jsonb_object_agg(x.name, x.cny) into v_detail from (
    select a.name, round(case when a.type='loan' then -a.balance else a.balance end * f.to_cny, 2) as cny
    from accounts a join fx_rates f on f.currency = a.currency where not a.archived
    union all
    select l.name, round(-l.principal_remaining * f.to_cny, 2)
    from loans l join fx_rates f on f.currency = l.currency where not l.archived
  ) x;

  insert into net_worth_snapshots(snap_date, total_cny, detail)
    values (v_today, round(v_total,2), coalesce(v_detail,'{}'::jsonb))
  on conflict (snap_date) do update set total_cny = excluded.total_cny, detail = excluded.detail;
  return round(v_total,2);
end $$;

-- ========== 每日结算:月供 + 固定支出(游标推进,幂等,可安全重复调用) ==========
create or replace function settle_due() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  l record; r record;
  v_cursor text; v_next date;
  v_interest numeric; v_principal_part numeric;
  n_loan int := 0; n_rec int := 0;
begin
  -- 防并发双结算:拿不到锁直接跳过(另一端正在结算)
  if not pg_try_advisory_xact_lock(hashtext('settle_due')) then
    return jsonb_build_object('skipped', true);
  end if;

  -- 月供
  for l in select * from loans where not archived and pay_account_id is not null and principal_remaining > 0
  loop
    v_cursor := l.settled_through;
    if v_cursor = '' then
      -- 首次:从创建月开始,当月还款日已过则本月记,否则等下月
      v_cursor := to_char((l.created_at at time zone 'Asia/Shanghai')::date - interval '1 month', 'YYYY-MM');
    end if;
    loop
      v_next := (to_date(v_cursor || '-01', 'YYYY-MM-DD') + interval '1 month')::date
                + (l.payment_day - 1);
      exit when v_next > v_today or l.principal_remaining <= 0;
      v_interest := round(l.principal_remaining * l.rate_annual / 100 / 12, 2);
      v_principal_part := least(l.monthly_payment - v_interest, l.principal_remaining);
      if v_principal_part < 0 then v_principal_part := 0; end if;
      perform record_tx(l.pay_account_id, 'expense', l.monthly_payment,
        '房贷月供', l.name || ' 月供(本金' || v_principal_part || '+利息' || v_interest || ')',
        v_next, null, null, l.id, null);
      update loans set principal_remaining = principal_remaining - v_principal_part
        where id = l.id returning principal_remaining into l.principal_remaining;
      v_cursor := to_char(v_next, 'YYYY-MM');
      n_loan := n_loan + 1;
    end loop;
    update loans set settled_through = v_cursor where id = l.id and settled_through <> v_cursor;
  end loop;

  -- 固定支出(月付;年付按 run_month+run_day)
  for r in select * from recurring where active
  loop
    v_cursor := r.settled_through;
    if r.period = 'monthly' then
      if v_cursor = '' then
        v_cursor := to_char((r.created_at at time zone 'Asia/Shanghai')::date - interval '1 month', 'YYYY-MM');
      end if;
      loop
        v_next := (to_date(v_cursor || '-01','YYYY-MM-DD') + interval '1 month')::date + (r.run_day - 1);
        exit when v_next > v_today;
        perform record_tx(r.account_id, 'expense', r.amount, r.category,
          r.name || '(自动)', v_next, null, null, null, r.id);
        v_cursor := to_char(v_next, 'YYYY-MM');
        n_rec := n_rec + 1;
      end loop;
    else -- yearly
      if v_cursor = '' then
        v_cursor := to_char((r.created_at at time zone 'Asia/Shanghai')::date - interval '1 year', 'YYYY');
      end if;
      loop
        v_next := make_date((v_cursor)::int + 1, coalesce(r.run_month,1), r.run_day);
        exit when v_next > v_today;
        perform record_tx(r.account_id, 'expense', r.amount, r.category,
          r.name || '(自动·年付)', v_next, null, null, null, r.id);
        v_cursor := to_char(v_next, 'YYYY');
        n_rec := n_rec + 1;
      end loop;
    end if;
    update recurring set settled_through = v_cursor where id = r.id and settled_through <> v_cursor;
  end loop;

  perform snapshot_net_worth();
  return jsonb_build_object('loan_payments', n_loan, 'recurring_charged', n_rec);
end $$;

-- ========== 提前还款 ==========
create or replace function prepay_loan(p_loan_id uuid, p_amount numeric, p_note text default '')
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  l loans;
  v_pay numeric;
begin
  select * into l from loans where id = p_loan_id;
  if not found then raise exception '贷款不存在'; end if;
  v_pay := least(p_amount, l.principal_remaining);
  perform record_tx(l.pay_account_id, 'expense', v_pay, '提前还款',
    l.name || ' 提前还款 ' || coalesce(nullif(p_note,''),''), null, null, null, p_loan_id, null);
  update loans set principal_remaining = principal_remaining - v_pay where id = p_loan_id;
  perform snapshot_net_worth();
  return (select principal_remaining from loans where id = p_loan_id);
end $$;

-- 仅 authenticated 可调用
revoke execute on function record_tx(uuid,text,numeric,text,text,date,uuid,uuid,uuid,uuid) from public, anon;
revoke execute on function delete_tx(uuid) from public, anon;
revoke execute on function settle_due() from public, anon;
revoke execute on function snapshot_net_worth() from public, anon;
revoke execute on function prepay_loan(uuid,numeric,text) from public, anon;
grant execute on function record_tx(uuid,text,numeric,text,text,date,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function delete_tx(uuid) to authenticated;
grant execute on function settle_due() to authenticated;
grant execute on function snapshot_net_worth() to authenticated;
grant execute on function prepay_loan(uuid,numeric,text) to authenticated;
