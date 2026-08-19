-- 017 · 服务器端每日自动结算:固定转账/贷款月供到期自动入流水,不再依赖打开 App
-- pg_cron 每天 16:10 UTC(北京 00:10)跑 settle_due(),游标口径为"已结算的最后一期",天然幂等
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname = 'daily-settle-due';
select cron.schedule('daily-settle-due', '10 16 * * *', $$select public.settle_due()$$);
