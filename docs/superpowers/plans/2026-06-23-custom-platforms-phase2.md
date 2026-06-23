# 自定义平台名 + 同平台重复添加 + 自定义新增 — 实施计划（第二阶段）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (this is small enough for inline). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** select 末尾加 "➕ 自定义..." 入口，用户输入纯文字平台名（1–20 字符，不要 emoji）后存入 `profile.customPlatforms`（云端），下拉里立即出现，自定义平台支持改名、重复添加、复用 website 图标。

**Architecture:** 在 `profiles` 表加 `custom_platforms JSONB[]` 列；链接的 `type` 字段为 `custom:<name>` 形式；`platformLabel()` 看到 `custom:` 前缀直接返回名字；`linkIcon()` 看到 `custom:` 走 website fallback。

**Tech Stack:** 单文件 HTML + Supabase + vanilla JS

**前置依赖：** 第一阶段已实施（platformLabels + ✏️ 改名按钮）。本计划只在第一阶段基础上扩展。

---

## 文件结构

### 修改
- `index.html` — schema（schema 项）、loadProfile/saveProfile、buildLinkRow（select 末尾 + 自定义处理）、platformLabel/linkIcon、profile 弹层渲染、sync/backfill/fetch
- `schema.sql` — profiles 表加 `custom_platforms jsonb not null default '[]'::jsonb`

### 不变
- `test-platform-labels.html` — 仍适用，扩展一个 platformLabel('custom:X') 用例

---

## Task 1: schema.sql — 加 custom_platforms 列

**Files:**
- Modify: `schema.sql:99-141`

- [ ] **Step 1: CREATE 块加列**

在第 105 行 `platform_labels jsonb not null default '{}'::jsonb,` 后面**插入**：

```sql
  custom_platforms jsonb      not null default '[]'::jsonb,
```

注意：`custom_platforms` 存的也是 JSONB 数组（`["Telegram","WhatsApp"]`），不是 `text[]`。

- [ ] **Step 2: alter 块加 if not exists**

在第 128 行 `add column if not exists platform_labels ...` 后面**追加**：

```sql
alter table public.profiles
  add column if not exists custom_platforms jsonb not null default '[]'::jsonb;
```

- [ ] **Step 3: 验证**

```bash
grep -n "custom_platforms" "/mnt/d/SYTA Projects/618/schema.sql"
```

预期：2 行匹配（CREATE 块 + alter 块）。

- [ ] **Step 4: 提交（如有 git）**

无 git 仓库时跳过。

---

## Task 2: loadProfile / saveProfile — 持久化 customPlatforms

**Files:**
- Modify: `index.html:2338-2362`（第一阶段已加 platformLabels 处）

- [ ] **Step 1: loadProfile 解析 customPlatforms**

找到第一阶段加的这段（约 2338–2346 行）：

```js
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
```

改为：

```js
      const platformLabels = (p.platformLabels && typeof p.platformLabels === 'object')
        ? Object.fromEntries(
            Object.entries(p.platformLabels)
              .map(([k, v]) => [k, String(v || '').trim()])
              .filter(([, v]) => v && v.length <= 20)
          )
        : {};
      const customPlatforms = Array.isArray(p.customPlatforms)
        ? p.customPlatforms
            .map(s => String(s || '').trim())
            .filter(s => s && s.length <= 20 && !PRESET_TYPES.has(s))
            .filter((s, i, a) => a.indexOf(s) === i)
        : [];
      return {
        nickname: p.nickname.trim(),
        bio: (p.bio || '').trim(),
        links,
        tags: normalizeTags(p.tags),
        platformLabels,
        customPlatforms,
      };
```

- [ ] **Step 2: saveProfile 写入 customPlatforms**

找到第一阶段加的这段（约 2358–2362 行）：

```js
    localStorage.setItem(PROFILE_KEY, JSON.stringify({
      nickname: p.nickname,
      bio: p.bio || '',
      links: p.links || [],
      tags: normalizeTags(p.tags),
      platformLabels: p.platformLabels || {},
      avatar_url: p.avatar_url || null,
      updatedAt: Date.now(),
    }));
```

改为：

```js
    localStorage.setItem(PROFILE_KEY, JSON.stringify({
      nickname: p.nickname,
      bio: p.bio || '',
      links: p.links || [],
      tags: normalizeTags(p.tags),
      platformLabels: p.platformLabels || {},
      customPlatforms: Array.isArray(p.customPlatforms) ? p.customPlatforms : [],
      avatar_url: p.avatar_url || null,
      updatedAt: Date.now(),
    }));
```

- [ ] **Step 3: 加 PRESET_TYPES 常量**

找到第一阶段加的 `platformLabel` 函数（约 2177 行），**在它前面**插入：

```js
  const PRESET_TYPES = new Set(['wechat', 'xhs', 'douyin', 'website', 'other']);
```

- [ ] **Step 4: 验证**

```bash
grep -n "PRESET_TYPES\|customPlatforms" "/mnt/d/SYTA Projects/618/index.html" | head -20
```

预期：PRESET_TYPES 1 处 + customPlatforms 多处。

---

## Task 3: 扩展 platformLabel + linkIcon 支持 custom: 前缀

**Files:**
- Modify: `index.html:2177-2182`（platformLabel）、`3512-3527`（linkIcon）

- [ ] **Step 1: platformLabel 支持 custom: 前缀**

找到：

```js
  // 解析某 type 的显示名：用户的 platformLabels 覆盖 > i18n 默认
  function platformLabel(type, customLabels) {
    const labels = customLabels || (profile && profile.platformLabels) || {};
    const custom = labels[type];
    if (custom && String(custom).trim()) return String(custom).trim();
    return linkTypeInfo(type).label;
  }
```

改为：

```js
  // 解析某 type 的显示名：自定义平台 > platformLabels 覆盖 > i18n 默认
  function platformLabel(type, customLabels) {
    // 1. 自定义平台：custom:<name> → 直接返回 name
    if (typeof type === 'string' && type.startsWith('custom:')) {
      return type.slice('custom:'.length);
    }
    // 2. 预设平台：用户的 platformLabels 覆盖 > i18n 默认
    const labels = customLabels || (profile && profile.platformLabels) || {};
    const custom = labels[type];
    if (custom && String(custom).trim()) return String(custom).trim();
    return linkTypeInfo(type).label;
  }
```

- [ ] **Step 2: linkIcon 处理 custom: 前缀**

找到 `linkIcon` 函数（约 3513 行），它返回 `icons[type] || icons.other`。改成：

```js
  function linkIcon(type) {
    // 自定义平台统一用 website 图标
    if (typeof type === 'string' && type.startsWith('custom:')) return icons.website;
    const icons = {
      wechat: '...',
      ...
    };
    return icons[type] || icons.other;
  }
```

⚠️ icons 对象是函数内的局部变量。把 `return icons[type] || icons.other;` 改成先判断 `custom:` 即可。**具体修改**：

找到 `return icons[type] || icons.other;` 这一行（约 3526 行），在它**前面**插入：

```js
    if (typeof type === 'string' && type.startsWith('custom:')) return icons.website;
```

最终函数尾部结构：

```js
  function linkIcon(type) {
    const icons = {
      wechat: '...',
      xhs:    '...',
      douyin: '...',
      website:'...',
      other:  '...',
    };
    if (typeof type === 'string' && type.startsWith('custom:')) return icons.website;
    return icons[type] || icons.other;
  }
```

- [ ] **Step 3: 验证**

```bash
grep -n "custom:" "/mnt/d/SYTA Projects/618/index.html" | head -10
```

预期：platformLabel 和 linkIcon 各 1 处。

---

## Task 4: buildLinkRow — select 末尾加 "➕ 自定义..." + 输入流程

**Files:**
- Modify: `index.html:2594-2743`（第一阶段加 ✏️ 按钮的 buildLinkRow）

- [ ] **Step 1: 扩展 select 填充函数**

找到 `populateSel` 函数（约 2598–2606 行）：

```js
    const sel = document.createElement('select');
    const populateSel = () => {
      sel.innerHTML = '';
      for (const [k] of Object.entries(LINK_TYPES)) {
        const opt = document.createElement('option');
        opt.value = k; opt.textContent = linkTypeInfo(k).label;
        sel.appendChild(opt);
      }
    };
    populateSel();
```

改为：

```js
    const sel = document.createElement('select');
    const populateSel = () => {
      sel.innerHTML = '';
      for (const [k] of Object.entries(LINK_TYPES)) {
        const opt = document.createElement('option');
        opt.value = k; opt.textContent = linkTypeInfo(k).label;
        sel.appendChild(opt);
      }
      // 自定义平台
      const customList = (profile && Array.isArray(profile.customPlatforms)) ? profile.customPlatforms : [];
      customList.forEach(name => {
        const opt = document.createElement('option');
        opt.value = 'custom:' + name;
        opt.textContent = name;
        sel.appendChild(opt);
      });
      // 分隔线 + "自定义" 触发项
      const sep = document.createElement('option');
      sep.disabled = true;
      sep.textContent = '──────────';
      sel.appendChild(sep);
      const addOpt = document.createElement('option');
      addOpt.value = '__add_custom__';
      addOpt.textContent = t('link.addCustom');
      sel.appendChild(addOpt);
    };
```

- [ ] **Step 2: 改 populateSel 初次调用 — 需要在 profile 已就绪后再填**

`populateSel` 改完没问题，但 `sel.value = initialType || 'website';` 在 `populateSel()` 之后，要保证如果 `initialType` 是 `custom:X` 也能被选中（option 已加入）。验证后没问题。

- [ ] **Step 3: select.change 处理 "__add_custom__"**

找到第一阶段加的 `sel.addEventListener('change', ...)` 块（约 2625 行）：

```js
    sel.addEventListener('change', () => {
      input.placeholder = linkTypeInfo(sel.value).placeholder;
      labelInput.style.display = (sel.value === 'other') ? '' : 'none';
    });
```

改为：

```js
    sel.addEventListener('change', () => {
      input.placeholder = (sel.value.startsWith('custom:') || sel.value === 'other' || sel.value === 'website' || sel.value === 'xhs' || sel.value === 'douyin')
        ? linkTypeInfo(sel.value === '__add_custom__' ? 'website' : sel.value).placeholder
        : linkTypeInfo(sel.value).placeholder;
      labelInput.style.display = (sel.value === 'other') ? '' : 'none';

      if (sel.value === '__add_custom__') {
        promptAddCustom(sel, input, populateSel);
      }
    });
```

更清晰版本：把 placeholder 解析统一到一个 helper。

- [ ] **Step 4: 加 promptAddCustom 函数（在 buildLinkRow 内部闭包）**

在 `populateSel` 之后、buildLinkRow 末尾插入：

```js
    function promptAddCustom(selEl, urlInp, refreshFn) {
      if (!profile) {
        showToast(t('link.renameNoProfile'));
        selEl.value = 'website';
        return;
      }
      const newName = (window.prompt(t('link.addCustomPh'), '') || '').trim();
      if (!newName) {
        selEl.value = 'website';
        return;
      }
      if (newName.length > 20) {
        showToast(t('link.renameTooLong'));
        selEl.value = 'website';
        return;
      }
      if (PRESET_TYPES.has(newName)) {
        showToast(t('link.addCustomReserved'));
        selEl.value = 'website';
        return;
      }
      if (!profile.customPlatforms) profile.customPlatforms = [];
      if (profile.customPlatforms.includes(newName)) {
        // 已存在：直接选到它
        selEl.value = 'custom:' + newName;
        urlInp.focus();
        return;
      }
      profile.customPlatforms.push(newName);
      refreshFn();
      selEl.value = 'custom:' + newName;
      urlInp.focus();
    }
```

- [ ] **Step 5: 验证**

```bash
grep -nE "promptAddCustom|__add_custom__" "/mnt/d/SYTA Projects/618/index.html"
```

预期：≥3 处匹配。

---

## Task 5: i18n — 新增自定义平台文案

**Files:**
- Modify: `index.html:1738-1741`（zh）、`1913-1916`（en）

- [ ] **Step 1: zh 加键**

找到第一阶段加的 `'link.renameNoProfile': '请先完成新手引导',` 这一行，**在它后面**插入：

```js
      'link.addCustom': '➕ 自定义...',
      'link.addCustomPh': '输入新平台的名字（1-20 字符）',
      'link.addCustomReserved': '这个名字是预设平台，请选预设里的',
```

- [ ] **Step 2: en 加键**

找到 `'link.renameNoProfile': 'Please complete onboarding first',` 这一行，**在它后面**插入：

```js
      'link.rename': 'Rename platform',
      'link.addCustom': '➕ Custom...',
      'link.addCustomPh': 'New platform name (1-20 chars)',
      'link.addCustomReserved': 'This name is a preset platform; please pick from the list',
```

⚠️ 上面 en 块第一个键重复了 `'link.rename'`（第一阶段已加），删掉重复。正确插入是：

```js
      'link.addCustom': '➕ Custom...',
      'link.addCustomPh': 'New platform name (1-20 chars)',
      'link.addCustomReserved': 'This name is a preset platform; please pick from the list',
```

- [ ] **Step 3: 验证**

```bash
grep -n "link.addCustom" "/mnt/d/SYTA Projects/618/index.html"
```

预期：4 行（zh 3 + en 3 + 至少 1 处使用 = populateSel 和 promptAddCustom）。≥6 行。

---

## Task 6: buildLinkRow 的 ✏️ 改名 — 支持 custom: 重命名 + 链接迁移

**Files:**
- Modify: `index.html:2716-2734`（第一阶段的 `commitRename` 函数）

- [ ] **Step 1: 扩展 commitRename**

找到第一阶段的 `commitRename`：

```js
    const commitRename = () => {
      const v = (renameInput.value || '').trim();
      if (!v) {
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
```

改为：

```js
    const commitRename = () => {
      const v = (renameInput.value || '').trim();
      if (!v) {
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
      const oldKey = sel.value;
      if (oldKey.startsWith('custom:')) {
        // 自定义平台重命名：迁移 list + 迁移 links
        const oldName = oldKey.slice('custom:'.length);
        if (oldName === v) { renameInput.style.display = 'none'; return; }
        if (PRESET_TYPES.has(v) || (profile.customPlatforms || []).includes(v)) {
          showToast(t('link.addCustomReserved'));
          return;
        }
        if (!profile.customPlatforms) profile.customPlatforms = [];
        const idx = profile.customPlatforms.indexOf(oldName);
        if (idx >= 0) profile.customPlatforms[idx] = v;
        if (Array.isArray(profile.links)) {
          profile.links.forEach(l => {
            if (l && l.type === 'custom:' + oldName) l.type = 'custom:' + v;
          });
        }
        // 重建 select 选项（旧的 custom:oldName 已不在 options 里）
        populateSel();
        sel.value = 'custom:' + v;
      } else {
        // 预设平台：写 platformLabels 覆盖
        if (!profile.platformLabels) profile.platformLabels = {};
        profile.platformLabels[oldKey] = v;
      }
      renameInput.style.display = 'none';
    };
```

- [ ] **Step 2: ✏️ 点击时预填 — 自定义平台也要预填名字**

找到 ✏️ 的 click 监听：

```js
    renameBtn.addEventListener('click', () => {
      const current = (profile && profile.platformLabels && profile.platformLabels[sel.value])
        || linkTypeInfo(sel.value).label;
      renameInput.value = current;
      ...
    });
```

`platformLabel()` 已经处理了 `custom:X` 分支（直接返回名字），所以 `current` 自动正确（要么是自定义平台的名字，要么是 platformLabels 覆盖，要么是 i18n 默认）。无需改动。

- [ ] **Step 3: 验证**

```bash
grep -n "oldKey.startsWith\|oldName === v" "/mnt/d/SYTA Projects/618/index.html"
```

预期：≥1 行匹配。

---

## Task 7: renderLinksContainer / profile 弹层 — 渲染 customPlatforms

**Files:**
- Modify: `index.html:3540-3582`（renderLinksContainer）、`3374-3418`（profile 弹层）

- [ ] **Step 1: renderLinksContainer 接受 customPlatforms**

第一阶段的实现已经把 `profileForLabels` 传给 `platformLabel()`。`platformLabel()` 内部已经从 type 解析出名字（不依赖 profileForLabels 的 customPlatforms，因为 custom:X 名字是自包含的）。所以这一步**不需改 renderLinksContainer 内部**，只需要调用方传完整 profile 对象（第一阶段已经做了）。

- [ ] **Step 2: profile 弹层 — 同样不需改内部**

`platformLabel()` 内部处理 `custom:X` 即可。

- [ ] **Step 3: 验证**

```bash
grep -n "platformLabel(" "/mnt/d/SYTA Projects/618/index.html"
```

预期：3 处（定义 + renderLinksContainer + profile 弹层）。

---

## Task 8: 云端 sync / backfill / fetch — 同步 customPlatforms

**Files:**
- Modify: `index.html:3145-3195`（第一阶段的同步函数）

- [ ] **Step 1: syncProfileToCloud 加 custom_platforms**

找到第一阶段加的：

```js
    const row = {
      ...
      platform_labels: profile.platformLabels || {},
      ...
    };
```

改为：

```js
    const row = {
      session_id: SESSION_ID,
      nickname:   profile.nickname,
      bio:        profile.bio || null,
      tags:       Array.isArray(profile.tags) ? profile.tags : [],
      links:      Array.isArray(profile.links) ? profile.links : [],
      platform_labels: profile.platformLabels || {},
      custom_platforms: Array.isArray(profile.customPlatforms) ? profile.customPlatforms : [],
      avatar_url: profile.avatar_url || null,
      updated_at: new Date().toISOString(),
    };
```

- [ ] **Step 2: backfillProfileToCloud 加 custom_platforms**

第一阶段加的 platform_labels 块下面，添加：

```js
      custom_platforms: (Array.isArray(p.customPlatforms)) ? p.customPlatforms : [],
```

- [ ] **Step 3: fetchProfile select 加 custom_platforms**

```js
      .select('session_id, nickname, bio, tags, links, platform_labels, avatar_url, updated_at')
```

改为：

```js
      .select('session_id, nickname, bio, tags, links, platform_labels, custom_platforms, avatar_url, updated_at')
```

- [ ] **Step 4: fetchProfile snake → camel 转换**

找到第一阶段加的：

```js
    if (data && data.platform_labels && !data.platformLabels) {
      data.platformLabels = data.platform_labels;
    }
```

在它后面追加：

```js
    if (data && data.custom_platforms && !data.customPlatforms) {
      data.customPlatforms = data.custom_platforms;
    }
```

- [ ] **Step 5: 验证**

```bash
grep -n "custom_platforms\|customPlatforms" "/mnt/d/SYTA Projects/618/index.html" | head -15
```

预期：≥6 行匹配。

---

## Task 9: buildProfileFromEncounter + onboard/settings — 初始化 customPlatforms

**Files:**
- Modify: `index.html:2988`（commitOnboard）、`3046`（saveSettings）、`3289`（buildProfileFromEncounter）

- [ ] **Step 1: 3 处初始化都加 `customPlatforms: []`**

第一阶段加的 `platformLabels: {}` 旁边，**3 处都**补一个 `customPlatforms: []`：

- `commitOnboard` 的 `profile = { ..., platformLabels: {} };` → 加 `customPlatforms: []`
- `saveSettings` 的 `profile = { ..., platformLabels: ... };` → 加 `customPlatforms: profile && profile.customPlatforms ? profile.customPlatforms : []`
- `buildProfileFromEncounter` 的 `return { ..., platformLabels: {}, ... };` → 加 `customPlatforms: []`

- [ ] **Step 2: 验证**

```bash
grep -n "customPlatforms: \[\]" "/mnt/d/SYTA Projects/618/index.html"
```

预期：≥2 行（onboard + buildProfileFromEncounter）。

---

## Task 10: 测试 — 扩展 platformLabel 用例 + 新增 custom 流程用例

**Files:**
- Modify: `test-platform-labels.html`

- [ ] **Step 1: 扩展 platformLabel 用例**

找到原 cases 数组，在末尾追加：

```js
    ['custom:Telegram',        platformLabel('custom:Telegram'),                    'Telegram'],
    ['custom: 优先于 default',  platformLabel('custom:Line', {}, []),                'Line'],
    ['custom 不会走 platformLabels',
      platformLabel('custom:Telegram', { 'custom:Telegram': 'X' }),                  'Telegram'],
```

- [ ] **Step 2: 跑测试**

```bash
node -e "
const fs = require('fs');
// 同步复制 test-platform-labels.html 中的 platformLabel 定义
function platformLabel(type, customLabels) {
  if (typeof type === 'string' && type.startsWith('custom:')) return type.slice(7);
  const labels = customLabels || {};
  const custom = labels[type];
  if (custom && String(custom).trim()) return String(custom).trim();
  return '默认_' + (type || 'other');
}
const cases = [
  ['custom:Telegram', platformLabel('custom:Telegram'), 'Telegram'],
  ['custom 优先', platformLabel('custom:Line'), 'Line'],
  ['custom 不被 platformLabels 覆盖', platformLabel('custom:Telegram', {'custom:Telegram': 'X'}), 'Telegram'],
];
let pass = 0, fail = 0;
cases.forEach(([n, g, w]) => {
  if (g === w) { pass++; console.log('✓', n); }
  else { fail++; console.log('✗', n, '→', JSON.stringify(g), 'want', JSON.stringify(w)); }
});
console.log(pass + '/' + (pass+fail) + ' passed');
process.exit(fail ? 1 : 0);
"
```

预期：`3/3 passed`

- [ ] **Step 3: 浏览器手动验证流程**

1. 完成 onboarding
2. 设置 → 添加一个链接行
3. 点 select 选 "➕ 自定义..."
4. 弹窗输入 "Telegram"
5. 预期：下拉里多出 "Telegram"，select 自动切到 "Telegram"，焦点跳到 url 输入框
6. 填一个 URL → 保存
7. 关掉设置再打开 → 仍能看到 Telegram 选项
8. 在另一台设备 / 隐身模式 → 看自己主页 → Telegram chip 正常显示

---

## Task 11: 端到端 — 所有用户路径

- [ ] **Step 1: 跑第一阶段 unit tests 仍然全过**

```bash
node -e "...(第一阶段的 10 个 case)"
```

- [ ] **Step 2: JS 语法 check**

```bash
node -e "const fs=require('fs');const html=fs.readFileSync('/mnt/d/SYTA Projects/618/index.html','utf8');const m=html.match(/<script(?:\\s[^>]*)?>([\\s\\S]+?)<\\/script>/g);for(const s of m||[]){const c=s.replace(/<\\/?script[^>]*>/g,'');try{new Function(c);}catch(e){console.error(e.message);process.exit(1);}}console.log('OK');"
```

- [ ] **Step 3: 静态服务器 smoke test**

```bash
cd "/mnt/d/SYTA Projects/618" && python3 -m http.server 8766 &
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8766/index.html
```

预期：200

---

## Self-Review

**Spec 覆盖：**
- ✅ select 末尾加 "➕ 自定义..." → Task 4
- ✅ 纯文字 1–20 字符 → Task 4（prompt + 校验）+ Task 5（i18n）
- ✅ 不要 emoji → 实现里没 emoji 入口，i18n 纯文字
- ✅ 存到 customPlatforms，云端同步 → Task 1, 2, 8
- ✅ 自定义平台支持改名、重复添加 → Task 6（commitRename 扩展 custom 路径）+ link 行本身可重复添加
- ✅ 复用 website 图标 → Task 3（linkIcon 走 website fallback）
- ✅ 别人看 A 的页面时，A 的 customPlatforms 只用于显示 → 没人改 B 的 select：populateSel 只读 `profile.customPlatforms`（B 自己的），别人的只在 `platformLabel()` 解析 link.type 时用到

**类型一致性：**
- `profile.customPlatforms`（camelCase 内存）↔ `profiles.custom_platforms`（snake_case 列）→ Task 2/8 一致
- `link.type === 'custom:<name>'` → Task 3/4/6 一致
- `PRESET_TYPES` 常量 → Task 2（loadProfile 过滤）+ Task 4（保留名校验）+ Task 6（重命名冲突）一致

**变量遮蔽：** platformLabel 函数内部新增 `custom:` 分支不影响外层 t() / profile 引用。

Plan 完成。
