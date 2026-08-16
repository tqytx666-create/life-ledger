-- 004_import_id.sql · 账单导入去重:流水带上原平台交易单号,重复导入自动跳过
alter table transactions add column if not exists import_id text;
create unique index if not exists idx_tx_import on transactions(import_id) where import_id is not null;

-- record_tx 加可选 p_import_id:已存在同单号直接返回旧 id(幂等),转账两条腿分别带 -out/-in 后缀
create or replace function record_tx(
  p_account_id uuid,
  p_type text,
  p_amount numeric,
  p_category text default '其他',
  p_note text default '',
  p_occurred_at date default null,
  p_peer_account_id uuid default null,
  p_batch_id uuid default null,
  p_loan_id uuid default null,
  p_recurring_id uuid default null,
  p_import_id text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_date date := coalesce(p_occurred_at, (now() at time zone 'Asia/Shanghai')::date);
  v_gid uuid;
  v_id uuid;
  v_cur1 text; v_cur2 text;
begin
  if p_amount <= 0 then raise exception '金额必须为正'; end if;

  if p_import_id is not null then
    select id into v_id from transactions where import_id in (p_import_id, p_import_id || '-out') limit 1;
    if found then return v_id; end if;  -- 幂等:已导入过
  end if;

  if p_type = 'income' then
    insert into transactions(account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id,import_id)
      values (p_account_id,'income',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id,p_import_id)
      returning id into v_id;
    update accounts set balance = balance + p_amount where id = p_account_id;

  elsif p_type = 'expense' then
    insert into transactions(account_id,type,amount,category,note,occurred_at,batch_id,loan_id,recurring_id,import_id)
      values (p_account_id,'expense',p_amount,p_category,p_note,v_date,p_batch_id,p_loan_id,p_recurring_id,p_import_id)
      returning id into v_id;
    update accounts set balance = balance - p_amount where id = p_account_id;

  elsif p_type = 'transfer' then
    if p_peer_account_id is null then raise exception '转账缺对手账户'; end if;
    select currency into v_cur1 from accounts where id = p_account_id;
    select currency into v_cur2 from accounts where id = p_peer_account_id;
    if v_cur1 <> v_cur2 then raise exception '跨币种请分两笔记(支出+收入)'; end if;
    v_gid := gen_random_uuid();
    insert into transactions(account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid,import_id)
      values (p_account_id,'transfer_out',p_amount,p_category,p_note,v_date,p_peer_account_id,v_gid,
              case when p_import_id is null then null else p_import_id || '-out' end)
      returning id into v_id;
    insert into transactions(account_id,type,amount,category,note,occurred_at,peer_account_id,transfer_gid,import_id)
      values (p_peer_account_id,'transfer_in',p_amount,p_category,p_note,v_date,p_account_id,v_gid,
              case when p_import_id is null then null else p_import_id || '-in' end);
    update accounts set balance = balance - p_amount where id = p_account_id;
    update accounts set balance = balance + p_amount where id = p_peer_account_id;

  elsif p_type = 'adjust' then
    insert into transactions(account_id,type,amount,category,note,occurred_at,import_id)
      values (p_account_id,'adjust',p_amount,p_category,p_note,v_date,p_import_id)
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

revoke execute on function record_tx(uuid,text,numeric,text,text,date,uuid,uuid,uuid,uuid,text) from public, anon;
grant execute on function record_tx(uuid,text,numeric,text,text,date,uuid,uuid,uuid,uuid,text) to authenticated;
