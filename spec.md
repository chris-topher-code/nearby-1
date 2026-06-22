# Near-Field Encounter Board — Optimized Spec

> A refined, implementation-ready version of the original brief. Improvements are inline.

## 0. Scope

A pure-static HTML page that, on load, geolocates the visitor and shows anonymous messages ("footprints") left by strangers within **100 m** in the last **5 minutes**. Visitors can leave one of their own.

## 1. Stack

- **Frontend**: HTML + CSS + vanilla JS. No frameworks, no bundlers.
- **Backend**: Supabase (free tier). Loaded via CDN (`@supabase/supabase-js` UMD bundle).
- **Hosting**: Any static host (Vercel / Netlify / GitHub Pages). HTTPS is mandatory (geolocation requires it).

## 2. Database

### 2.1 Table `nearby_encounters`

| column        | type             | notes                                                  |
|---------------|------------------|--------------------------------------------------------|
| `id`          | `uuid` PK        | `default gen_random_uuid()`                            |
| `content`     | `text` NOT NULL  | no length cap                                          |
| `latitude`    | `float8` NOT NULL|                                                        |
| `longitude`   | `float8` NOT NULL|                                                        |
| `session_id`  | `text` NOT NULL  | per-browser anon id from `localStorage`                |
| `nickname`    | `text` NOT NULL  | user-chosen at onboarding / via settings; no cap       |
| `bio`         | `text`           | optional, no cap                                       |
| `links`       | `jsonb` NOT NULL | array of `{type, url, label?}`; default `'[]'`         |
| `tags`        | `text[]` NOT NULL| interest tags, e.g. `['🎮 游戏','📚 书籍']`; default `'{}'` |
| `created_at`  | `timestamptz`    | `default now()`                                        |

Indexes:
- `created_at` DESC (for the 5-minute window query).

### 2.1a Table `profiles` (persistent identity)

| column        | type             | notes                                                  |
|---------------|------------------|--------------------------------------------------------|
| `session_id`  | `text` PK        | one row per browser session                            |
| `nickname`    | `text` NOT NULL  | latest nickname                                        |
| `bio`         | `text`           | latest bio                                             |
| `tags`        | `text[]` NOT NULL| latest tag set, default `'{}'`                         |
| `links`       | `jsonb` NOT NULL | latest links array, default `'[]'`                     |
| `avatar_url`  | `text`           | Supabase Storage public URL                            |
| `updated_at`  | `timestamptz`    | last sync timestamp                                    |

RLS: anon can SELECT (read others' profiles), INSERT, UPDATE, DELETE. Frontend is trusted to only mutate its own row (no JWT claim available on anon key for stricter server-side check).

### 2.1b Storage bucket `avatars`

- Public bucket; read = open to anyone.
- Anon can insert / update / delete (path: `avatars/<session_id>.jpg`).
- Avatars are JPEG 256×256, ~85% quality, ~50–150 KB typical after client-side resize.

### 2.2 RLS

Enable RLS. Allow `anon` role to `SELECT` and `INSERT`. No `UPDATE`/`DELETE`.

### 2.3 SQL

See `schema.sql` in repo.

## 3. UI / Interaction

### 3.1 Top status bar

States:
- `pending`  → "正在获取定位..."
- `ok`       → "定位成功 ✓"
- `denied`   → red banner: "定位被拒绝，页面无法使用。请刷新并允许定位。"
- `error`    → "定位失败，请允许浏览器权限"

If state is `denied` or `error`, the input + button are **disabled**.

### 3.2 Input area

- Top line shows the current identity: `以 [昵称] 的身份留下足迹` (hidden until onboarding complete).
- `<textarea>` with no `maxlength`, `placeholder="此刻，你想说什么？"`.
- Big primary button "留下足迹" (desktop) / circular transmit icon (mobile).
- Submit:
  - Empty content → inline hint "说点什么吧".
  - Location not ready → "定位中，请稍后...".
  - No profile (somehow bypassed onboarding) → reopen onboarding.
  - Insert row → clear input → show "✅ 已发送" for 2s.
  - Supabase error → "网络波动，正在重试..." at list bottom (do not white-screen).

### 3.2a Onboarding (first visit only)

- On first load (no `encounter_profile` in `localStorage`), show a full-screen modal:
  - "昵称" input (required, no length cap)
  - "自我介绍" textarea (optional, no length cap)
  - "联系方式" section: dynamic list of `{type, url}` rows (see 3.2c)
  - "开始" button
- Cannot be dismissed by clicking the backdrop — must complete to use the app.
- On save → write to `localStorage`, close modal, enable submit.

### 3.2b Settings

- Gear icon in top-right opens a modal with the same fields, pre-filled from `localStorage`.
- "保存" updates `localStorage` and the input area identity line.
- "取消" / clicking the backdrop closes without saving.
- New encounters from now on carry the updated nickname / bio / links. Existing rows are not retroactively modified.

### 3.2c Contact links

- Each link is `{ type, url, label? }`. Supported types: `wechat`, `xhs` (小红书), `douyin`, `website`, `other`.
- Editor: rows of `<select type> + [optional label input, shown only when type=other] + <url input> + <delete button>`, plus "添加一个链接" button.
- `label` is only meaningful for `other` links; user-typed name shown on the card chip instead of "其他链接".
- Saved in `localStorage` as `profile.links`; sent with each insert.
- Validation:
  - `wechat`: plain text ID (stored as-is, displayed as "微信: <id>", click → copy to clipboard).
  - All other types: must match `^https?://...`; `javascript:` / `data:` rejected.
- Platform auto-detection from URL host (`xiaohongshu.com`/`xhslink.com` → `xhs`, `douyin.com` → `douyin`, etc.) when type is `website` / `other`.
- Rendered on cards as chips: platform icon + "平台 · 域名" label (or "自定义名 · 域名" for `other` with label), `target="_blank"`.

### 3.2d Interest tags

- Editor (in onboarding + settings): row of preset chips (`🎮 游戏`, `📚 书籍`, `🎬 电影`, `🎵 音乐`, `🏃 运动`, `🍜 美食`, `✈️ 旅行`, `💻 编程`, `📷 摄影`, `🎨 绘画`, `🐱 宠物`, `☕ 咖啡`) plus a "+ 自定义标签" input (Enter to add, max 12 chars each, dedup, max 8 tags).
- Stored in `localStorage` as `profile.tags`; sent with each insert as `text[]`.
- Rendered on cards as small chips below the message body.

### 3.2e Debug panel (development aid)

- Open: desktop — long-press the gear button for 1 second; mobile — tap the gear 5 times within 1.5 seconds. (Normal click still opens settings.)
- Shows: session ID, Supabase host, location state + coords, profile summary, last fetch time + result count, last error (if any).
- Actions: jump location to preset (Beijing / Shanghai / Tokyo), revert to real GPS, toggle "show own messages" (bypasses self-isolation), manual refresh, copy SID, wipe localStorage.
- Auto-refreshes display after each `refresh()`.

### 3.2f Avatar upload

- Settings modal: circular preview (96 px) + "上传头像" / "移除头像" buttons.
- Client pipeline: validate type (`image/jpeg|png|webp`) and size (≤2 MB) → `FileReader` → `Image` → center-crop to square → draw to 256×256 canvas → `toBlob('image/jpeg', 0.85)`.
- Upload path: `avatars/<session_id>.jpg` (overwrite on each upload).
- Cache-bust: avatar URLs rendered with `?t=<timestamp>` so re-renders see updated image.
- Fallback: when no `avatar_url`, generate a colored circle from a hash of the nickname (6 palette colors × first character).

### 3.2g Profile page (author detail)

- Click any encounter card's avatar (or nickname) → opens `profileMask` modal.
- Fetches `profiles` row by `session_id` + author's encounters from last 24h.
- Renders: avatar + nickname + bio + tags + links (clickable) + recent messages list.
- Backdrop click / "关闭" closes the modal.
- Used by both desktop and mobile; sized for one-handed use.

### 3.3 List

- Initial fetch on load + polling every **15s** (± small jitter).
- Pause polling while `document.hidden`; resume immediately on visibility return.
- Fetch rows where `created_at > now() - 5min`.
- Client-side:
  - Compute Haversine distance to user coords.
  - Drop rows with `distance > 100 m`.
  - Filter out rows where `session_id === self.sessionId` ("self-isolation").
  - Sort by distance ascending.
- Empty state: "此刻，这里静悄悄... 你是第一个留下足迹的人吗？"
- Per-row format:
  - **Header row**: avatar (40 px, clickable to profile page) + nickname (accent color, bold) + optional `bio` (dim) + up to 3 inline tag hints.
  - Time: `< 1 min` → "刚刚"; else `Math.floor(seconds/60)` → "X 分钟前".
  - Distance: `< 10 m` → "在极近处"; else rounded int → "在约 [Y] 米外".
  - Body: the message text.
  - Link chips below (as before).

### 3.4 Error handling

Any Supabase read/write failure surfaces a small grey line at list bottom: "网络波动，正在重试...". No uncaught exceptions bubble up.

## 4. Config block

A single `CONFIG` object near the top of `index.html`:
```js
const CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-KEY',
  RADIUS_METERS: 100,
  WINDOW_MINUTES: 5,
  POLL_MS: 15000,
  MAX_CONTENT: 200,
};
```
**Never** put the service_role key here.

## 5. Compatibility notes

- `<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">`.
- Test on Android Chrome + iOS Safari. Both require HTTPS for geolocation.
- Use `navigator.geolocation.watchPosition` so a fix is available without re-prompting on each action.

## 6. Deliverables

- `index.html` — single-file app, Chinese comments at key blocks.
- `schema.sql` — table + RLS policies + index.
- This `SPEC.md`.