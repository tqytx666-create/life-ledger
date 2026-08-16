-- 006 · ① 固定支出支持内部转账(peer_account_id) ② 账户类型扩展房产/车辆
alter table recurring add column if not exists peer_account_id uuid references accounts(id);

alter table accounts drop constraint if exists accounts_type_check;
alter table accounts add constraint accounts_type_check
  check (type in ('cash','bank','stock','fund','loan','property','vehicle'));

-- settle_due:固定项带 peer 时记转账(自己卡到卡,不算消费),否则记支出
create or replace function settle_due() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  l record; r record;
  v_cursor text; v_next date;
  v_interest numeric; v_principal_part numeric;
  n_loan int := 0; n_rec int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('settle_due')) then
    return jsonb_build_object('skipped', true);
  end if;

  for l in select * from loans where not archived and pay_account_id is not null and principal_remaining > 0
  loop
    v_cursor := l.settled_through;
    if v_cursor = '' then
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
        if r.peer_account_id is not null then
          perform record_tx(r.account_id, 'transfer', r.amount, '转账',
            r.name || '(自动)', v_next, r.peer_account_id, null, null, r.id);
        else
          perform record_tx(r.account_id, 'expense', r.amount, r.category,
            r.name || '(自动)', v_next, null, null, null, r.id);
        end if;
        v_cursor := to_char(v_next, 'YYYY-MM');
        n_rec := n_rec + 1;
      end loop;
    else
      if v_cursor = '' then
        v_cursor := to_char((r.created_at at time zone 'Asia/Shanghai')::date - interval '1 year', 'YYYY');
      end if;
      loop
        v_next := make_date((v_cursor)::int + 1, coalesce(r.run_month,1), r.run_day);
        exit when v_next > v_today;
        if r.peer_account_id is not null then
          perform record_tx(r.account_id, 'transfer', r.amount, '转账',
            r.name || '(自动·年付)', v_next, r.peer_account_id, null, null, r.id);
        else
          perform record_tx(r.account_id, 'expense', r.amount, r.category,
            r.name || '(自动·年付)', v_next, null, null, null, r.id);
        end if;
        v_cursor := to_char(v_next, 'YYYY');
        n_rec := n_rec + 1;
      end loop;
    end if;
    update recurring set settled_through = v_cursor where id = r.id and settled_through <> v_cursor;
  end loop;

  perform snapshot_net_worth();
  return jsonb_build_object('loan_payments', n_loan, 'recurring_charged', n_rec);
end $$;
