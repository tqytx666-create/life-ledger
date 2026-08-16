-- 010 · 随手拍收件箱:图片/语音/文字先存后台,南哥回家后由 Claude 识别入账
insert into storage.buckets (id, name, public)
values ('inbox', 'inbox', false)
on conflict (id) do nothing;

drop policy if exists inbox_auth_all on storage.objects;
create policy inbox_auth_all on storage.objects
  for all to authenticated
  using (bucket_id = 'inbox') with check (bucket_id = 'inbox');

create table if not exists inbox_items (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('image','audio','text')),
  path        text not null default '',   -- storage 路径(text 类型为空)
  note        text not null default '',   -- 他随手补的一句话/或 text 类型的正文
  status      text not null default 'pending' check (status in ('pending','done','skipped')),
  result      text not null default '',   -- 处理结果说明(记了哪笔)
  created_at  timestamptz not null default now()
);
alter table inbox_items enable row level security;
drop policy if exists auth_all on inbox_items;
create policy auth_all on inbox_items for all to authenticated using (true) with check (true);
