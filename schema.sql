-- ============================================================
-- 近场偶遇留言板 (Near-Field Encounter Board)
-- Supabase schema. Run in SQL editor of a fresh project.
-- All statements are idempotent (safe to re-run).
-- ============================================================

-- 1. 启用 pgcrypto 以使用 gen_random_uuid()
create extension if not exists "pgcrypto";

-- 2. encounters 表（留言）
create table if not exists public.nearby_encounters (
  id          uuid        primary key default gen_random_uuid(),
  content     text        not null,
  latitude    float8      not null,
  longitude   float8      not null,
  session_id  text        not null,
  nickname    text        not null,
  bio         text,
  links       jsonb       not null default '[]'::jsonb,
  tags        jsonb       not null default '[]'::jsonb,
  created_at  timestamptz not null default now()
);

-- 给老表补新列（如果表是旧版跑出来的）
alter table public.nearby_encounters
  add column if not exists links jsonb not null default '[]'::jsonb;

-- tags 列迁移：旧版是 text[]，新版是 jsonb（[{tag, items[]}]）
-- 如果列不存在 → 加上 jsonb 版（前端写这个）
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'nearby_encounters' and column_name = 'tags'
        and data_type = 'jsonb'
  ) then
    -- 旧 text[] 列还在的话，先建一个新列并存数据
    alter table public.nearby_encounters add column tags_jsonb_new jsonb not null default '[]'::jsonb;
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'nearby_encounters'
        and column_name = 'tags' and data_type = 'ARRAY'
    ) then
      update public.nearby_encounters
      set tags_jsonb_new = (
        select coalesce(jsonb_agg(jsonb_build_object('tag', t, 'items', '[]'::jsonb)), '[]'::jsonb)
        from unnest(tags) as t
      );
    end if;
  end if;
end$$;

-- 把 tags 列改成 jsonb（如果还是 text[]）
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'nearby_encounters'
      and column_name = 'tags' and data_type = 'ARRAY'
  ) then
    -- 用临时列替换
    alter table public.nearby_encounters drop column tags;
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'nearby_encounters'
        and column_name = 'tags_jsonb_new'
    ) then
      alter table public.nearby_encounters rename column tags_jsonb_new to tags;
    else
      alter table public.nearby_encounters add column tags jsonb not null default '[]'::jsonb;
    end if;
  end if;
end$$;

-- 索引
create index if not exists nearby_encounters_created_at_idx
  on public.nearby_encounters (created_at desc);

-- RLS + 策略
alter table public.nearby_encounters enable row level security;

drop policy if exists "nearby_encounters_select_anon" on public.nearby_encounters;
create policy "nearby_encounters_select_anon"
  on public.nearby_encounters
  for select
  to anon
  using (true);

drop policy if exists "nearby_encounters_insert_anon" on public.nearby_encounters;
create policy "nearby_encounters_insert_anon"
  on public.nearby_encounters
  for insert
  to anon
  with check (true);

-- ============================================================
-- 3. profiles 表（个人主页 / 头像 / 最新身份）
-- ============================================================
create table if not exists public.profiles (
  session_id      text        primary key,
  nickname        text,
  bio             text,
  tags            text[]      not null default '{}'::text[],
  links           jsonb       not null default '[]'::jsonb,
  platform_labels jsonb       not null default '{}'::jsonb,
  avatar_url      text,
  updated_at      timestamptz not null default now()
);

-- 给老 profiles 表补列（如果存在但字段不全）
alter table public.profiles
  add column if not exists session_id text;
alter table public.profiles
  add column if not exists nickname text;
alter table public.profiles
  add column if not exists bio text;
alter table public.profiles
  add column if not exists tags text[] not null default '{}'::text[];
alter table public.profiles
  add column if not exists links jsonb not null default '[]'::jsonb;
alter table public.profiles
  add column if not exists avatar_url text;
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now();

-- 平台名覆盖表：用户把 "微信" 改名为 "Instagram" 等
alter table public.profiles
  add column if not exists platform_labels jsonb not null default '{}'::jsonb;

-- 确保 session_id 是主键（如果是老表，先 drop 任何现存的主键约束再加）
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_pkey' and conrelid = 'public.profiles'::regclass
  ) then
    -- 先 drop 老的主键（如果存在其他名字）
    execute (
      select 'alter table public.profiles drop constraint ' || quote_ident(c.conname)
      from pg_constraint c
      where c.conrelid = 'public.profiles'::regclass and c.contype = 'p'
      limit 1
    );
    alter table public.profiles add primary key (session_id);
  end if;
end$$;

-- nickname 不强制 NOT NULL（兼容老数据），但前端会强制

-- 索引（用 do $$ 包裹，避免老表无 nickname 列时炸）
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'nickname'
  ) then
    create index if not exists profiles_nickname_idx on public.profiles (nickname);
  end if;
end$$;

-- RLS
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_anon" on public.profiles;
create policy "profiles_select_anon"
  on public.profiles
  for select
  to anon
  using (true);

drop policy if exists "profiles_insert_anon" on public.profiles;
create policy "profiles_insert_anon"
  on public.profiles
  for insert
  to anon
  with check (true);

drop policy if exists "profiles_update_anon" on public.profiles;
create policy "profiles_update_anon"
  on public.profiles
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "profiles_delete_anon" on public.profiles;
create policy "profiles_delete_anon"
  on public.profiles
  for delete
  to anon
  using (true);

-- ============================================================
-- 4. 头像存储桶 avatars
-- ============================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_read_public" on storage.objects;
create policy "avatars_read_public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'avatars');

drop policy if exists "avatars_write_anon" on storage.objects;
create policy "avatars_write_anon"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'avatars');

drop policy if exists "avatars_update_anon" on storage.objects;
create policy "avatars_update_anon"
  on storage.objects
  for update
  to anon
  using (bucket_id = 'avatars')
  with check (bucket_id = 'avatars');

drop policy if exists "avatars_delete_anon" on storage.objects;
create policy "avatars_delete_anon"
  on storage.objects
  for delete
  to anon
  using (bucket_id = 'avatars');

-- ============================================================
-- 使用说明：
-- 1. 在 Supabase 控制台 SQL Editor 中粘贴并执行本文件。
-- 2. Project Settings → API 复制 URL 和 anon public key。
-- 3. 填入 index.html 顶部的 CONFIG 对象。
-- 4. 部署到任意静态站点（Vercel / Netlify / GitHub Pages），
--    必须使用 HTTPS，否则浏览器拒绝提供定位。
-- ============================================================