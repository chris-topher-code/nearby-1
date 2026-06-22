# 近场偶遇留言板 — 部署指南

> 一个纯前端的"5 分钟时空胶囊"：附近 100 米 / 5 分钟内陌生人留下的匿名心声。

## 文件清单

- `index.html` — 单文件前端应用（包含样式、逻辑、HTML）
- `schema.sql` — Supabase 数据库建表脚本
- `SPEC.md` — 设计说明（功能、数据结构、UI 决策）
- `README.md` — 本文件，部署步骤

## 完整步骤（约 10 分钟）

### 第 1 步：新建 Supabase 项目

1. 打开 https://supabase.com → 登录
2. **New Project**：
   - Name：`encounter-board`（或自取）
   - Database Password：选个**新的强密码并记下**（项目建好后不会再显示完整密码）
   - Region：选离你最近的（如 Singapore / Tokyo）
3. 等 1-2 分钟初始化

### 第 2 步：建表 + 开启权限

1. 新项目仪表盘 → 左侧 **SQL Editor** → **New query**
2. 粘贴 `schema.sql` 全部内容
3. 点 **Run**
4. 验证：左侧 **Table Editor** → 应看到 `nearby_encounters` 表，含 `id / content / latitude / longitude / session_id / nickname / bio / links / tags / created_at` 10 列

### 第 3 步：复制 API 凭证

1. 左侧 ⚙️ **Project Settings** → **API**
2. 复制：
   - **Project URL**（如 `https://abcdefgh.supabase.co`）
   - **anon public** key（一长串以 `eyJ` 开头）
3. ⚠️ **不要复制** `service_role` key，那个不能放前端

### 第 4 步：填凭证进 `index.html`

打开 `index.html`，找到第 1012-1013 行：

```js
const CONFIG = {
  SUPABASE_URL:      'https://YOUR-PROJECT.supabase.co',   // ← 换成步骤 3 的 URL
  SUPABASE_ANON_KEY: 'YOUR-ANON-KEY',                      // ← 换成步骤 3 的 anon key
  ...
};
```

保存文件。

### 第 5 步：部署到 HTTPS（必须 HTTPS，定位 API 不支持 HTTP）

**最快：Netlify Drop（30 秒，无需注册）**

1. 打开 https://app.netlify.com/drop
2. 把整个 `618` 文件夹（包含 `index.html` / `schema.sql` / `SPEC.md` / `README.md`）拖进浏览器
3. 等 10-30 秒，给一个网址如 `https://random-name-123.netlify.app`
4. 用这个网址在电脑 + 手机访问

### 第 6 步：端到端测试

#### 6.1 桌面浏览器访问部署网址
- 应看到 onboarding 弹层（昵称 + bio + 标签 + 联系方式）
- 填昵称 + 至少 1 个标签 → 点【开始】
- 应看到顶部状态栏变绿色 ✓"定位成功"
- 写一条带标签 + 链接的留言 → 点发射 → 应看到 ✅ 已发送

#### 6.2 调试面板验证数据真的写入了
- **长按齿轮按钮 1 秒** → 调试面板弹出
- 看：
  - **Supabase**：`abcdefgh.supabase.co`（你填的那个）
  - **定位状态**：`ok`
  - **当前坐标**：有数字
  - **Profile**：你的昵称 + 标签数 + 链接数
  - **最近一次拉取**：显示时间 + 条数
- 如果有**红色错误框**，把内容发我看

#### 6.3 模拟另一个用户
- 用浏览器**隐身窗口**（Ctrl+Shift+N）打开同一网址
- 完成 onboarding，用不同的昵称
- 发一条留言
- 回到原窗口 → 应能看到这条新留言（**前提**：两边都"在同一地点"，即 100m 内）
- 调试面板有 4 个模拟位置按钮（北京/上海/东京/真实定位），可用于桌面对桌面测试

#### 6.4 手机测试
- 用手机浏览器访问同一网址
- 允许定位权限
- 完成 onboarding
- 应能看到桌面发的留言（如果距离 < 100m 且 < 5 min）

## 常见问题

### Q：填完 URL 和 key 后还是 `ERR_NAME_NOT_RESOLVED`
**A**：浏览器缓存。**硬刷新**：Ctrl+Shift+R（Mac: Cmd+Shift+R）。

### Q：Netlify 部署后访问是空白页
**A**：打开浏览器 Console（F12）看报错。最常见：
- `net::ERR_NAME_NOT_RESOLVED` → URL 没填对
- `Invalid API key` → anon key 没填对或填成了 service_role

### Q：写入失败 `column "links" of relation "nearby_encounters" does not exist`
**A**：表是旧的，没有 links 列。SQL Editor 跑：
```sql
alter table public.nearby_encounters add column if not exists links jsonb not null default '[]'::jsonb;
alter table public.nearby_encounters add column if not exists tags text[] not null default '{}'::text[];
```

### Q：写入失败 `new row violates row-level security policy`
**A**：RLS 策略没生效。重跑 `schema.sql` 第 4-5 段（启用 RLS + 创建策略）。

### Q：手机看不到桌面发的留言
1. 调试面板看错误
2. 桌面隐身窗口模拟另一个用户，看看能不能互相看到（排除"没真实人在旁边"的情况）
3. 缩短测试间隔：发完消息等 15 秒内看（轮询周期 15s）

### Q：链接标签 chips 不显示
**A**：可能浏览器加载了旧版 `index.html`。硬刷新。删除 Netlify 旧部署重新拖一次。

## 调试面板速查

**打开方式**：
- 桌面：**长按齿轮按钮 1 秒**
- 移动：**连点齿轮 5 次**（1.5 秒内）

**功能**：
- 看会话 ID / Supabase / 定位状态 / 坐标 / Profile
- 模拟位置（北京 / 上海 / 东京 / 真实）
- 禁用自我隔离（看自己留言，方便调试）
- 手动刷新 / 复制 SID / 清空 localStorage

## 安全提示

- 只放 **anon public** key 进 `index.html`，**绝不放 service_role**
- Supabase 免费层：500 MB 数据库 / 2 GB 带宽 / 50,000 月活 — 个人玩绰绰有余
- 用户留言是公开的（任何人都能拉到 5min/100m 内的），所以别写敏感信息

## 需要再改功能？

`SPEC.md` 里有完整设计说明，`index.html` 关键位置有中文注释。改完直接重新拖到 Netlify 即可（覆盖原部署）。