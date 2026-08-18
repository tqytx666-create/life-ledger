-- 014 · 修复 household_members RLS 自引用递归:成员关系判定改走 SECURITY DEFINER 函数(绕过RLS,无递归)
create or replace function my_household() returns uuid
language sql security definer stable set search_path = public as
$$ select household_id from household_members where user_id = auth.uid() limit 1 $$;

create or replace function i_am_head() returns boolean
language sql security definer stable set search_path = public as
$$ select exists(select 1 from household_members where user_id = auth.uid() and role = 'head') $$;

create or replace function is_my_family_member(p_owner uuid) returns boolean
language sql security definer stable set search_path = public as
$$ select exists(select 1 from household_members them
     where them.user_id = p_owner and them.household_id = my_household()) $$;

revoke execute on function my_household(), i_am_head(), is_my_family_member(uuid) from public, anon;
grant execute on function my_household() to authenticated;
grant execute on function i_am_head() to authenticated;
grant execute on function is_my_family_member(uuid) to authenticated;

-- 重建家庭三表策略(不再自引用)
drop policy if exists hh_member_read on households;
create policy hh_member_read on households for select to authenticated using (id = my_household());
drop policy if exists hm_same_house on household_members;
create policy hm_same_house on household_members for select to authenticated using (household_id = my_household());
drop policy if exists inv_head on invites;
create policy inv_head on invites for all to authenticated
  using (household_id = my_household() and i_am_head())
  with check (household_id = my_household() and i_am_head());

-- 重建业务表 head_read(改用函数)
do $$
declare t text;
begin
  foreach t in array array['accounts','transactions','members','batches','batch_expenses',
                           'loans','recurring','savings','save_goals','net_worth_snapshots',
                           'sec_daily','holdings','inbox_items']
  loop
    execute format('drop policy if exists head_read on %I', t);
    execute format($f$create policy head_read on %I for select to authenticated
      using (i_am_head() and is_my_family_member(%I.owner))$f$, t, t);
  end loop;
end $$;
