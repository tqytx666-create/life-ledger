-- 015 · 图片识别:收件箱存识别草稿;流水加"已核验"标记(图片识别入账默认未核验,取件员复核后置真)
alter table inbox_items add column if not exists draft jsonb;
alter table transactions add column if not exists verified boolean not null default true;
