# 自定义平台名 + 同平台重复添加 + 自定义新增 — 设计

## 目标
让用户能为每个平台**重命名**（如把"微信"改成"Instagram"），并能**重复添加同一平台**（多个微信/多个小红书等）。
改后的名称**全用户可见**（云端同步）。用户只需要写**纯文字名字**（不需要 emoji）。

**第二阶段：用户能新增自定义平台**（如"Telegram"），从 select 末尾的"➕ 自定义..."入口添加，云端同步；自定义平台支持改名、重复添加、复用地图图标。别人看到 A 的页面时，A 的自定义平台仅用于显示名字，B 自己的下拉里不会出现 A 创建的项。

## 数据模型

### 链接条目（不变）
```
p.links = [{ type: 'wechat' | 'xhs' | 'douyin' | 'website' | 'other', url, label? }, ...]
```
- 同一 `type` 允许出现多次
- `other` 类型的 `label` 字段继续存在（每条独立），与平台名覆盖互不冲突
- 微信号保持纯文本 ID 语义（不跳转、可重复多条文本 ID）

### 新增：平台名覆盖表
```
p.platformLabels = { wechat: 'Instagram', xhs: '...', douyin: '...', website: '...', other: '...' }
```
- key 是 5 个预设 `type`
- value 是 1–20 字符的纯文字（trim 后非空）
- 缺省/未设置时，回退到 i18n `link.<type>` 的翻译值
- 整张表随 `saveProfile` 一起写到云端（`profiles.platform_labels` 列）

### 新增：自定义平台列表
```
p.customPlatforms = ['Telegram', 'WhatsApp', 'Line', ...]
```
- 用户自己创建的**新 type**，纯文字 1–20 字符
- 内部以 `custom:Telegram`（带前缀 `custom:`）作为 `link.type` 写入 `p.links`（这样不会和 5 个预设 `type` 撞名）
- 渲染时，`linkIcon()` 看到 `custom:X` 一律返回 `website` 的地球 SVG
- 渲染时，`platformLabel()` 看到 `custom:Telegram` 直接返回 `Telegram`（不需要再查 platformLabels）
- 云端同步（`profiles.custom_platforms` 列，JSONB 数组）
- 别人看到 A 的页面时，A 的 `customPlatforms` 仅用于 `platformLabel` 显示；B 自己的 select 下拉**不会出现** A 创建的项

### schema 变更
- 在 `profiles` 表加 JSONB 列 `platform_labels`，默认 `'{}'::jsonb`
- 在 `profiles` 表加 JSONB 列 `custom_platforms`，默认 `'[]'::jsonb`
- 兼容旧数据：加载时 `platform_labels ?? {}`、`custom_platforms ?? []`

## UI 改动（链接编辑器）

### 当前
```
[ select 平台 | ✏️ 改名 | label-input(仅 other) | url-input | 删除 ]
```

### 改为
```
[ select 平台(含"➕ 自定义...") | ✏️ 改名 | url-input | 删除 ]
```
- select 选项：**5 个预设 + 用户 `customPlatforms` 列表 + 末尾的 "➕ 自定义..."**
- 选 "➕ 自定义..." → select 后 inline 出现一个 text 输入框，用户输入新平台名（1–20 字符纯文字）
- 提交：把新名字加入 `profile.customPlatforms`（去重），下拉里立即多出一个选项；select 自动切到新选项，输入框消失，焦点跳到 url-input
- 取消（Esc 或空值）：输入框消失，select 回到原值
- 重复添加：同一 `type` 已有 N 行时仍可继续添加（不阻止）
- ✏️ 改名按钮**对自定义平台也生效**（改的是 `customPlatforms` 列表中的名字 → 通过 `custom:X` 间接处理：改名时同步更新 `p.links` 中所有 `custom:oldname` → `custom:newname`，否则历史链接会显示旧名）

### ✏️ 改名按钮行为（更新）
- 对预设 type：写 `profile.platformLabels[type]`
- 对自定义 type（`custom:X`）：重命名 `profile.customPlatforms` 中的 X，同步迁移所有引用（见上）

## 渲染改动

### 显示名解析（更新）
```js
function platformLabel(type, customLabels, customPlatforms) {
  // 1. 自定义平台：直接返回名字
  if (typeof type === 'string' && type.startsWith('custom:')) {
    return type.slice('custom:'.length);
  }
  // 2. 预设平台：platformLabels 覆盖 > i18n 默认
  const labels = customLabels || (profile && profile.platformLabels) || {};
  const custom = labels[type];
  if (custom && String(custom).trim()) return String(custom).trim();
  return linkTypeInfo(type).label;
}
```

### 用到的地方
1. `renderLinksContainer`（chip 文本）— 传 `profileForLabels.platformLabels` + `customPlatforms`
2. 个人主页弹层链接渲染 — 传 `p.platformLabels` + `p.customPlatforms`
3. 编辑器内 select 选项文字 — 自定义平台直接显示名字

### 图标
- `custom:X` → 走 `linkIcon('website')`（地球 SVG）
- 5 个预设 type 对应 5 个固定 SVG（保留原样）
- `linkIcon()` 收到 `custom:X` 时把前缀剥掉，看内置 icons 表里有没有；没有就 fallback `website`

## 校验与保存

### 改名
- 1–20 字符，trim 后非空
- 空字符串 = 不保存（保持原值）
- 不允许纯空白

### 添加自定义平台
- 1–20 字符，trim 后非空
- 不能和预设 type 重名（`wechat/xhs/douyin/website/other`）
- 不能和已有 `customPlatforms` 重名（去重）
- 不需要 URL（URL 留给 link 行单独填）

### 保存
- 用户点"保存"时，`platformLabels` + `customPlatforms` 整体写入 `profiles` 行
- 通过现有 `saveProfile` + `syncProfileToCloud` 流程
- 不需要新接口

### 加载他人 profile
- A 的 `customPlatforms` 仅用于显示（A 创建的链接名）
- B 自己的下拉里**不会出现** A 创建的项
- B 看到的 chip 文字用 A 的覆盖名；B 自己添加的同 type 链接走 B 自己的 `customPlatforms`

## 范围

### ✅ 包含
- 5 个预设平台都能改名
- 改名（纯文字 1–20 字符）
- 同平台可重复添加
- 平台名同步到云端
- 保留原 SVG 图标
- 新增自定义平台（纯文字 1–20 字符）
- 自定义平台云端同步
- 自定义平台支持改名、重复添加
- 自定义平台复用 website 图标
- i18n（中文/英文）错误提示

### ❌ 不包含
- 改 emoji / 自定义图标
- 删除预设平台
- 平台库管理 UI（单独的"管理平台"页面）
- 重命名历史/撤销
- 别人复用 A 创建的自定义平台

## 测试要点（实施时再细化）

1. 编辑器：改名 → 保存 → 重新打开设置 → 显示新名
2. 渲染：别人看我的页面，看到我改的名
3. 重复添加：加 3 个"微信"行 → 都能保存 + 渲染为 3 个 chip
4. 兼容性：旧 profile 没有 `platform_labels` 列时，UI 正常（回退到 i18n）
5. 校验：空名 / 超 20 字符 / 全空白 → 拒绝保存，给 toast

## 影响的文件

- `index.html` — 编辑器 UI、渲染、helper、saveProfile
- `schema.sql` — `platform_labels` JSONB 列
- `setup-guide-user.sql` — 同上（如有）
- `README.md` — 简短说明（可选）
- `SPEC.md` — 同步更新（如需要）
