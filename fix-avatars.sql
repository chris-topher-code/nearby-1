-- ============================================================
-- 头像功能修复脚本 v2（暴力清理所有 avatars policies）
-- 在 Supabase SQL Editor 里跑这个
-- ============================================================

-- 1. 确保 avatars 桶存在 + 公开
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

-- 2. 暴力 drop 所有可能的 avatars policies
drop policy if exists "avatars_select_public"   on storage.objects;
drop policy if exists "avatars_insert_anon"     on storage.objects;
drop policy if exists "avatars_update_anon"     on storage.objects;
drop policy if exists "avatars_delete_anon"     on storage.objects;

drop policy if exists "avatars_read_public"     on storage.objects;
drop policy if exists "avatars_write_anon"      on storage.objects;
drop policy if exists "avatars_read_anon"       on storage.objects;

-- 3. 重建 policies（用统一名字 + 简化的权限）
-- 公开读（公开桶必须）
create policy "avatars_select_public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'avatars');

-- anon INSERT
create policy "avatars_insert_anon"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'avatars');

-- anon UPDATE
create policy "avatars_update_anon"
  on storage.objects
  for update
  to anon
  using (bucket_id = 'avatars')
  with check (bucket_id = 'avatars');

-- anon DELETE
create policy "avatars_delete_anon"
  on storage.objects
  for delete
  to anon
  using (bucket_id = 'avatars');

-- 4. 验证：所有 policies（应该正好 4 个，名字都是 avatars_*_anon/public）
select policyname, roles, cmd
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like 'avatars%'
order by policyname;

-- 5. 验证 RLS 状态
select relname, relrowsecurity
from pg_class
where relname = 'objects' and relnamespace = 'storage'::regnamespace;