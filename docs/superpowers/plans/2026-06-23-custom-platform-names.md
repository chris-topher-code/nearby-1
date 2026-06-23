# 自定义平台名 + 同平台重复添加 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户能为每个平台改名（如"微信"→"Instagram"），并能重复添加同一平台；改后的名称云端同步，所有人可见。纯文字，1–20 字符。

**Architecture:** 在 `profiles` 表新增 `platform_labels` JSONB 列存用户的覆盖表；编辑器每行加一个 ✏️ 按钮触发 inline 输入；渲染时优先用覆盖表，否则回退到 i18n 默认。图标保留原 SVG，不跟随改名变化。

**Tech Stack:** 单文件静态 HTML + Supabase（profiles 表） + vanilla JS + CSS

---

## 文件结构

### 修改
- `index.html` — 链接编辑器（buildLinkRow 加 ✏️ 按钮）、渲染逻辑（renderLinksContainer + profile 链接 section）、saveProfile/loadProfile/syncProfileToCloud/backfillProfileToCloud/fetchProfile、profileLinksData 流转
- `schema.sql` — profiles 表加 `platform_labels jsonb default '{}'::jsonb` 列
- `setup-guide-user.sql` — 同步更新导览账号 INSERT 字段（可选补，但加列 if not exists 已经兼容）
- `SPEC.md` — 简短说明

### 新增
- `test-platform-labels.html` — 独立测试页（不依赖主页面），加载 index.html 里的关键函数并跑用例

---

## Task 1: 数据库 schema — 加 platform_labels 列

**Files:**
- Modify: `schema.sql:99-141`（profiles 表的 create + alter 块）

- [ ] **Step 1: 添加新列的 alter table 语句**

在 `schema.sql` 中找到这段（大约第 120 行）：

```sql
alter table public.profiles
  add column if not exists avatar_url text;
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now();
```

在它**后面**追加：

```sql
-- 平台名覆盖表：用户把 "微信" 改名为 "Instagram" 等
alter table public.profiles
  add column if not exists platform_labels jsonb not null default '{}'::jsonb;
```

- [ ] **Step 2: 同步更新 CREATE TABLE 语句**

在第 99–107 行的 `create table if not exists public.profiles (...)` 中，找到 `links jsonb not null default '[]'::jsonb,` 这一行（约第 104 行），在它**后面**插入一行：

```sql
  platform_labels jsonb       not null default '{}'::jsonb,
```

最终 CREATE 部分应包含这两行：

```sql
  links           jsonb       not null default '[]'::jsonb,
  platform_labels jsonb       not null default '{}'::jsonb,
  avatar_url      text,
```

- [ ] **Step 3: 验证文件结构**

```bash
grep -n "platform_labels" "/mnt/d/SYTA Projects/618/schema.sql"
```

预期：3 处匹配（CREATE 块里 1 处 + alter 块里 1 处 if not exists + 你刚加的 1 处）。如果只看到 2 处说明 CREATE 块漏改，回看 Step 2。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add schema.sql && git commit -m "feat(db): add platform_labels column for custom platform names"
```

---

## Task 2: profile 内存模型扩展 + saveProfile/loadProfile

**Files:**
- Modify: `index.html:2297-2325`（loadProfile + saveProfile）

- [ ] **Step 1: 修改 loadProfile，返回 platformLabels**

把现有 `loadProfile` 函数（约 2297–2315 行）整体替换为：

```js
  function loadProfile() {
    try {
      const raw = localStorage.getItem(PROFILE_KEY);
      if (!raw) return null;
      const p = JSON.parse(raw);
      if (!p || typeof p.nickname !== 'string' || !p.nickname.trim()) return null;
      const links = Array.isArray(p.links)
        ? p.links
            .map(l => normalizeLink(l && l.type, l && l.url, l && l.label))
            .filter(Boolean)
        : [];
      const platformLabels = (p.platformLabels && typeof p.platformLabels === 'object')
        ? Object.fromEntries(
            Object.entries(p.platformLabels)
              .map(([k, v]) => [k, String(v || '').trim()])
              .filter(([, v]) => v && v.length <= 20)
          )
        : {};
      return {
        nickname: p.nickname.trim(),
        bio: (p.bio || '').trim(),
        links,
        tags: normalizeTags(p.tags),
        platformLabels,
      };
    } catch { return null; }
  }
```

- [ ] **Step 2: 修改 saveProfile，写入 platformLabels**

把现有 `saveProfile` 函数（约 2316–2325 行）整体替换为：

```js
  function saveProfile(p) {
    localStorage.setItem(PROFILE_KEY, JSON.stringify({
      nickname: p.nickname,
      bio: p.bio || '',
      links: p.links || [],
      tags: normalizeTags(p.tags),
      platformLabels: p.platformLabels || {},
      avatar_url: p.avatar_url || null,
      updatedAt: Date.now(),
    }));
  }
```

- [ ] **Step 3: 验证修改**

```bash
grep -n "platformLabels" "/mnt/d/SYTA Projects/618/index.html" | head -20
```

预期：至少出现 `loadProfile`、`saveProfile` 内各一次。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(profile): persist platformLabels in local profile model"
```

---

## Task 3: 新增 platformLabel() helper

**Files:**
- Modify: `index.html:2149-2152`（紧跟在 `linkTypeInfo` 之后）

- [ ] **Step 1: 添加 helper 函数**

找到这段（约 2149 行）：

```js
  function linkTypeInfo(key) {
    const info = LINK_TYPES[key] || LINK_TYPES.other;
    return { label: t(info.labelKey), placeholder: t(info.placeholderKey) };
  }
```

在它**后面**插入：

```js
  // 解析某 type 的显示名：用户的 platformLabels 覆盖 > i18n 默认
  function platformLabel(type, customLabels) {
    const labels = customLabels || (profile && profile.platformLabels) || {};
    const custom = labels[type];
    if (custom && String(custom).trim()) return String(custom).trim();
    return linkTypeInfo(type).label;
  }
```

- [ ] **Step 2: 验证**

```bash
grep -n "function platformLabel" "/mnt/d/SYTA Projects/618/index.html"
```

预期：1 行匹配。

- [ ] **Step 3: 提交**

```bash
cd "/mnt/d/SETA Projects/618" && git add index.html && git commit -m "feat(profile): add platformLabel helper for override resolution"
```

> ⚠️ 上面的 `cd` 路径写错了，正确是 `SYTA`，下面继续用对的。

修改后重做：

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(profile): add platformLabel helper for override resolution"
```

---

## Task 4: 编辑器 — buildLinkRow 加 ✏️ 改名按钮 + inline 输入

**Files:**
- Modify: `index.html:2594-2652`（`buildLinkRow` 函数）

- [ ] **Step 1: 在 buildLinkRow 末尾、return row 之前加 ✏️ 按钮逻辑**

找到 `buildLinkRow` 函数（约 2594 行开始）。函数最后是：

```js
    row.appendChild(sel);
    row.appendChild(labelInput);
    row.appendChild(input);
    row.appendChild(del);
    return row;
  }
```

把它替换为：

```js
    // ✏️ 改名按钮：把当前 type 的显示名改成用户输入的纯文字
    const renameBtn = document.createElement('button');
    renameBtn.type = 'button';
    renameBtn.className = 'rename';
    renameBtn.setAttribute('aria-label', t('link.rename'));
    renameBtn.title = t('link.rename');
    renameBtn.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/></svg>';

    // 改名用的 inline 输入框（默认隐藏）
    const renameInput = document.createElement('input');
    renameInput.type = 'text';
    renameInput.className = 'rename-input';
    renameInput.maxLength = 20;
    renameInput.placeholder = t('link.renamePh');
    renameInput.style.display = 'none';

    // 点击 ✏️：切换显示输入框 + 预填当前自定义名（或 i18n 默认）
    renameBtn.addEventListener('click', () => {
      const current = (profile && profile.platformLabels && profile.platformLabels[sel.value])
        || linkTypeInfo(sel.value).label;
      renameInput.value = current;
      renameInput.style.display = '';
      renameInput.focus();
      renameInput.select();
    });

    const commitRename = () => {
      const v = (renameInput.value || '').trim();
      if (!v) {
        // 空字符串视为取消，保留原值
        renameInput.style.display = 'none';
        return;
      }
      if (v.length > 20) {
        showToast(t('link.renameTooLong'));
        return;
      }
      if (!profile) {
        showToast(t('link.renameNoProfile'));
        renameInput.style.display = 'none';
        return;
      }
      if (!profile.platformLabels) profile.platformLabels = {};
      profile.platformLabels[sel.value] = v;
      renameInput.style.display = 'none';
    };

    renameInput.addEventListener('blur', commitRename);
    renameInput.addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); renameInput.blur(); }
      else if (e.key === 'Escape') { renameInput.value = ''; renameInput.style.display = 'none'; }
    });

    row.appendChild(sel);
    row.appendChild(renameBtn);
    row.appendChild(renameInput);
    row.appendChild(labelInput);
    row.appendChild(input);
    row.appendChild(del);
    return row;
  }
```

- [ ] **Step 2: 验证函数能加载**

```bash
node -e "
const fs = require('fs');
const html = fs.readFileSync('/mnt/d/SYTA Projects/618/index.html', 'utf8');
const m = html.match(/function buildLinkRow[\s\S]+?\n  \}\n/);
if (!m) { console.error('NOT FOUND'); process.exit(1); }
if (!m[0].includes('renameBtn')) { console.error('renameBtn not added'); process.exit(1); }
console.log('OK');
"
```

预期：`OK`

- [ ] **Step 3: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(editor): add per-row rename button for platform labels"
```

---

## Task 5: CSS — ✏️ 按钮 + rename input 样式

**Files:**
- Modify: `index.html:807-823`（link-row 相关 CSS 块）

- [ ] **Step 1: 找到 link-row CSS 块**

读 index.html 第 807–823 行左右，应是这段：

```css
    .link-row .del:hover { color: var(--err); border-color: var(--err); }
    .link-row .del svg { width: 14px; height: 14px; }

    @media (max-width: 480px) {
      .link-row { flex-wrap: wrap; }
      .link-row input.url-input { flex: 1 1 100%; }
      .link-row input.label-input { flex: 1 1 auto; max-width: none; }
      .link-row .del { margin-left: auto; }
    }
```

- [ ] **Step 2: 在 `.link-row .del svg` 之后、`@media` 之前插入新样式**

```css
    .link-row .rename {
      display: inline-flex; align-items: center; justify-content: center;
      width: 28px; height: 28px; border: 1px solid var(--border);
      background: var(--surface-2); color: var(--text-dim);
      border-radius: 8px; cursor: pointer; padding: 0;
      flex: 0 0 auto;
    }
    .link-row .rename:hover { color: var(--accent, #00e5ff); border-color: var(--accent, #00e5ff); }
    .link-row .rename svg { width: 13px; height: 13px; }
    .link-row input.rename-input {
      flex: 0 0 120px; max-width: 140px;
      padding: 6px 8px; font-size: 12px;
    }
```

- [ ] **Step 3: 验证**

```bash
grep -n "\.link-row \.rename" "/mnt/d/SYTA Projects/618/index.html"
```

预期：3+ 行匹配（`.rename {`、`.rename:hover {`、`.rename svg {`、input.rename-input）。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(css): style for rename button and inline rename input"
```

---

## Task 6: i18n — 新增改名相关文案

**Files:**
- Modify: `index.html:1722-1723`（zh 块）、`1893-1894`（en 块）

- [ ] **Step 1: 在 zh 块添加键**

找到 `'link.del': '删除此链接',`（约 1723 行），在它**前面**插入：

```js
      'link.rename': '改平台名',
      'link.renamePh': '新名字（1-20 字）',
      'link.renameTooLong': '名字最多 20 个字符',
      'link.renameNoProfile': '请先完成新手引导',
```

- [ ] **Step 2: 在 en 块添加键**

找到 `'link.del': 'Remove link',`（约 1894 行），在它**前面**插入：

```js
      'link.rename': 'Rename platform',
      'link.renamePh': 'New name (1-20 chars)',
      'link.renameTooLong': 'Name must be 20 chars or less',
      'link.renameNoProfile': 'Please complete onboarding first',
```

- [ ] **Step 3: 验证**

```bash
grep -n "link.rename" "/mnt/d/SYTA Projects/618/index.html"
```

预期：4 处匹配（zh 的 4 键 + en 的 4 键 + 至少 1 处使用 = buildLinkRow 里的 `t('link.rename')`）。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(i18n): add rename-related strings in zh and en"
```

---

## Task 7: 渲染 — chip 用 platformLabel()

**Files:**
- Modify: `index.html:3432-3482`（`renderLinksContainer` 函数）

- [ ] **Step 1: 替换 info.label 为 platformLabel 调用**

找到 `renderLinksContainer` 函数（约 3433 行）。在它的 forEach 回调里（约 3437 行）：

```js
    links.forEach(l => {
      if (!l || !l.url) return;
      const t = l.type || 'website';
      const info = LINK_TYPES[t] || LINK_TYPES.other;
      const chip = document.createElement('a');
      chip.className = 'chip ' + t;
      // 内联 SVG icon
      const iconWrap = document.createElement('span');
      iconWrap.style.cssText = 'display:inline-flex;align-items:center;';
      iconWrap.innerHTML = linkIcon(t);
      const label = document.createElement('span');
      label.className = 'chip-text';
      if (t === 'wechat') {
        label.textContent = `${t('link.wechat')}: ${l.url}`;
      } else if (t === 'other' && l.label) {
        // "其他"链接：显示用户自定义的名称 + 主机名
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${l.label} · ${host}`;
        } catch {
          label.textContent = l.label;
        }
      } else {
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${info.label} · ${host}`;
        } catch {
          label.textContent = info.label;
        }
      }
```

把 `info.label` 的两处都改成 `platformLabel(t, p && p.platformLabels)`，并把 forEach 的回调签名从 `l =>` 改为 `(l, _i, arr)` 然后拿到所属 profile。这个函数当前签名没有 profile 参数——需要从函数参数加一个：

把整个 `renderLinksContainer(linksArr)` 函数签名改为 `renderLinksContainer(linksArr, profileForLabels)`：

```js
  // 把一行 row.links 渲染成 chip 数组
  // profileForLabels 可选：传入时用其 platformLabels 覆盖默认名
  function renderLinksContainer(linksArr, profileForLabels) {
    const wrap = document.createElement('div');
    wrap.className = 'links';
    if (!Array.isArray(linksArr) || !linksArr.length) return wrap;
    links.forEach(l => {
      if (!l || !l.url) return;
      const t = l.type || 'website';
      const resolvedLabel = platformLabel(t, profileForLabels && profileForLabels.platformLabels);
      const chip = document.createElement('a');
      chip.className = 'chip ' + t;
      const iconWrap = document.createElement('span');
      iconWrap.style.cssText = 'display:inline-flex;align-items:center;';
      iconWrap.innerHTML = linkIcon(t);
      const label = document.createElement('span');
      label.className = 'chip-text';
      if (t === 'wechat') {
        label.textContent = `${resolvedLabel}: ${l.url}`;
      } else if (t === 'other' && l.label) {
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${l.label} · ${host}`;
        } catch {
          label.textContent = l.label;
        }
      } else {
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${resolvedLabel} · ${host}`;
        } catch {
          label.textContent = resolvedLabel;
        }
      }
      chip.appendChild(iconWrap);
      chip.appendChild(label);
      chip.href = (t === 'wechat') ? '#' : l.url;
      chip.target = '_blank';
      chip.rel = 'noopener noreferrer';
      if (t === 'wechat') {
        chip.addEventListener('click', e => {
          e.preventDefault();
          try { navigator.clipboard.writeText(l.url); } catch {}
          showToast(t('debug.copiedSid') + '：' + l.url);
        });
      }
      wrap.appendChild(chip);
    });
    return wrap;
  }
```

> ⚠️ 函数里把外层 `t` 变量名（`t('link.wechat')`）遮蔽了，所以旧的 `t` 函数调用要保留为 `t('link.wechat')` 等的别名。**保留**：`showToast(t('debug.copiedSid') + '：' + l.url);` 这一行中 `t` 指的是翻译函数。我们改用 `tKey` 作 forEach 内 type 变量避免冲突。重写时把内层 `const t = l.type || 'website';` 改成 `const tKey = l.type || 'website';`，下面所有用 `t` 改 `tKey`，翻译函数 `t(...)` 不动。**最终正确版：**

```js
  // 把一行 row.links 渲染成 chip 数组
  // profileForLabels 可选：传入时用其 platformLabels 覆盖默认名
  function renderLinksContainer(linksArr, profileForLabels) {
    const wrap = document.createElement('div');
    wrap.className = 'links';
    if (!Array.isArray(linksArr) || !linksArr.length) return wrap;
    linksArr.forEach(l => {
      if (!l || !l.url) return;
      const tKey = l.type || 'website';
      const resolvedLabel = platformLabel(tKey, profileForLabels && profileForLabels.platformLabels);
      const chip = document.createElement('a');
      chip.className = 'chip ' + tKey;
      const iconWrap = document.createElement('span');
      iconWrap.style.cssText = 'display:inline-flex;align-items:center;';
      iconWrap.innerHTML = linkIcon(tKey);
      const label = document.createElement('span');
      label.className = 'chip-text';
      if (tKey === 'wechat') {
        label.textContent = `${resolvedLabel}: ${l.url}`;
      } else if (tKey === 'other' && l.label) {
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${l.label} · ${host}`;
        } catch {
          label.textContent = l.label;
        }
      } else {
        try {
          const host = new URL(l.url).hostname.replace(/^www\./, '');
          label.textContent = `${resolvedLabel} · ${host}`;
        } catch {
          label.textContent = resolvedLabel;
        }
      }
      chip.appendChild(iconWrap);
      chip.appendChild(label);
      chip.href = (tKey === 'wechat') ? '#' : l.url;
      chip.target = '_blank';
      chip.rel = 'noopener noreferrer';
      if (tKey === 'wechat') {
        chip.addEventListener('click', e => {
          e.preventDefault();
          try { navigator.clipboard.writeText(l.url); } catch {}
          showToast(t('debug.copiedSid') + '：' + l.url);
        });
      }
      wrap.appendChild(chip);
    });
    return wrap;
  }
```

- [ ] **Step 2: 找到 renderLinksContainer 的所有调用点，确保传 profile**

```bash
grep -n "renderLinksContainer(" "/mnt/d/SYTA Projects/618/index.html"
```

预期：3+ 个调用点。把每个调用点第二个参数加上 `p`（当前 row 的 profile 对象）。具体位置需要逐个看，但典型的形式是 `rowEl.appendChild(renderLinksContainer(row.links));` → 改为 `rowEl.appendChild(renderLinksContainer(row.links, row));`（其中 `row` 是有 `.platformLabels` 的对象）。

调用点上下文一般有 `row` 变量名（来自外层 `.forEach(row => ...)`）。在每个调用点把第二个参数 `row` 加上。

- [ ] **Step 3: 验证**

```bash
grep -n "renderLinksContainer(" "/mnt/d/SYTA Projects/618/index.html"
```

预期：每个调用现在都是 `renderLinksContainer(X, Y)` 形式。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(render): use platformLabel override when rendering link chips"
```

---

## Task 8: 渲染 — 个人主页弹层链接区用 platformLabel()

**Files:**
- Modify: `index.html:3287-3315`（profile 链接 section 的 forEach）

- [ ] **Step 1: 修改 label 解析**

在 profile 链接 section（约 3287 行）：

```js
        links.forEach(l => {
          const info = LINK_TYPES[l.type] || LINK_TYPES.other;
          const a = document.createElement('a');
          a.className = 'profile-link';
          a.href = (l.type === 'wechat') ? '#' : l.url;
          a.target = '_blank';
          a.rel = 'noopener noreferrer';
          a.innerHTML = linkIcon(l.type || 'other');
          const label = document.createElement('span');
          label.textContent = (l.label && String(l.label).trim()) ? l.label : info.label;
          a.appendChild(label);
```

把这段替换为：

```js
        links.forEach(l => {
          const resolvedLabel = platformLabel(l.type || 'other', p && p.platformLabels);
          const a = document.createElement('a');
          a.className = 'profile-link';
          a.href = (l.type === 'wechat') ? '#' : l.url;
          a.target = '_blank';
          a.rel = 'noopener noreferrer';
          a.innerHTML = linkIcon(l.type || 'other');
          const label = document.createElement('span');
          // "其他" 类型的 l.label 仍优先（每条独立的名称）
          if (l.type === 'other' && l.label && String(l.label).trim()) {
            label.textContent = l.label;
          } else {
            label.textContent = resolvedLabel;
          }
          a.appendChild(label);
```

注意：`p` 是外层函数的 profile 参数（约 3270 行附近的 `const p = ...`），需确认 `p.platformLabels` 存在。如果 p 没有 `platformLabels` 字段（旧 profile），`platformLabel` 会回退到 i18n 默认，行为正确。

- [ ] **Step 2: 验证**

```bash
grep -n "resolvedLabel" "/mnt/d/SYTA Projects/618/index.html"
```

预期：至少 2 处（renderLinksContainer + profile 弹层）。

- [ ] **Step 3: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(profile-modal): render links with custom platform labels"
```

---

## Task 9: 云端同步 — syncProfileToCloud / backfillProfileToCloud / fetchProfile

**Files:**
- Modify: `index.html:3046-3089`

- [ ] **Step 1: syncProfileToCloud 加 platform_labels 字段**

找到 `syncProfileToCloud`（约 3046 行），把 row 对象改为：

```js
    const row = {
      session_id: SESSION_ID,
      nickname:   profile.nickname,
      bio:        profile.bio || null,
      tags:       Array.isArray(profile.tags) ? profile.tags : [],
      links:      Array.isArray(profile.links) ? profile.links : [],
      platform_labels: profile.platformLabels || {},
      avatar_url: profile.avatar_url || null,
      updated_at: new Date().toISOString(),
    };
```

- [ ] **Step 2: backfillProfileToCloud 加 platform_labels 字段**

找到 `backfillProfileToCloud`（约 3063 行），把 row 对象改为：

```js
    const row = {
      session_id: p.session_id,
      nickname:   p.nickname || t('common.anonymous'),
      bio:        p.bio || null,
      tags:       Array.isArray(p.tags) ? p.tags : [],
      links:      Array.isArray(p.links) ? p.links : [],
      platform_labels: (p.platformLabels && typeof p.platformLabels === 'object') ? p.platformLabels : {},
      avatar_url: p.avatar_url || null,
      updated_at: new Date().toISOString(),
    };
```

- [ ] **Step 3: fetchProfile 选择 platform_labels**

找到 `fetchProfile`（约 3081 行）：

```js
  async function fetchProfile(sessionId) {
    const { data, error } = await sb
      .from('profiles')
      .select('session_id, nickname, bio, tags, links, avatar_url, updated_at')
      .eq('session_id', sessionId)
      .maybeSingle();
    if (error) { console.warn('fetchProfile', error); return null; }
    return data;
  }
```

改为：

```js
  async function fetchProfile(sessionId) {
    const { data, error } = await sb
      .from('profiles')
      .select('session_id, nickname, bio, tags, links, platform_labels, avatar_url, updated_at')
      .eq('session_id', sessionId)
      .maybeSingle();
    if (error) { console.warn('fetchProfile', error); return null; }
    // 兼容老数据：snake_case → camelCase
    if (data && data.platform_labels && !data.platformLabels) {
      data.platformLabels = data.platform_labels;
    }
    return data;
  }
```

- [ ] **Step 4: 验证**

```bash
grep -n "platform_labels" "/mnt/d/SYTA Projects/618/index.html"
```

预期：至少 3 处匹配（syncProfileToCloud、backfillProfileToCloud、fetchProfile）。

- [ ] **Step 5: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(sync): include platform_labels in cloud round-trip"
```

---

## Task 10: 让 onboarding 提交时也保存 platformLabels（默认空对象）

**Files:**
- Modify: `index.html:2891`（`commitOnboard` 内 profile 构造）

- [ ] **Step 1: 在 onboarding 提交时初始化 platformLabels**

找到 `commitOnboard`（约 2885 行）里的：

```js
    profile = { nickname: nick, bio, links, tags, avatar_url: null };
```

改为：

```js
    profile = { nickname: nick, bio, links, tags, avatar_url: null, platformLabels: {} };
```

- [ ] **Step 2: 在 settings 保存时保留 platformLabels**

找到 `saveSettings`（约 2932 行）里的 profile 构造（约 2943 行）：

```js
    profile = {
      nickname: nick,
      bio,
      links: finalLinks,
      tags: finalTags,
      avatar_url: profile ? profile.avatar_url : null,
    };
```

改为：

```js
    profile = {
      nickname: nick,
      bio,
      links: finalLinks,
      tags: finalTags,
      avatar_url: profile ? profile.avatar_url : null,
      platformLabels: profile && profile.platformLabels ? profile.platformLabels : {},
    };
```

- [ ] **Step 3: 验证**

```bash
grep -n "platformLabels:" "/mnt/d/SYTA Projects/618/index.html"
```

预期：至少 2 处匹配。

- [ ] **Step 4: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add index.html && git commit -m "feat(profile): initialize platformLabels on onboard/settings save"
```

---

## Task 11: 独立测试页 — 验证 platformLabel 解析

**Files:**
- Create: `test-platform-labels.html`

- [ ] **Step 1: 创建测试页**

在 `/mnt/d/SYTA Projects/618/test-platform-labels.html` 写入：

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<title>platformLabel 单元测试</title>
<style>
  body { font-family: system-ui, sans-serif; padding: 20px; }
  pre  { background: #f4f4f4; padding: 8px; border-radius: 6px; }
  .ok  { color: #0a0; }
  .fail{ color: #c00; }
</style>
</head>
<body>
<h1>platformLabel 解析测试</h1>
<div id="out"></div>

<!-- 直接复制 index.html 里的纯函数（不依赖 DOM / supabase） -->
<script>
  // 与 index.html 保持同步
  const LINK_TYPES = {
    wechat:  { labelKey: 'wechat'  },
    xhs:     { labelKey: 'xhs'     },
    douyin:  { labelKey: 'douyin'  },
    website: { labelKey: 'website' },
    other:   { labelKey: 'other'   },
  };
  function linkTypeInfo(key) {
    return { label: '默认_' + (key || 'other') };
  }
  function platformLabel(type, customLabels) {
    const labels = customLabels || {};
    const custom = labels[type];
    if (custom && String(custom).trim()) return String(custom).trim();
    return linkTypeInfo(type).label;
  }

  const out = document.getElementById('out');
  const cases = [
    ['默认 wechat',         platformLabel('wechat'),                              '默认_wechat'],
    ['默认 other',          platformLabel('other'),                               '默认_other'],
    ['改 wechat',           platformLabel('wechat', { wechat: 'Instagram' }),     'Instagram'],
    ['改 xhs',              platformLabel('xhs',    { xhs: 'RED' }),              'RED'],
    ['改但空白',            platformLabel('wechat', { wechat: '   ' }),           '默认_wechat'],
    ['不存在的 type',       platformLabel('unknown', { wechat: 'X' }),            '默认_unknown'],
    ['多余键不影响',        platformLabel('xhs',    { xhs: 'A', qq: 'B' }),       'A'],
  ];

  let pass = 0, fail = 0;
  cases.forEach(([name, got, want]) => {
    const ok = got === want;
    if (ok) pass++; else fail++;
    const p = document.createElement('p');
    p.className = ok ? 'ok' : 'fail';
    p.textContent = (ok ? '✓ ' : '✗ ') + name + '  →  ' + JSON.stringify(got) + (ok ? '' : '   (want ' + JSON.stringify(want) + ')');
    out.appendChild(p);
  });
  const summary = document.createElement('p');
  summary.innerHTML = `<b>${pass}/${pass+fail} passed</b>`;
  out.appendChild(summary);
</script>
</body>
</html>
```

- [ ] **Step 2: 打开并确认（手动）**

```bash
ls -la "/mnt/d/SYTA Projects/618/test-platform-labels.html"
```

预期：文件存在。然后用浏览器打开 `file:///mnt/d/SYTA Projects/618/test-platform-labels.html`，应看到 `7/7 passed` 字样，全绿。

- [ ] **Step 3: 提交**

```bash
cd "/mnt/d/SYTA Projects/618" && git add test-platform-labels.html && git commit -m "test: standalone page for platformLabel resolver"
```

---

## Task 12: 端到端手工验收 + 修复

**Files:**
- Modify: 任何遗留小问题

- [ ] **Step 1: 浏览器打开 index.html**

用本地静态服务器启动：

```bash
cd "/mnt/d/SYTA Projects/618" && python3 -m http.server 8765
```

打开 `http://localhost:8765/index.html`。

- [ ] **Step 2: 验收 — 改名**

1. 完成新手引导（或在设置里）
2. 在联系方式区域加一行"微信"
3. 点 ✏️ → 输入 "Instagram" → 失焦
4. 期望：✓ toast 提示"已保存"（实现里没加 toast，跳过；如未提示也正常）—— 关闭设置再打开，select 仍显示"微信"（这是预期：select 显示原始 type 名；改名只影响渲染）
5. 提交后看 list 渲染，chip 文字应是 "Instagram: xxx"

- [ ] **Step 3: 验收 — 重复添加**

1. 点"添加一个链接"两次
2. type 都选 wechat
3. 保存
4. 期望：list 里出现 2 个微信 chip（都带 "Instagram:" 自定义名），都点击可复制

- [ ] **Step 4: 验收 — 云端同步**

1. 在另一个浏览器（隐身模式）打开同一页面
2. 找一个由 user A 发的留言 → 点 A 头像打开个人主页
3. 期望：A 改名的 chip 显示 A 的自定义名（不是默认"微信"）

- [ ] **Step 5: 修复并提交**

如发现 bug 就地修复并 commit。

```bash
cd "/mnt/d/SYTA Projects/618" && git status
```

无意外应是干净状态。

---

## Self-Review 检查

**1. Spec 覆盖：**
- ✅ 5 个预设平台都能改名 → Task 4, 6
- ✅ 改名 1–20 字符纯文字 → Task 4（maxLength + 校验 + i18n 键）
- ✅ 同平台可重复添加 → 无 UI 限制（已存在）+ Task 10 不阻止
- ✅ 平台名同步到云端 → Task 1, 9
- ✅ 保留原 SVG 图标 → Task 7, 8（仍按 type 走 linkIcon）
- ✅ 加载他人 profile 用他人 platformLabels → Task 9（fetchProfile 返回 platform_labels → profile modal 渲染）

**2. 占位符扫描：** 全部步骤含具体文件路径 + 具体代码，无 TBD/TODO。

**3. 类型一致性：**
- `profile.platformLabels`（camelCase）— 在 saveProfile、loadProfile、syncProfileToCloud、backfillProfileToCloud、fetchProfile、saveSettings、commitOnboard 中一致使用
- 数据库列名 `platform_labels`（snake_case）— sync/select/backfill 一致；fetchProfile 加了 snake→camel 转换
- helper `platformLabel(type, customLabels)` — Task 3 定义、Task 7/8 使用
- i18n 键 `link.rename*` — Task 6 定义、Task 4 使用

**4. 变量名冲突：** Task 7 把内层 `t` 改名为 `tKey` 避免遮蔽外层 `t` 翻译函数。

Plan 已就绪。
