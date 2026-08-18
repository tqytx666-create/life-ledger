-- 017 · 管家日记(ledger_journal):账本大事记,是管家的长期记忆
create table if not exists ledger_journal (
  id      uuid primary key default gen_random_uuid(),
  owner   uuid not null default coalesce(auth.uid(), 'be833ea5-699a-4513-8f0a-a821fd663465'::uuid),
  at      date not null default (now() at time zone 'Asia/Shanghai')::date,
  kind    text not null default 'event',  -- event|decision|alert|weekly_report
  content text not null
);
create index if not exists idx_journal_owner_at on ledger_journal(owner, at desc);
alter table ledger_journal enable row level security;
drop policy if exists owner_all on ledger_journal;
create policy owner_all on ledger_journal for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());
