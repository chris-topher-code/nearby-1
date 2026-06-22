-- ============================================================
-- 导览账号 universal —— 修复 profiles 表 + 插入导览账号
-- 一次性脚本，在 Supabase SQL Editor 跑一次
-- ============================================================

-- 步骤 1：先确保 profiles.session_id 有 PRIMARY KEY 约束
-- （原 schema.sql 的 do $$ 块在重复行存在时会失败）
do $$
declare
  has_pk boolean;
  has_dup boolean;
  dropped_constraint text;
begin
  -- 检查是否已经有主键
  select exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and contype = 'p'
  ) into has_pk;

  if not has_pk then
    -- 删除 profiles 里所有重复的 session_id（保留 updated_at 最新的一条）
    delete from public.profiles a
    using public.profiles b
    where a.session_id = b.session_id
      and a.updated_at < b.updated_at;

    -- 删除可能存在的其他唯一约束
    execute (
      select 'alter table public.profiles drop constraint ' || quote_ident(c.conname)
      from pg_constraint c
      where c.conrelid = 'public.profiles'::regclass
        and c.contype in ('u', 'p')
      limit 1
    );

    -- 加主键
    alter table public.profiles add primary key (session_id);
  end if;
end$$;

-- 步骤 2：插入 / 更新导览账号 universal
insert into public.profiles (
  session_id,
  nickname,
  bio,
  tags,
  links,
  avatar_url,
  updated_at
) values (
  '__universal_guide__',
  'universal',
  '我是这片星空的指路人 ✨ 首次来这里？点击我看看个人主页长什么样。',
  array['导览', '示例', '指路人'],
  '[
    {"type": "website", "url": "https://github.com/", "label": "了解更多"},
    {"type": "xhs", "url": "https://www.xiaohongshu.com/", "label": "小红书"}
  ]'::jsonb,
  null,
  now()
)
on conflict (session_id) do update set
  nickname   = excluded.nickname,
  bio        = excluded.bio,
  tags       = excluded.tags,
  links      = excluded.links,
  avatar_url = excluded.avatar_url,
  updated_at = now();

-- 验证
select session_id, nickname, bio, tags, links
from public.profiles
where session_id = '__universal_guide__';