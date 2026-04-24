---
name: wechat
description: macOS WeChat CLI + local HTTP bridge — send messages, query sessions / contacts / chat history / Moments / favorites, and expose a stable HTTP surface for agent integration. Use when the user asks to "send a WeChat message", "发微信", query WeChat contacts/groups/messages, look up who said what in a chat, read moments / 朋友圈, export chat history, or wire WeChat into Hermes / n8n / Dify / LangChain. Requires WeChat 4.1.8 on macOS (Apple Silicon) and a `wxp_act_` activation code. One-time `wechat init` extracts the DB key; no sudo, no re-signing WeChat.app.
metadata:
  author: leeguooooo
  version: "1.10.0"
  platform: macOS-arm64
  requires:
    - macOS >= 14 (Apple Silicon)
    - WeChat 4.1.8 (CFBundleVersion 36830 / 37335 / 37342) running
    - LLDB (Xcode Command Line Tools)
    - Accessibility permission for the Terminal (only for `send`)
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

# SSE message stream
curl -N 'http://127.0.0.1:18400/messages/stream'
```

Endpoints:

| Method | Path | Maps to |
|---|---|---|
| GET  | `/health` | ping + send_status |
| GET  | `/chats` | sessions |
| GET  | `/unread` | unread |
| GET  | `/contacts` | contacts (query + limit) |
| GET  | `/chat/:wxid/history` | history (limit + since + until) |
| GET  | `/resolve` | resolve_recipient |
| POST | `/send` | send_text — returns `{status: delivered / submitted_unconfirmed / status_unknown / failed, diagnostic, ...}` |
| GET  | `/messages/stream` | new_messages_since polled into SSE |

**Security notes for agents:**
- Bridge binds 127.0.0.1 — not exposed to LAN without tunnelling.
- Set `WECHAT_BRIDGE_BEARER=<secret>` env var to require `Authorization: Bearer <secret>` on non-`/health` routes. Use this if tunnelling via Tailscale / SSH.
- **Activation gating is enforced inside wechatd**, not in the bridge. A missing / expired `wxp_act_` token → HTTP 401 / 402 on `/send`. Bridge cannot bypass subscription.

## Command groups

| Group | Commands | First-time requirement |
|-------|----------|-----------------------|
| Diagnostics | `doctor` | — (run first; checks AX permission, daemon status, dylib SHA-256 fingerprint) |
| Setup | `init` | requires user to click 进入 WeChat during the ~5 min window |
| Send | `send` | first `send` after each WeChat restart prompts user to type one short message + Enter in WeChat (auto InputView bootstrap, ~5 s) |
| Query (messaging) | `sessions`, `unread`, `new-messages`, `contacts`, `history`, `search`, `members`, `stats`, `export` | `init` first; daemon auto-starts on demand (v1.7.5) |
| Query (Moments) | `sns-feed`, `sns-search`, `sns-notifications` | `init` first; daemon auto-starts on demand |
| Saved items | `favorites` | `init` first; daemon auto-starts on demand |
| **Realtime (v1.3+)** | `listen` | daemon auto-starts on demand (v1.7.5) |
| **Daemon (v1.2+)** | `daemon start\|stop\|status\|ping` | optional — query/listen commands pull it up automatically when needed |
| **HTTP Bridge (v1.10+)** | `wechat-bridge` (separate binary) | agent / Hermes / n8n integration over localhost HTTP — see section below |
| **Auth (v1.9.1+)** | `auth activate \| status \| renew` | mandatory activation before `send` — code from @WechatCliBot on Telegram |

All query commands default to **YAML output** (agent-friendly, low token). Add `--json` to get JSON.

---

## 🛑 Safety rules (CRITICAL — read before calling `send`)

**Every `send` call must specify `--wxid` OR `--current-chat` explicitly.** No silent default. Reason: "给 Lisa 发早上好" without wxid resolution can hit the wrong chat (boss, family, etc.) — consequences are severe.

Correct flows for "给 XXX 发 YYY":

1. **Just try it**: `wechat send "YYY" XXX`. Fast-path resolver (see top of this doc) handles wxid-shaped targets instantly and fuzzy-matches names against the local contact DB with session-recency bias.
2. **On exit 2 + `status: "ambiguous"`**: if `candidates[0]` has `last_seen` within ~30 days and others are stale/empty, the CLI already auto-picked it and returned success. If it truly was ambiguous (multiple candidates with recent activity), pick one yourself by asking the user — don't guess.
3. **On "no contact matches"**: either ask the user for the wxid, or tell them to open the chat in WeChat and use `wechat send "YYY" --current-chat` (3s Ctrl-C abort).

**Hard rules (the agent MUST follow):**

- **DO NOT** guess or fabricate a wxid. If resolution fails, escalate to the user.
- **DO NOT** silently send to the current chat without explicit `--current-chat`.
- **DO NOT** scan the filesystem / grep logs / use AppleScript to hunt for a wxid. The CLI already searches the local contact DB via the fast path — trust it. If it can't find the recipient, stop and ask the user.
- **DO NOT** invoke `wechat contacts` followed by `wechat send` as two separate calls unless the first fast-path send already told you it was ambiguous. The one-liner saves ~400ms and one agent round-trip.

---

## Capability matrix

| Capability | Status | Command |
|------------|--------|---------|
| Extract DB key, cache layout (required first step for query commands) | ✅ | `wechat init` |
| Send text to a specific wxid | ✅ | `wechat send --text "..." --wxid <id>` |
| Send to currently open chat (3s abort window) | ✅ | `wechat send --text "..." --current-chat` |
| Any Unicode / emoji / CJK / length | ✅ | built-in |
| Zero UI flash (no focus steal) | ✅ | default for `send` |
| List recent chat sessions | ✅ | `wechat sessions` |
| Sessions with unread messages | ✅ | `wechat unread` |
| Incremental new messages since last check | ✅ | `wechat new-messages` |
| Contact lookup / fuzzy search | ✅ | `wechat contacts [--query KW]` |
| Chat history (private / group) | ✅ | `wechat history <chat> [-n 500]` |
| Full-DB keyword search | ✅ | `wechat search <kw> [--in CHAT]` |
| Group members | ✅ | `wechat members <group>` |
| Chat statistics (senders / types / hours) | ✅ | `wechat stats <chat>` |
| Export chat → Markdown / JSON | ✅ | `wechat export <chat> --format markdown -o ...` |
| Favorites (text/image/article/...) | ✅ | `wechat favorites [--type ...] [--query KW]` |
| Moments timeline | ✅ | `wechat sns-feed [--user NAME]` |
| Moments keyword search | ✅ | `wechat sns-search <kw>` |
| Moments interactions (likes / comments) | ✅ | `wechat sns-notifications` |
| InputView bootstrap (one-time per WeChat session) | ✅ | auto-invoked by first `send` after WeChat restart |
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

Key is only written to memory during the login moment, so `init` attaches LLDB with a conditional breakpoint and waits up to 300 s. If the user misses the window or WeChat was already logged in before `init` ran, the breakpoint never fires — rerun `wechat init --force`.

Result saved to `~/.wx-rs/key.hex` (mode 0600) + `~/.wx-rs/config.json`. Re-run `init` whenever WeChat restarts.

`init` also prints the detected WeChat version/build and the `wechat.dylib` SHA-256 fingerprint check. If the hash isn't in the verified set (e.g. Tencent pushed a hot-fix dylib), send/query may silently fail at the LLDB layer — reinstall the official dmg from https://mac.weixin.qq.com/en and verify the auto-update toggle at WeChat → 设置 → 通用 → 「有更新时自动升级」 is off.

**Step 3 — (For `send` only) Accessibility permission**:

Run `wechat doctor`. If the terminal hasn't been granted Accessibility yet, this pops the native macOS dialog **and** opens the Privacy & Security → Accessibility pane directly — no hunting. Toggle the terminal app ON, then quit + relaunch the terminal (macOS requires a restart for the permission to take effect).

If you prefer the manual path: System Settings → Privacy & Security → Accessibility → add the terminal app you're using (Terminal / iTerm / Warp / …).

**Step 4 — (For `send` only) One-time InputView bootstrap per WeChat session**:

`send` needs WeChat's in-memory InputView address. The first `send` after each WeChat restart prompts:

> `[bootstrap] 等待抓取 InputView 地址。请在 WeChat 打开任意聊天，输入任意短消息，按回车。（每次 WeChat 重启后只需这一次）`

User types any short message (e.g. `.`) into any WeChat chat (filehelper is the safe test target) and presses Enter. The tool snapshots the InputView pointer via an LLDB breakpoint on the real send call, then the pending `wechat send` continues automatically. Cache lives in `~/.wechat/state.json` until the next WeChat restart.

There is no separate `wechat bootstrap` subcommand in v1.7+ — the bootstrap step only runs when needed, inline.

---

## Usage — send

```bash
# Known wxid → direct
wechat send --text "你好 🎉" --wxid filehelper
wechat send --text "会议 5 分钟后开始" --wxid lishuang683451

# Unknown wxid → look up via contacts first
wechat contacts --query Lisa       # returns lishuang683451 + variants
wechat send --text "早上好" --wxid lishuang683451

# Explicit current-chat with 3s abort window
wechat send --text "..." --current-chat

# Heap-mode (no AX; needs user-typed seed text)
wechat send --text "..." --wxid <id> --mode heap --seed "xxxxxxxxxx"
```

### `send` arguments

| Arg | Required | Description |
|-----|----------|-------------|
| `--text TEXT` | yes | Message body (any length, any Unicode) |
| `--wxid WXID` | yes (or `--current-chat`) | Target wxid |
| `--current-chat` | yes (or `--wxid`) | Explicit: send to currently open chat. Prints resolved wxid + 3s abort |
| `--mode ax | heap` | no (default ax) | `ax` = silent AX + auto-hide; `heap` = pure LLDB heap overwrite |
| `--auto-hide` / `--no-auto-hide` | default on | Hide WeChat before setValue (prevents flash) |
| `--seed TEXT` | for `--mode heap` | Current text in WeChat input field |
| `--inputview 0xADDR` | first-time bootstrap | Cache InputView instance address |
| `-v, --verbose` | no | Detailed technical output |
| `--json` | no | JSON output |

---

## Usage — query

```bash
# Sessions (recent conversations)
wechat sessions -n 20                           # all types
wechat sessions --filter private,group          # only real chats
wechat unread --filter private,group            # unread human chats

# Contacts
wechat contacts --query 李                     # fuzzy match nickname/remark/wxid
wechat contacts -n 500                          # list all

# History
wechat history "张三" -n 2000
wechat history "AI 星球" --since 2026-04-01 --until 2026-04-15 -n 200

# Search
wechat search "会议纪要"
wechat search "报销" --in "财务群" --since 2026-01-01

# Group members
wechat members "AI 星球"

# Stats
wechat stats "AI 星球" --since 2026-01-01

# Export
wechat export "张三" --format markdown -o zhang.md
wechat export "AI 星球" --format json -o ai.json -n 5000

# Incremental (since last checkpoint saved in ~/.wechat/state.json)
wechat new-messages            # advances checkpoint
wechat new-messages --peek     # read-only; does NOT advance checkpoint

# Favorites
wechat favorites                          # all
wechat favorites --type image             # text / image / voice / video / article / card / file / location
wechat favorites --query "会议"

# Moments
wechat sns-feed                           # recent locally-cached posts
wechat sns-feed --user "张三" -n 50
wechat sns-search "婚礼" --user "李四"
wechat sns-notifications                   # unread by default
wechat sns-notifications --include-read
```

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
wechat listen --format json

# Trigger a shell command per message — the handler sees WECHAT_MSG_* env vars
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
wechat sessions --json | jq '.[] | select(.chat_type=="private" and .unread>0)'
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
- "朋友圈里有没有人提到婚礼" → `wechat sns-search 婚礼`
- "XXX 的朋友圈" → `wechat sns-feed --user XXX`
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

**`init`** — restarts WeChat, sets an LLDB breakpoint at a known write offset, reads the 32-byte raw key as it is written to a register during startup. No `codesign --force --deep` on `WeChat.app`, no `sudo`. Immediately detaches after capture.

**Query commands** — load the raw key + discovered DB paths from `~/.wechat/keys.json`, open each `.db` via the `sqlcipher` CLI with WeChat's PRAGMAs (cipher_compat=4, kdf_iter=256000, cipher_page_size=4096, HMAC_SHA512, PBKDF2_HMAC_SHA512), run SELECTs in JSON mode, parse. When the background daemon is running, queries are routed over a local Unix socket to a persistent SQLCipher connection pool — amortizes PBKDF2 cost and cuts latency 5-10×.

**`listen`** — watches `message_*.db-wal` files for mtime changes, queries `Msg_*` tables for rows newer than the last seen `create_time`, decodes content (zstd-decompressed if needed), strips the group `<sender>:\n` prefix, and pushes each new row to subscribed CLI processes over the daemon socket. Zero network traffic; runs entirely locally against the on-disk WeChat databases.

**`send`** — uses macOS Accessibility API to set `AXHidden=True` (silent hide) + setValue into `chat_input_field`, then LLDB-`WriteMemory` overwrites `InputView+0x2B8` with target wxid SSO `std::string`, then LLDB `expression` cold-calls `mmui::InputView::Send(0)` via its RVA. Zero window activation / focus steal.

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
