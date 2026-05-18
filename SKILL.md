---
name: wechat
description: "macOS WeChat CLI + local HTTP bridge + Wechaty Puppet gRPC gateway — send messages, query sessions / contacts / chat history / images / favorites, and expose stable HTTP / gRPC surfaces for agent integration. Use when the user asks to 'send a WeChat message', '发微信', query WeChat contacts/groups/messages, look up who said what in a chat, fetch images from history, export chat history, wire WeChat into Hermes / n8n / Dify / LangChain, or run any wechaty bot on a real macOS WeChat account. Requires WeChat 4.1.8 / 4.1.9 on macOS (Apple Silicon) and a `wxp_act_` activation code. One-time `wechat init` extracts the DB key; no sudo, no re-signing WeChat.app. Optional remote bridge — `wechat tunnel setup --hostname <yours>` exposes the local REST API via Cloudflare Tunnel for remote services to call."
metadata:
  author: leeguooooo
  version: "1.12.1"
  platform: macOS-arm64
  requires:
    - macOS >= 14 (Apple Silicon)
    - WeChat 4.1.8 (CFBundleVersion 36830 / 37335 / 37342) running
    - LLDB (Xcode Command Line Tools)
    - Accessibility permission for `wechat-bridge` (macOS Sonoma+, only for `send`; Terminal itself does NOT need it)
    - Activation code (wxp_act_…) from @WechatCliBot — subscribe the official Telegram channel first
---

# wechat — macOS CLI

Unified CLI for WeChat on macOS. Send messages in pure background (zero UI flash) AND query the local SQLCipher databases for sessions, contacts, chat history, group members, Moments, favorites.

## Fast path (read this first)

**Send a WeChat message in one call:**

```bash
wechat send "早上好" Lisa                 # fuzzy name match (remark / nick / alias)
wechat send "hi" filehelper              # wxid — zero DB lookup, fastest
wechat send "提醒一下" 20590343959@chatroom  # group wxid (ends in @chatroom)
```

Resolution rules (applied in order):

1. RECIPIENT matches a wxid shape (`wxid_…`, `…@chatroom`, `gh_…`, `biz_…`, or reserved like `filehelper`) → skip all DB work and send directly.
2. Otherwise, search the local contact DB (remark / nickname / alias / wxid) with session-recency bias:
   - single match → send
   - multiple matches but only one has recent activity (30d) → send to that one
   - otherwise → exit 2 + JSON `{"status":"ambiguous","candidates":[...]}`; the agent picks and retries with the explicit wxid

On ambiguous, a sample response:

```json
{
  "status": "ambiguous",
  "hint": "Lisa",
  "candidates": [
    {"wxid": "lishuang683451", "display_name": "lisa", "last_seen": "2026-04-20 05:34:55"},
    {"wxid": "wxid_xxx", "display_name": "Lisa (另一个)", "last_seen": ""}
  ],
  "note": "multiple matches; pass one of the wxids explicitly: wechat send <text> <wxid>"
}
```

Agent should: read `candidates[0].wxid`, retry `wechat send "<text>" <wxid>`. Don't ask the user unless the top candidate has no recent activity or multiple candidates do.

## HTTP Bridge for agent integration (v1.10+)

`wechat-bridge` is a separate binary that wraps the daemon's RPCs as a stable localhost HTTP surface. Use this when wiring WeChat into agent platforms (Hermes, n8n, Dify, LangChain, custom bots) — HTTP is cheaper to integrate than spawning the CLI per call.

```bash
# Start bridge (binds 127.0.0.1:18400 by default)
wechat-bridge &

# Health + send-readiness
curl http://127.0.0.1:18400/health

# Send
curl -X POST http://127.0.0.1:18400/send \
  -H 'Content-Type: application/json' \
  -d '{"wxid":"filehelper","text":"hi"}'

# SSE message stream — ⚠️ ALWAYS pass ?since=<epoch>
# Without ?since, default is 0 = backfills entire local message history
# (1MB+ in seconds for typical accounts). For agent / long-running flows
# always pass a since timestamp; pick "now" for live-only or last-checkpoint.
SINCE=$(date +%s)
curl -N "http://127.0.0.1:18400/messages/stream?since=$SINCE"
```

Endpoints:

| Method | Path | Maps to |
|---|---|---|
| GET  | `/health` | ping + send_status |
| GET  | `/chats` | sessions |
| GET  | `/unread` | unread |
| GET  | `/contacts` | contacts (query + limit) |
| GET  | `/chat/:wxid` | recent N messages for one chat |
| GET  | `/chat/:wxid/history` | history (limit + since + until) |
| GET  | `/resolve` | resolve_recipient |
| POST | `/send` | send_text — returns `{status: delivered / submitted_unconfirmed / status_unknown / failed, diagnostic, ...}` |
| POST | `/typing` | typing indicator (only when `--shape hermes`) |
| GET  | `/messages/stream?since=<epoch>` | new_messages_since polled into SSE; **pass `since`** or you'll get the full backlog on first connect |

### SSE payload shape (v1.10.28 — Wechaty-aligned + isMentioned)

`/messages/stream` emits `event: messages` carrying a JSON array of:

```ts
{
  messageId: string,
  chatId: string,                // wxid (DM) or groupid@chatroom
  senderId: string,              // in group: sender's wxid; in DM: the other party's wxid
  senderName: string,
  chatName: string,
  isGroup: boolean,
  body: string,                  // human-readable text. For URL / quote / mini_program, body is the title — raw XML is NOT exposed here.
  hasMedia: boolean,
  mediaType: "image"|"voice"|"video"|"file"|"",
  mediaUrls: string[],           // first entry is CDN URL when applicable
  mentionedIds: string[],        // v1.10.25+ — authoritative @-mention list resolved by daemon
  isMentioned: boolean,          // v1.10.28+ — bridge-authoritative "this row @-mentions ME". Self-sent rows are always false.
  quotedParticipant: string,     // v1.10.27+ — populated from refer.fromUser on quote replies
  botIds: string[],              // legacy heuristic self-marker; NEW consumers should rely on fromSelf instead
  fromSelf: boolean,             // v1.10.25+ — bridge-authoritative "this row was produced by our own POST /send"; DROP THESE to avoid self-echo loops
  messageKind: "text"|"image"|"audio"|"video"|"contact"|"emoticon"|"location"|
               "url"|"attachment"|"mini_program"|"chat_history"|"transfer"|
               "red_envelope"|"recalled"|"system"|"unknown",  // v1.10.27+, aligned to Wechaty's MessageType enum
  urlLink?:     { title, description, url, thumbUrl },                             // present iff messageKind=url
  miniProgram?: { title, description, appId, username, pagePath, thumbUrl },        // present iff messageKind=mini_program
  refer?:       { svrId, fromUser, chatUser, displayName, content },              // present on quote replies
  recall?:      { replacedMsgId, text },                                            // present iff messageKind=recalled
  media?:       { aesKey, md5, cdnUrl, cdnThumbUrl, length, durationSeconds, localPath },  // structured metadata for image/audio/video/attachment
  timestamp: number,
}
```

The full JSON Schema is committed at [`wx/schema/sse-payload-v1.10.28.schema.json`](https://github.com/leeguooooo/wechat-skill/blob/main/wx/schema/sse-payload-v1.10.28.schema.json) and enforced by a contract test in the daemon build.

**Consumer checklist:**

- Filter self-echo with `fromSelf === true`. Do NOT use `senderId === myWxid` — in DM both directions share the same senderId.
- In groups, only respond when `isGroup && isMentioned` — the daemon already resolves the authoritative mention comparison, so don't reimplement `mentionedIds.includes(myWxid)` yourself (your wxid may be a remark / lookup that the daemon resolves correctly). The bridge will also drop non-`@` group rows automatically when `WECHAT_BRIDGE_GROUP_MENTION_ONLY=1`.
- Need the URL only? `mediaUrls[0]`. Need aesKey + md5 to decrypt or verify? `media.cdnUrl / media.aesKey / …`.
- For `messageKind: "image"`, do **not** inline base64 image bytes in chat responses. Call `wechat image get <messageId> --chat <chatId> --json`, parse `absolutePath`, then use the host agent's file/image Read capability on that path. Default `--from auto` (since v1.13.11) tries the daemon's heap scan first (fast, works when the user has opened the image at least once in WeChat) and falls back to CDN replay only on miss. If the result is `image not yet viewed in WeChat (heap empty), and CDN fallback failed`, ask the user to open the image once in WeChat and retry. `cdn-expired` or `needs local-decrypt RE` means neither path can recover this image — surface that to the user instead of guessing.
- Expect `body` for URL / quote / mini_program to be the human title. If you were previously parsing raw `<appmsg>` XML from body, migrate to the dedicated `urlLink` / `miniProgram` / `refer` objects.
- Backward compatible: every pre-v1.10.25 field is preserved in name + type. New fields are additive.

**Security notes for agents:**
- Bridge binds 127.0.0.1 — not exposed to LAN without tunnelling.
- Set `WECHAT_BRIDGE_BEARER=<secret>` env var to require `Authorization: Bearer <secret>` on non-`/health` routes. Use this if tunnelling via Tailscale / SSH.
- **Activation gating is enforced inside wechatd**, not in the bridge. A missing / expired `wxp_act_` token → HTTP 401 / 402 on `/send`. Bridge cannot bypass subscription.

## Command groups

| Group | Commands | First-time requirement |
|-------|----------|-----------------------|
| Diagnostics | `doctor` | — (run first; checks AX permission, daemon status, dylib SHA-256 fingerprint) |
| Setup | `init` | requires user to click 进入 WeChat during the ~5 min window |
| Send | `send` | first `send` after each WeChat restart fails with `delivery_verify_timeout` until the user manually types + Enters one message in WeChat to warm up the send dispatch path (~5 s) |
| Query (messaging) | `sessions`, `unread`, `new-messages`, `contacts`, `history`, `search`, `members`, `stats`, `export`, `image`, `sent` (v1.16.12+, cross-chat self-sent) | `init` first; daemon auto-starts on demand (v1.7.5) |
| Saved items | `favorites` | `init` first; daemon auto-starts on demand |
| **Realtime (v1.3+)** | `listen` | daemon auto-starts on demand (v1.7.5) |
| **Daemon (v1.2+)** | `daemon start\|stop\|status\|ping` | optional — query/listen commands pull it up automatically when needed |
| **HTTP Bridge (v1.10+)** | `wechat-bridge` (separate binary) | agent / Hermes / n8n integration over localhost HTTP — see section below |
| **Wechaty Puppet gateway (v1.10.32+)** | `wechat-wechaty-gateway` (separate binary, gRPC :18401) | for the human writing a wechaty bot — NOT used by this skill. If the user asks "can I run my wechaty bot on this?", point them to https://github.com/leeguooooo/wechat-skill#接-ai-agent and stop. Don't try to write wechaty TS from this skill. |
| **`wechat tunnel` (v1.11+)** | `wechat tunnel setup` | Expose local REST bridge to a remote service via Cloudflare Tunnel; details in `docs/remote-gateway.md`, do NOT inline the full setup flow in this skill. |
| **`wechat orchestrate` (v1.12+)** | `wechat orchestrate setup --outbox-url= --webhook-url= --bearer= --webhook-secret=` | Long-running worker that polls a SaaS outbox API and pushes SSE inbound events to a SaaS webhook. NAT-friendly (Mac all-outbound, no public IP / domain). Used by SaaS integrations (cherry-class). Protocol: `docs/v1.12-orchestrate-protocol.md`. Don't inline the SaaS-side endpoint design here. |
| **Auth (v1.9.1+)** | `auth activate \| status \| renew` | mandatory activation before `send` — code from @WechatCliBot on Telegram |

All query commands default to **YAML output** (agent-friendly, low token). Add `--json` to get JSON.

---

## 🛑 Safety rules (CRITICAL — read before calling `send`)

**Every `send` call must resolve to a known wxid.** No silent default to "current chat" — that flag (`--current-chat`) was removed pre-1.13; if the resolver can't find a recipient, stop and ask the user.

Correct flows for "给 XXX 发 YYY":

1. **Just try it**: `wechat send "YYY" XXX`. Fast-path resolver (see top of this doc) handles wxid-shaped targets instantly and fuzzy-matches names against the local contact DB with session-recency bias.
2. **On exit 2 + `status: "ambiguous"`**: if `candidates[0]` has `last_seen` within ~30 days and others are stale/empty, the CLI already auto-picked it and returned success. If it truly was ambiguous (multiple candidates with recent activity), pick one yourself by asking the user — don't guess.
3. **On `no contact matches "XXX"`**: ask the user for the wxid (or have them confirm a candidate from `wechat contacts --query XXX --brief`).

**Hard rules (the agent MUST follow):**

- **DO NOT** guess or fabricate a wxid. If resolution fails, escalate to the user.
- **DO NOT** scan the filesystem / grep logs / use AppleScript to hunt for a wxid. The CLI already searches the local contact DB via the fast path — trust it. If it can't find the recipient, stop and ask the user.
- **DO NOT** invoke `wechat contacts` followed by `wechat send` as two separate calls unless the first fast-path send already told you it was ambiguous. The one-liner saves ~400ms and one agent round-trip.

---

## Capability matrix

| Capability | Status | Command |
|------------|--------|---------|
| Extract DB key, cache layout (required first step for query commands) | ✅ | `wechat init` |
| Send text to a specific wxid / 群名 / 昵称 | ✅ | `wechat send "..." <recipient>` |
| Any Unicode / emoji / CJK / length | ✅ | built-in |
| Zero UI flash (no focus steal) | ✅ | default for `send` |
| List recent chat sessions | ✅ | `wechat sessions` |
| Sessions with unread messages | ✅ | `wechat unread` |
| Incremental new messages since last check | ✅ | `wechat new-messages` |
| Contact lookup / fuzzy search | ✅ | `wechat contacts [--query KW]` |
| Chat history (private / group) | ✅ | `wechat history <chat> [-n 500]` |
| **LLM-ready group digest** | ✅ v1.13.33 | `wechat digest <chat>` |
| Full-DB keyword search | ✅ | `wechat search <kw> [--in CHAT]` |
| Group members | ✅ | `wechat members <group>` |
| Chat statistics (senders / types / hours) | ✅ | `wechat stats <chat>` |
| Export chat → Markdown / JSON | ✅ | `wechat export <chat> --format markdown -o ...` |
| Favorites (text/image/article/...) | ✅ | `wechat favorites [--type ...] [--query KW]` |
| Image media (heap scan + CDN fallback) | ✅ | `wechat image get <messageId> --chat <id>` |
| Voice media (raw SILK_V3) | ✅ | `wechat audio get <svr_id>` (1.13.21+) |
| Voice transcribe (whisper.cpp + SILK pipeline) | ✅ | `wechat audio setup` 一次 + `wechat audio transcribe <svr_id>` (1.13.25+) |
| InputView warmup (manual, once per WeChat session) | required | first `send` errors with `delivery_verify_timeout`; user types one msg in WeChat then re-runs `wechat send` |
| **Realtime inbound stream (v1.3)** | ✅ | `wechat listen` — watches new messages, push to stdout |
| **Inbound callback → shell command (v1.3)** | ✅ | `wechat listen --on-message "handler.sh"` (WECHAT_MSG_* env vars) |
| **Server-side wxid filter (v1.3)** | ✅ | `wechat listen --wxid filehelper` |
| **Background daemon (v1.2+, lazy-start v1.7.5)** | ✅ | `wechat daemon start` — or auto-spawn by any query command |
| **Dylib SHA-256 fingerprint verification (v1.7.2+)** | ✅ | `wechat doctor` surfaces drift after Tencent hot-fix updates |
| Send image / file | ⏳ roadmap | — |
| Group broadcast | ❌ disallowed | anti-abuse; LICENSE forbids |
| Linux / Windows / Intel Mac | ❌ | macOS arm64 only |
| WeChat build ≠ 36830 / 37335 | ⚠️ unverified | offsets may drift; `wechat doctor` flags it |

---

## Agent: first-use setup

**Step 1 — Check `wechat` is on PATH**:

```bash
command -v wechat
```

If missing:

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
# Ensure ~/.local/bin is on PATH
case "${SHELL##*/}" in
  fish) fish_add_path "$HOME/.local/bin" ;;
  zsh)  grep -q '.local/bin' ~/.zshrc  2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc ;;
  bash) grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc ;;
esac
export PATH="$HOME/.local/bin:$PATH"
```

**Step 2 — Run `wechat init`** (required before any query command):

```bash
wechat init
```

This **restarts WeChat** (closes current session + relaunches) in order to capture the decryption key at login. Tell the user:
> "Going to briefly close and relaunch WeChat to extract the local database key. Any draft messages in WeChat will be lost — confirm before proceeding. **After WeChat relaunches, you must click 「进入 WeChat」 (or scan QR if no cached account) within ~5 minutes** — the key is only written during that sign-in."

Key material is only written during the login moment, so `init` attaches LLDB once during that window and waits up to 300 s. If the user misses the window or WeChat was already logged in before `init` ran, capture won't trigger — rerun `wechat init --force`.

Result is saved to `~/.wx-rs/` (mode 0600 files) + `~/.wx-rs/config.json`. Re-run `init` whenever WeChat restarts.

`init` also prints the detected WeChat version/build and a dylib fingerprint check. If the fingerprint isn't in the verified set (e.g. Tencent pushed a hot-fix dylib), send/query may silently fail — reinstall the official dmg from https://mac.weixin.qq.com/en and verify the auto-update toggle at WeChat → 设置 → 通用 → 「有更新时自动升级」 is off.

**Step 3 — (For `send` only) Accessibility permission**:

Run `wechat doctor`. If the terminal hasn't been granted Accessibility yet, this pops the native macOS dialog **and** opens the Privacy & Security → Accessibility pane directly — no hunting. Toggle the terminal app ON, then quit + relaunch the terminal (macOS requires a restart for the permission to take effect).

If you prefer the manual path: System Settings → Privacy & Security → Accessibility → add the terminal app you're using (Terminal / iTerm / Warp / …).

**Step 4 — (For `send` only) One-time InputView warmup per WeChat session**:

`send` needs WeChat's send dispatch path to be fully wired, which only happens after a real user-initiated send. The first `wechat send` after each WeChat restart fails with:

> `error: 消息发送路径已执行,但数据库核查窗口内没有找到匹配新消息。常见原因:WeChat 输入框还没 warmup,首次 send 之前需要在 WeChat 里手动发一条让发送路径建好。`

Resolution (the error itself prints these steps):

1. Open WeChat
2. Click "文件传输助手" (filehelper)
3. Type any short message (e.g. `hi`)
4. Press Enter to send
5. Re-run `wechat send` — succeeds on retry, and stays warm until WeChat restarts.

This is intrinsic to WeChat's Qt event loop; no automation can substitute. If `wechat doctor` reports `ax_trusted: true` and warmup still doesn't help, file an issue.

---

## Usage — send

```bash
# Recipient resolves wxid / 群名 / 昵称 / 备注 (fuzzy match against local contact DB)
wechat send "你好 🎉" filehelper
wechat send "会议 5 分钟后开始" lishuang683451
wechat send "早上好" Lisa                # 找不到 → friendly error + 候选

# Group send (resolver also handles group display names)
wechat send "今天 19:00 团建" "AI 星球"

# JSON output for agents that parse responses
wechat send "ok" filehelper --json

# Dry-run: resolve recipient + validate args, do NOT actually send. Useful when
# the agent wants to verify a fuzzy name → expected wxid before committing.
wechat send "draft" "李工" --dry-run --json
```

### `send` arguments

| Arg | Required | Description |
|-----|----------|-------------|
| `<TEXT>` (positional) | yes | Message body. Any length, any Unicode. |
| `<RECIPIENT>` (positional) or `--wxid` | yes | Target wxid / chatroom id / 昵称 / 群名 / 备注. Resolver picks the most-recently-active match if hint is fuzzy. |
| `--mention <wxid>` | no | Visual `@<name>` prefix (text-only, no real ping ack — see issue #4). |
| `--dry-run` | no | Resolve recipient + validate but don't send. Pairs well with `--json` for agent dry-checks. |
| `--json` | no | JSON output |

### `send --json` 三态契约 (v1.13.20+)

所有 `--json` 输出都带顶层 `ok: bool`,agent 直接 `if (r.ok) {...} else {...}` 不需要解析三套 schema:

| 状态 | 触发 | shape (顶层字段) |
|---|---|---|
| **success** | `wechat send TEXT RECIPIENT --json` 真发成功 | `{ok: true, sent: true, reason: null, diagnostic: {…SendResult 全字段…}}` |
| **dry-run** | `--dry-run --json`(resolver OK + 不真发) | `{ok: true, dry_run: true, text, resolved_wxid}` |
| **error (early)** | `--json` + 参数错 / resolver 找不到 / ambiguous / 网络断 | `{ok: false, exit_code: <int>, error: "<msg>"}` |
| **error (send fail)** | 真发失败 (InputView warmup miss / TCC 缺 / dylib mismatch) | `{ok: false, sent: false, reason: "<reason>", diagnostic: {…}}` |

```bash
# 推荐:agent 用 jq 分支
wechat send "hi" filehelper --dry-run --json | jq -e '.ok' && echo "✓ resolved" || echo "✗ failed"
```

stderr 仍然有 human-readable 错误描述(给终端用户看);agent 只需 parse stdout JSON。

---

## Usage — query

```bash
# Sessions (recent conversations)
wechat sessions -n 20                           # full yaml
wechat sessions --brief -n 20                   # 单行/会话, 带未读数
wechat sessions --filter group --json -n 20     # 只看群聊 (chat_type: group / private / official_account / folded / other)
# JSON 字段命名:未读数是 `unread_count`(下划线全名), 不是裸 `unread`。brief 视图渲染成 [N unread] 仅是显示, 实际字段是 unread_count。

# Contacts
wechat contacts --query 李                      # fuzzy match nickname/remark/wxid
wechat contacts --brief -n 50                   # 单行/联系人 (姓名 + wxid)

# Unread
wechat unread -n 5

# History (chat positional or --chat flag, both accepted)
wechat history "张三" -n 2000
wechat history --chat 21263894984@chatroom -n 200
wechat history "AI 星球" --since "2026-04-01" --until "2026-04-15" -n 200   # ISO date OK
wechat history "AI 星球" --since 1719793200 --until 1720484400 -n 200       # epoch OK too

# Search
wechat search "会议纪要"
wechat search "报销" --in "财务群"

# Group members
wechat members "AI 星球"

# Stats
wechat stats "AI 星球"
```

### `history --json` payload shape (stable contract for agents)

**顶层包装(`history` / `sessions` / `unread` / `search` / `digest` 全一致):**

```json
{
  "meta": {
    "chat_latest_timestamp": 1778981425,
    "shards_scanned": 2,
    "shards_hit": 2,
    "status": "ok",
    "order": "desc"
  },
  "rows": [ {...row...}, {...row...} ]
}
```

不是裸数组。`jq` 要 `.rows[]` 不是 `.[]`。`meta.order` 是 v1.16.12+ 加的字段,告诉
你 rows 是 `"desc"`(新→老,history 默认)还是 `"asc"`(老→新,digest 默认 / `wechat
history --order asc`)。**别拿 `rows[0]` 当"最新"也别当"最老",先看 `meta.order`。**

`meta.status` 取值:`ok` / `windowed`(传了 `--since`/`--until`)/ `possibly_stale`
(SessionTable 比 history 领先 > 24h,大概率分片漂)/ `possibly_stale_unknown_shards`
(磁盘有新分片 daemon 不认,要重跑 `wechat init`)。

**每条 message row 字段(snake_case):**

| 字段 | 类型 | 说明 |
|---|---|---|
| `local_id` | int | DB 行主键(per chat 单调)。`image get <local_id> --chat <wxid>` 用这个取图。 |
| `server_id` | int | WeChat 服务端 msg id(撤回时引用 `replacedMsgId`)。 |
| `local_type` | int | 原始 type code。低 16 位 mask 后 = `1` 文本 / `3` 图 / `34` 语音 / `43` 视频 / `49` appmsg / 等。 |
| `message_kind` | string | enum: `text` / `image` / `audio` / `video` / `url` / `mini_program` / `recalled` / `appmsg` / 等。Wechaty 对齐。 |
| `display_text` | string | 已清洗后的 human-readable body(text 直接 = body;image/url 抽 title;recalled 给替代文案)。 |
| `message_content` | string | 原始 body(可能是 raw XML / 群消息带 `<sender>:\n` 前缀)。debug 用,生产逻辑请用 `display_text`。 |
| `sender_wxid` | string \| null | 群消息 = 真发送者 wxid;**DM 两侧都是 `null`**(WeChat DB 在 1:1 chat 不记 sender wxid)。**不能单凭这个判 self-sent**(DM 会双方都误判 + 系统消息也是 null)。 |
| `sender_display_name` | string \| null | daemon-resolved 展示名(群里的群昵称 / 联系人备注 / 昵称)。群里基本都有;DM self-sent / 系统消息为 null。 |
| `real_sender_id` | string | per-chat 自增 ID(字符串,**永远非空**)。WeChat 给当前账号分配一个固定 id(本机经验值是 `"2"`,不同账号可能不同),其它整数 = 对方/群成员。**判 self-sent 用这个**:扫 `filehelper` 历史得到自己的 id(filehelper 100% 自发,占比最大那个就是 self id),其它 chat 用同一 id 过滤。 |
| `chat_id` / `username` | string | 会话 wxid(DM)或 `xxxx@chatroom`(群)。 |
| `chat_display_name` | string | 群名 / 联系人备注 / 昵称(v1.13.9+ 自动解析)。`xxxx@chatroom` 直接看得懂。 |
| `create_time` | int | epoch seconds。 |
| `created_at` | string | ISO 本地时区(`2026-05-18T01:30:45+09:00`),v1.13.30+ 派生,人读直接拿这个。 |
| `is_mentioned` | bool | 当前账号在群里被 `@` 了(daemon 端权威解析,客户端别再算一遍)。 |
| `media` | object | `image` / `voice` / `video` / `file` 才有: `{aesKey, md5, cdnUrl, cdnThumbUrl, length, durationSeconds, localPath, dat_path?, dat_md5?, dat_exists?}`。 |
| `urlLink` / `miniProgram` / `refer` / `recall` | object | type-specific 结构化字段(见 SSE schema)。 |

字段稳定性:增加 = 默认 `null` / 缺省;**不会**重命名 / 改类型(契约由 v1.10.27 起的 SSE schema 单测守)。

**想跨 chat 拉"我说过什么":** 用 `wechat sent --since "7 days ago" --json`(v1.16.12+),
比手动遍历 sessions + filter 干净得多。

**群名歧义:** `wechat history "AI 星球"` 可能匹配多个(同名群 + 同名联系人)。
撞歧义时 CLI 会列出候选 + 报错,改用 `--chat <wxid>` 或 `--chat <chatroom_id@chatroom>`
明确指定。常用群建议在自己脚本里做个 alias map(目前 CLI 没内置)。

```bash

# Export
wechat export "张三" --format markdown -o zhang.md
wechat export "AI 星球" --format json -o ai.json -n 5000

# Incremental (since last checkpoint saved in ~/.wx-rs/cursor.json)
wechat new-messages -n 50      # advances checkpoint
wechat new-messages --reset    # rewind checkpoint to "now" so next call starts fresh

# Favorites
wechat favorites                          # all locally-cached items

# Image media (heap scan first, CDN fallback)
wechat image get <local_id> --chat <chat_id>            # decrypts + writes to ~/.wechat/media-cache/<md5>.jpg
wechat image inspect <local_id> --chat <chat_id>        # dump CDN metadata (no key/url leak)

# Voice media — history auto-transcribes by default (v1.13.25+)
wechat audio setup [--model small|medium|large]         # one-time: install deps + download model
wechat audio transcribe <svr_id> [--language zh]        # single-file pipeline
wechat audio get <svr_id>                               # raw SILK_V3 bytes, no decode
```

### Voice — agents reading group history just work (v1.13.25+)

After running `wechat audio setup` once (~2-3 minutes downloads ~1.5GB
medium model + builds silk-decoder), **`wechat history` automatically
transcribes voice messages** so the agent sees the spoken content in
`display_text` (and structured in `media.transcript`) — no more
`[语音消息]` placeholders breaking conversation context. Transcripts are
cached by SHA-256 of the audio blob, so re-reading the same chat is
near-instant.

```bash
# One-time setup
wechat audio setup

# Read a chat — voice messages already transcribed inline
# (Output is {meta, rows} not a bare array — use `.rows[]` not `.[]`.)
wechat history <chat> --json | jq '.rows[] | {kind: .message_kind, text: .display_text}'
```

Opt-out (skip transcribe to keep history fast / private):

```bash
wechat history <chat> --no-transcribe                   # skip transcribe entirely
wechat history <chat> --transcribe-model small          # smaller / faster model
wechat history <chat> --quiet                           # silence stderr progress lines
                                                        # (auto-on in --json mode)
```

The `media.transcript_status` field on each audio row tells the agent
where the text came from: `cached` / `transcribed` / `no_deps` (run
`wechat audio setup`) / `failed` / `skipped_svr_id_zero` / `invalid_input`.

`wechat doctor` reports audio readiness in two rows so machine consumers
can check default-model status without parsing strings:

- `audio_transcribe_setup` — overall ffmpeg / whisper-cli / silk-decoder
  presence. Always `ok: true` (audio is optional; missing tools must
  not flip overall doctor status to `needs_init`).
- `audio_transcribe_default_model` — `ggml-medium.bin` exists. `ok`
  reflects reality, but excluded from the overall status calculation
  so a user without medium still sees `status: "ok"`. Read this row's
  `ok` field directly to know whether `wechat history` default
  transcribe will work.

For a single voice file outside `history`:

```bash
SVR=$(wechat history <chat> --json | jq -r '.rows[] | select(.message_kind=="audio") | .server_id' | head -1)
wechat audio transcribe "$SVR"           # prints transcript directly
```

`wechat audio transcribe --json` defaults to redacting the transcript
text (only metadata in JSON output) so agents can't accidentally log
private conversation text. Pass `--include-transcript` to opt in.

### Voice — manual decode if you skip `audio setup`

`wechat audio get <svr_id>` writes the raw `.silk` bytes locally
(pure local read; no LLDB / heap scan / CDN). To play / share without going through `audio transcribe`:

```bash
# One-time decoder build
git clone https://github.com/kn007/silk-v3-decoder /tmp/silk-v3-decoder
cd /tmp/silk-v3-decoder/silk && make

# Per-file
SVR=691336177198502815
wechat audio get "$SVR"
/tmp/silk-v3-decoder/silk/decoder ~/.wechat/audio-cache/$SVR.silk /tmp/$SVR.pcm
ffmpeg -y -f s16le -ar 24000 -ac 1 -i /tmp/$SVR.pcm /tmp/$SVR.wav
```

> **Note**: SNS / Moments commands (`sns-feed`, `sns-search`, `sns-notifications`) and the legacy `bootstrap` subcommand were removed in the v1.13 line. The data is still in `sns.db` if you query it directly with sqlcipher, but no first-class CLI surface yet — track via roadmap.

---

## Usage — realtime listen (v1.3)

**`wechat listen` streams new incoming WeChat messages to stdout as they arrive** (latency <500ms). Requires the background daemon.

```bash
# One-time: start the daemon (keep running in a separate terminal or `&`)
wechat daemon start

# Stream all new messages
wechat listen

# Stream only messages from one chat (server-side filter)
wechat listen --wxid filehelper

# JSONL output for agent consumption
# IMPORTANT: pipe stdout only — daemon spawn / errors go to stderr.
#   wechat listen --format json | your-adapter      ← OK
#   wechat listen --format json 2>&1 | your-adapter ← WRONG, stderr 混流会把 [daemon] 字样混进 stdin
wechat listen --format json

# Trigger a shell command per message — the handler sees WECHAT_MSG_* env vars
# Handler stdout is routed to /dev/null (so it doesn't pollute the JSONL stream
# that agents pipe to jq); use stderr or write to a file for logging.
wechat listen --on-message "./ai-reply.sh"
wechat listen --wxid lisa --on-message 'echo "[$(date +%H:%M)] $WECHAT_MSG_SENDER_WXID: $WECHAT_MSG_TEXT" >> log.txt'
```

### `--on-message` env vars

| Variable | Meaning |
|---|---|
| `WECHAT_MSG_TEXT` | Message body (already cleaned: compressed content decompressed, group `<sender>:\n` prefix stripped) |
| `WECHAT_MSG_SENDER_WXID` | Sender wxid for group messages (empty string for private chats — there the chat wxid = sender) |
| `WECHAT_MSG_TABLE` | `Msg_<md5(chat_wxid)>` — internal table name |
| `WECHAT_MSG_CREATE_TIME` | Unix epoch seconds (as string) |
| `WECHAT_MSG_LOCAL_ID` / `WECHAT_MSG_LOCAL_TYPE` | Internal message id + type code |
| `WECHAT_MSG_SENDER_ID` | DB `real_sender_id` (numeric; rarely needed — use `SENDER_WXID` instead) |
| `WECHAT_MSG_DB` | Absolute path of the message DB the message came from |

**Safety notes**:
- Content is passed via env vars, not shell-interpolated into the command. Safe against `$(rm -rf)` style injection.
- Handler runs async (one subprocess per message); if it takes longer than messages arrive, handlers will pile up. Keep handlers fast or add your own queueing.

### Daemon lifecycle

```bash
wechat daemon start              # foreground; or `wechat daemon start &` for background
wechat daemon status             # socket + pid + uptime
wechat daemon ping               # round-trip latency sanity check
wechat daemon stop               # graceful shutdown
```

The daemon caches each SQLCipher DB connection so `wechat sessions` / `contacts` / `history` / `unread` run in **<30ms** (vs 400-500ms without it). It also powers `wechat listen` by watching `message_*.db-wal` file changes.

### Fuzzy chat resolution

`history` / `search --in` / `stats` / `export` / `members` accept a `<chat>` argument that is matched against (in order): exact wxid → remark → nick_name → alias. If ambiguous, the most-recently-active match is picked. Use `wechat contacts --query ...` first if you need to disambiguate.

### Output format

All query commands emit YAML by default. Add `--json` for JSON:

```bash
wechat sessions --json | jq '.rows[] | select(.chat_type=="private" and .unread_count>0)'
wechat new-messages --json                # ideal for agents consuming incremental updates
```

---

## When to invoke this skill (agent triggers)

**Send**:

- "给 Lisa 发消息：..."
- "发微信通知我妈 '到家了'"
- "提醒 XXX 会议 5 分钟后开始"
- "send to filehelper ..."

**Query**:

- "微信里 Lisa 最近说了什么" → `wechat history Lisa`
- "搜一下群里谁提过报销" → `wechat search 报销`
- "AI 星球群有多少人 / 谁发言最多" → `wechat members` + `wechat stats`
- "有哪些未读消息" → `wechat unread`
- "导出我和张三的聊天记录" → `wechat export 张三 -o ...`
- "XX 群里那张图是什么" → `wechat history "XX群" -n 50` (找 message_kind: image 的 local_id) → `wechat image get <local_id> --chat <chat_id>`
- "最近收藏了什么" → `wechat favorites`

**Realtime**:

- "帮我盯着 Lisa 发来的消息，收到就自动回复 XXX" → `wechat daemon start` then `wechat listen --wxid <lisa-wxid> --on-message "..."`
- "把微信消息接进我的 AI assistant" → `wechat listen --format json --on-message "curl -X POST ..."`
- "监控这个群谁提到 '会议'，马上通知我" → `wechat listen --wxid <group>` + handler that greps

Example user utterances and the right first call:

- "给 Lisa 发消息：会议 5 分钟后开始"  → `wechat contacts --query Lisa` → `wechat send --wxid ... --text ...`
- "send to filehelper today's summary" → `wechat send --text ... --wxid filehelper`
- "查一下 XXX 群最近谁发言最多" → `wechat stats "XXX"`

---

## 🔐 Security / data scope

- Everything runs **100% locally** — no data leaves the machine.
- `wechat init` caches the raw DB key in `~/.wechat/keys.json` (mode 0600). **Treat that key like a password** — anyone with `keys.json` + a copy of `~/Library/Containers/com.tencent.xinWeChat/...` can decrypt all your WeChat data.
- Never commit `~/.wechat/` to git. Never paste the key into chat windows. If leaked: logout + re-login WeChat to rotate the key.

---

## Mechanism (brief)

**`init`** — relaunches WeChat and uses a one-shot LLDB attach during the login moment to capture the local DB decryption material. No `codesign --force --deep` on `WeChat.app`, no `sudo`. Detaches immediately after capture.

**Query commands** — load the captured material + discovered DB paths from local config and read the on-disk SQLCipher databases directly. When the background daemon is running, queries are routed over a local Unix socket to a persistent connection pool — cuts latency 5-10×.

**`listen`** — watches the on-disk message databases for changes and pushes each new row to subscribed CLI processes over the daemon socket. Zero network traffic; runs entirely locally.

**`send`** — uses macOS Accessibility API to silently target the chat input, then drives WeChat's normal send path via LLDB. Zero window activation / focus steal.

---

## Caveats

- **macOS arm64 only**, **WeChat 4.1.8** verified. Other versions may need offset rediscovery.
- Binary is a standalone native executable (GitHub Releases). `install.sh` auto-clears macOS Gatekeeper quarantine attribute.
- **Not a WeChat API**. Userland research artifact. Can break on any WeChat update.
- **LICENSE forbids commercial use** — see [LICENSE](LICENSE) + [DISCLAIMER.md](DISCLAIMER.md).

## Updating the CLI

Before starting a session, the agent should check that `wechat` is reasonably current. The binary is self-contained; upgrading just means pulling a newer release.

**Check current version**:

```bash
wechat --version
```

**Upgrade to latest (safe, idempotent)** — re-run `install.sh` with `--force`, or without it (it overwrites by default):

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
```

That pulls the latest tagged release binary from GitHub, re-installs to `~/.local/bin/wechat`, and re-clears any Gatekeeper quarantine attribute. No data is lost — `~/.wechat/keys.json` + `state.json` are untouched.

**When to upgrade**:

- `wechat --version` is more than one minor behind the latest release tag at https://github.com/leeguooooo/wechat-skill/releases
- A command that the user asks for doesn't exist yet (the capability matrix on this page reflects the latest release; older binaries may be missing commands)
- WeChat itself was updated — new versions may need a fresh `wechat` release to track shifted offsets (watch https://github.com/leeguooooo/wechat-skill/releases for a note)

**Updating the skill metadata** (this `SKILL.md` itself, when the agent is installed via `skills.sh`):

```bash
# refresh skill files (including this SKILL.md) from the public repo
npx skills update leeguooooo/wechat-skill -g
```

If the agent sees `wechat: command not found` after an `npx skills update`, it still needs to run `install.sh` — skill updates do **not** include the binary.

## Support

- Issues → https://github.com/leeguooooo/wechat-skill/issues
