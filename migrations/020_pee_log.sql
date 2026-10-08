-- 儿子尿尿记录小本:口令制,表不对 anon 开放,只能走 RPC(口令不对就读不到)
create table if not exists public.pee_log (
  id bigserial primary key,
  code text not null,
  ts timestamptz not null,
  created_at timestamptz not null default now(),
  unique (code, ts)
);
alter table public.pee_log enable row level security;

create or replace function public.pl_list(p_code text) returns jsonb
language sql security definer set search_path = public as $$
  select case when length(coalesce(p_code,'')) < 12 then '[]'::jsonb
    else coalesce((select jsonb_agg((extract(epoch from ts)*1000)::bigint order by ts)
                   from pee_log where code = p_code), '[]'::jsonb) end;
$$;

create or replace function public.pl_add(p_code text, p_ms bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_code,'')) < 12 then raise exception 'bad code'; end if;
  insert into pee_log(code, ts) values (p_code, to_timestamp(p_ms/1000.0)) on conflict do nothing;
end $$;

create or replace function public.pl_del(p_code text, p_ms bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_code,'')) < 12 then raise exception 'bad code'; end if;
  delete from pee_log where code = p_code and ts = to_timestamp(p_ms/1000.0);
end $$;

revoke all on function public.pl_list(text), public.pl_add(text,bigint), public.pl_del(text,bigint) from public;
grant execute on function public.pl_list(text), public.pl_add(text,bigint), public.pl_del(text,bigint) to anon, authenticated;
