-- 008 · 可动净资产口径:房/车资产及其对应贷款摘出主指标
-- loans.asset_backed = true 表示该贷款绑定沉淀资产(房/车),与资产一起从"可动"口径剔除
alter table loans add column if not exists asset_backed boolean not null default false;
update loans set asset_backed = true where name in ('南山房贷(经营贷370万)','武汉房贷(中海城)','问界M9车贷');

alter table net_worth_snapshots add column if not exists liquid_cny numeric(16,2);

create or replace function snapshot_net_worth() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_total numeric := 0;
  v_liquid numeric := 0;
  v_detail jsonb;
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
begin
  select coalesce(sum(case when a.type = 'loan' then -a.balance else a.balance end * f.to_cny), 0)
    into v_total
  from accounts a join fx_rates f on f.currency = a.currency
  where not a.archived;
  select v_total - coalesce((
    select sum(l.principal_remaining * f.to_cny)
    from loans l join fx_rates f on f.currency = l.currency
    where not l.archived), 0)
  into v_total;

  -- 可动口径:剔除房产/车辆账户;贷款只算未绑定资产的
  select coalesce(sum(case when a.type = 'loan' then -a.balance else a.balance end * f.to_cny), 0)
    into v_liquid
  from accounts a join fx_rates f on f.currency = a.currency
  where not a.archived and a.type not in ('property','vehicle');
  select v_liquid - coalesce((
    select sum(l.principal_remaining * f.to_cny)
    from loans l join fx_rates f on f.currency = l.currency
    where not l.archived and not l.asset_backed), 0)
  into v_liquid;

  select jsonb_object_agg(x.name, x.cny) into v_detail from (
    select a.name, round(case when a.type='loan' then -a.balance else a.balance end * f.to_cny, 2) as cny
    from accounts a join fx_rates f on f.currency = a.currency where not a.archived
    union all
    select l.name, round(-l.principal_remaining * f.to_cny, 2)
    from loans l join fx_rates f on f.currency = l.currency where not l.archived
  ) x;

  insert into net_worth_snapshots(snap_date, total_cny, liquid_cny, detail)
    values (v_today, round(v_total,2), round(v_liquid,2), coalesce(v_detail,'{}'::jsonb))
  on conflict (snap_date) do update
    set total_cny = excluded.total_cny, liquid_cny = excluded.liquid_cny, detail = excluded.detail;
  return round(v_liquid,2);
end $$;
