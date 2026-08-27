-- 018 · 物品间:电商购物→物品档案→7天退货/15/30天复盘→留用入资产/闲置变现
alter table accounts drop constraint if exists accounts_type_check;
alter table accounts add constraint accounts_type_check
  check (type = any (array['cash','bank','stock','fund','loan','property','vehicle','goods']));

create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid),
  name text not null,
  price numeric not null default 0,
  value numeric not null default 0,          -- 当前估值(留用后计入资产)
  bought_at date not null default (now() at time zone 'Asia/Shanghai')::date,
  source text default '',                    -- 抖音/淘宝/京东/线下…
  category text default '',
  tx_id uuid,                                -- 关联流水
  status text not null default 'trial' check (status in ('trial','kept','idle','selling','sold','returned','consumed')),
  sold_price numeric,
  sold_at date,
  note text default '',
  created_at timestamptz default now()
);
create index if not exists items_owner_status on items(owner, status);
alter table items enable row level security;
drop policy if exists owner_all on items;
create policy owner_all on items for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

-- 物品资产同步:留用+闲置+在卖的估值合计 → 「物品资产」账户(type=goods,沉淀资产口径)
create or replace function sync_items_asset() returns numeric
language plpgsql security definer set search_path = public as $$
declare
  o uuid := coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid);
  v numeric;
  aid uuid;
begin
  select coalesce(sum(value), 0) into v from items
    where owner = o and status in ('kept','idle','selling');
  select id into aid from accounts where owner = o and type = 'goods' limit 1;
  if aid is null then
    if v > 0 then
      insert into accounts(owner, name, type, currency, balance)
        values (o, '物品资产(在用+闲置)', 'goods', 'CNY', v);
    end if;
  else
    update accounts set balance = v where id = aid;
  end if;
  return v;
end $$;
revoke execute on function sync_items_asset() from public, anon;
grant execute on function sync_items_asset() to authenticated;
