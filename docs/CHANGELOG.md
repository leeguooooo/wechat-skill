# 更新日志

## v1.13.22 — 2026-05-06

`wechat audio get` 修 codex review 4 个 SHOULD-FIX(无 BLOCKER):

- **`--json` JSON sentinel 防 double-print**:之前 error 路径会让 main.rs 在 stderr 再打一次纯文本错误,跟 v1.13.20 send 同款。现在用 `__JSON_ENVELOPE_ALREADY_PRINTED__:` sentinel,wrapper strip 后单 stdout JSON envelope + 单 clean stderr message。
- **默认 redact 路径,避免泄漏账号目录指纹**:`absolutePath` / `matchedDb` 默认替换 `home → ~`、`xwechat_files/<account>_<hash>/ → <account>/`。语音泄漏比图风险更高(声纹),account dir 出现在 stdout JSON 里被 agent 上传 / log 是真实风险。新增 `--reveal-path` flag 显式解锁,JSON 里 `pathRedacted: bool` 让 agent 知道是否 redact。
- **SQL error 分类**:`rusqlite::ErrorCode::NotADatabase` → KeyError / `DatabaseBusy`|`DatabaseLocked` → Locked / 其余 → Other,每类单独 hint。原版把所有错误都 squash 进"transient lock,1-2s 重试",误导用户。
- **NULL voice_data vs no row 区分**:server 推了 metadata 但语音 body 没下载时(rare),`VoiceInfo` 行存在但 `voice_data IS NULL`。原版当作"row 不存在"处理,现在给精确 hint("WeChat 里点开播放一次让 client 拉 body")。

`audio get --help` `long_about` 加 kn007 + ffmpeg 解码 one-liner(SKILL.md 已有,help text 之前没)。

新增 3 个单元测试覆盖 redact 行为(总 8 audio tests,8/8 pass)。

## v1.13.21 — 2026-05-06

新增 `wechat audio get <svr_id>` — 取一条语音消息的 raw SILK_V3 字节,落盘到 `~/.wechat/audio-cache/<svr_id>.silk`(chmod 0600)。

**实现**:
- 直接读 `db_storage/message/media_*.db.VoiceInfo.voice_data` BLOB(SQLCipher 解了就纯 plaintext SILK_V3,无加密层、无 LLDB、无 heap scan、无 CDN replay)。
- 自动跨 `media_*.db` shard 扫(不硬编 `media_0.db`),svr_id=0(本地草稿/失败消息)显式 reject 给 hint。
- Strip Tencent 加的 1-byte `0x02` prefix,留 magic-byte sanity check(防未来 schema 漂移悄悄写出损坏文件)。
- JSON `--json` 三态 `ok: bool`(success / not-found / sanity-fail)。

**为什么不 bundle 解码器**:
- `silk-rs` Rust crate 2022 后无更新,质量不可信;
- macOS 系统 `ffmpeg` 没有 SILK codec(Tencent 的 SILK 是修改版,通用 SILK decoder 也搞不定);
- 唯一可靠路径是 `kn007/silk-v3-decoder`(C 项目)+ `ffmpeg` 二步走,SKILL.md 给 one-liner。

**沿用 image 隐私模式**:默认输出到 `~/.wechat/audio-cache/`(chmod 0600),`--out` 可覆盖。

cli_smoke 加 `audio_get_does_not_require_key_hex` ignored e2e 测试。

## v1.13.20 — 2026-05-06

主 agent + Codex 连续 9 轮 ping-pong review 累计修复(每轮主修 → Codex 验 → 再修 → 验 …直到 Codex 给 "all clean")。

**CLI surface 一致性**:
- `wechat history` 加 `required_unless_present` 让必填语义清楚;`--since` / `--until` 接 ISO date / `YYYY-MM-DD HH:MM` / epoch 三种格式(之前只接 epoch int 直接 `invalid digit found in string`)。
- `wechat send "x" "   "` 全空白 recipient 立即 reject(之前 SQL LIKE %   % 匹配一堆空格昵称)。
- `wechat doctor` exit code 反映 status:`ok=0 / needs_*=1 / broken=2`。CI 脚本 `wechat doctor || exit 1` 真能用。
- `wechat doctor --json` 加顶层 `all_ok: bool` 给 CI 直接消费,不需要 jq 聚合 checks[]。
- `wechat contacts --filter` 现在是 `--query` 的 alias(老用户肌肉记忆兼容)。
- `wechat history` `--help` 描述加澄清「必填」语义。
- `wechat tunnel` / `wechat orchestrate` / `wechat clone install` 各自加 `long_about` 决策树 / 前置条件 / 装完用法。
- `wechat --help` long_about 加「关联二进制」段说明 `wechat-bridge` / `wechat-wechaty-gateway` 是独立 binary。

**JSON 输出契约**:
- `wechat send --json` 四态全部带顶层 `ok: bool`(success / dry-run / ambiguous / error early)。Sentinel 防 double-print。
- AmbiguousRecipientReport 加顶层 `ok:false`。
- README + SKILL.md 加完整四态契约表 + `jq` 例子。

**bridge / listen UX**:
- `wechat-bridge --help` 重写:列全部 9 路 endpoint + `--port` / `--shape` 详细描述 + `WECHAT_BRIDGE_BEARER` 鉴权说明。
- SSE `/messages/stream` 默认 `since=0` 一连 backfill 全历史(实测 1.3MB+);docs / SKILL.md / `--help` 全加 `?since=<epoch>` 警告。
- `wechat listen --on-message` handler stdout 路由 `/dev/null`(避免 handler `echo` 污染 JSONL event stream);stderr 仍 inherit 让错误透出。

**Daemon / 错误信息**:
- daemon spawn stderr 现在写 `~/.wx-rs/wechatd.log`(之前丢 `/dev/null` 导致 crash 无法排查);`doctor` 在 daemon ✗ 时引用 log 路径。
- AuthError::NetworkUnreachable 文案重写明说"这跟你的命令参数无关",给 `curl wechat-profile.misonote.com` / cache grace / proxy 三步排查;`post_auth_me` 加 1 次短退避(400ms)+ 5xx retry,4xx 不 retry。
- `wechat doctor` `key_file_present` 在 keys.json 已存在时不再误指 init;daemon ✗ 时显示 wechatd.log 路径。
- `wechat doctor` 渲染:hint 空字符串时不打孤零零的 `→`。
- `wechat init` 输出去 `--scan` 字样(`--scan` 是内部代号,用户视角无此 flag)。
- `wechat auth activate <无效码>` 错误信息倒置修正(把"码无效"放第一,"如果之前激活过查 status"第二)。
- `wechat send` `DeliveryVerifyTimeout` remediation 步骤化(打开 WeChat → 点文件传输助手 → 输入 hi → 按回车 → 重跑 send)。

**docs**:
- README §3 五步顺序对齐 install.sh,补「授权辅助功能」+ filehelper 说明。
- `docs/install.md` 加 §6 多账号 / `wechat clone` 章节 + §7 状态文件速查表(`~/.wx-rs/{keys.json, key.hex, config.json, auth.json, auth-cache.json, cursor.json, rva-cache.json, wechatd.log}` 每个文件用途 + 删除影响)。
- SKILL.md 历史残留命令清理(`sns-feed` / `--current-chat` / `--mode heap` / `--seed` / `--filter` / `--peek` 全部移除);加 `history --json` 字段稳定契约表;send 段重写跟 v1.13 对齐。
- `docs/capabilities.md` 加 `wechat-bridge` 完整 9 路路由表;`--on-message` env 变量表迁出 SKILL.md。
- examples bearer 自相矛盾修正(loopback 默认信任,bearer 留给 04 远程示例)。
- `wechat tunnel setup --hostname` 必填补全所有 docs / examples。

**install.sh**:
- bridge `/health` 二段重试(15s + 10s)消除 LaunchAgent 冷启动 race;首次 yellow 加新机解释。

## v1.13.19 — 2026-05-06

第八轮(主 agent 第七次自查)针对 HTTP bridge surface 的 5 修。前 7 轮全是 CLI 视角,bridge 这条 agent / Hermes / n8n 必经路径完全没扫过。

- `wechat-bridge --help` 重写:列出全部路由(GET /health /chats /unread /contacts /resolve /messages/stream /chat/{wxid} /chat/{wxid}/history;POST /send 加 `--shape hermes` 时的 /typing),`--port` / `--shape` 加详细描述,加 `WECHAT_BRIDGE_BEARER` 鉴权说明。之前两个 flag 都是空白,新用户 / agent 完全摸黑。
- `docs/capabilities.md` HTTP bridge 段补完整路由表(9 路 + method + 用途),"8 路"魔数 → 实际路由表;加 SSE `?since=<epoch>` 警告(默认 since=0 = 1.3MB+ 全历史 backfill,agent 接 LLM 直接被 token 淹)。
- `SKILL.md` HTTP bridge 段加同款 SSE 警告 + 默认 `SINCE=$(date +%s)` 例子;路由表加 `/chat/{wxid}` 和 hermes-only `/typing`。
- 实测细节:bridge 默认 bind 127.0.0.1 only(无 0.0.0.0 风险),BEARER 是 opt-in;但用户 / docs 视角下"localhost = 安全"的暗示需要明示。

## v1.13.18 — 2026-05-06

第七轮新角度回归 4 修(JSON / exit code / resolver edge cases):

- `wechat history --since "2026-04-01"` 现在接 ISO date / `YYYY-MM-DD HH:MM[:SS]` / epoch seconds 三种格式(之前只接 epoch int 报 `invalid digit found in string`,SKILL.md 旧 example 都直接撒谎)。`--until` 同样,且 bare date 自动延伸到 23:59:59 让一日窗口 `--since X --until X` 真覆盖那天。
- `wechat send "x" "   "` 全空白 recipient 立即 reject(之前 LIKE '%   %' 匹配一堆昵称含连续空格的联系人,出 ambiguous 候选列表,新用户 / agent 误传空白参数会得到一堆陌生 wxid)。
- `wechat doctor` exit code 反映 status:`ok` → 0 / `needs_init` / `needs_send_verify` → 1 / `broken` → 2。之前不论 ✓✗ 都 exit 0,CI 脚本 `wechat doctor || exit 1` 完全失效。
- README + SKILL.md 加 `--dry-run` 例子(flag 早就有,但只埋在 `wechat send --help` 里,文档 0 提)。

加: Codex round 6 跨 docs 反向 audit 发现的 6 修(SKILL.md 引用废命令 sns-feed/--current-chat/--mode/--seed/--filter/--peek;examples bearer 自相矛盾;tunnel --hostname 必填漏写;docs/install.md 漏 4.1.9 + 顺序错;clone 多账号缺 doc;listen --on-message env 变量表迁出 SKILL.md)。

## v1.13.17 — 2026-05-06

- **SKILL.md**: 删除 v1.13 移除的 `sns-feed` / `sns-search` / `sns-notifications` / `bootstrap` 命令引用 (agent 调会得到 `unrecognized subcommand`)。重写 send 用法段:`--current-chat` / `--mode heap` / `--seed` / `--auto-hide` 等不存在的 flag 全删,改成现行 `wechat send TEXT RECIPIENT` 写法。Capability matrix 加上 image / heap warmup,删 Moments 行。
- **examples/README.md + 01-echo-bot/bot.js**: gateway bearer 自相矛盾 —— README 让设 `WECHATY_GATEWAY_BEARER`,但 bot.js 不传 grpc metadata,照抄连不上。改为 loopback 默认信任,bearer 是公网暴露场景的可选项,见 04-cf-worker。
- **examples/04-cf-worker README + docs/install.md** : `wechat tunnel setup` 必填 `--hostname`(bare `<uuid>.cfargotunnel.com` 公网不路由的踩坑),旧 doc 给的裸命令直接 missing-arg。
- **docs/install.md** : 支持版本表加 4.1.9 + build 268575;Step 4 改成 5 步顺序对齐 install.sh / README §3(之前漏 TCC + 顺序反了)。
- **docs/install.md** : 新增 §6 多账号 / `wechat clone` 章节(命令存在但缺旅程文档,clone install / list / per-bundle init / per-bundle TCC 全说明)。
- **docs/capabilities.md** : `--on-message` env 变量表(`WECHAT_MSG_TEXT/SENDER_WXID/...`)从 SKILL.md 内迁出来,docs/capabilities.md 给完整字段表 + 用途说明,新用户从公开 docs 直接看得到。

无 binary 改动,install.sh 拉的还是 v1.13.17 tarball;只是 docs / SKILL.md / examples 跟 v1.13.17 实际行为对齐。

## v1.13.17 — 2026-05-06

第五轮新机视角(再次清空 ~/.wx-rs / Keychain / 二进制)发现的 6 修。

- `wechat doctor` 在新机(还没 init)时,`daemon_running` ✗ 行不再吐多行嵌套 hint(之前把 DaemonClient::connect 的整段长 error 字符串塞进 detail,渲染成杂乱多行,且包含老路径 `~/.wechat/keys.json`)。改成单行「未启动 (没找到 SQLCipher key — 跑 `wechat init`)」,key_file_present 已经独立报路径了。
- `wechat doctor` 的 `wechat_dylib_fingerprint` 在 4.1.9 dylib + 没 keys.json 时,hint 不再说「raw-key offset 尚未 live 验证」(4.1.9 走内存扫描根本不用 offset BP),改成「跑 `wechat init` 把 keys.json 抓出来,4.1.9 走内存扫描不是 offset BP」。新加 `DylibFingerprint.per_db_key_model` 区分两种 key 模型。
- `wechat image get <bad-id>` 错误信息不再优先吐 heap miss 提示("先在 WeChat 里点开图")—— 当根因是 `message not found`(用户传错 ID),直接说「检查 message id 是否正确」+ 引导用 `wechat history <chat>` 找 local_id。
- `wechat image get --help` 给 `<MESSAGE_ID>` / `--chat` / `--out` 都加了中文描述(之前都是空白)。
- `wechat doctor` 渲染:hint 是空字符串时不再打孤零零的 `→ ` 尾(之前 P5-1 修法触发了渲染 bug)。

## v1.13.16 — 2026-05-06

第四轮新机视角(完全清空 ~/.wx-rs / Keychain / 二进制后从 install.sh 一条龙)发现的 7 修。

- `wechat doctor` 的 `daemon_running` 不再自相矛盾。之前:doctor 自己拉起了 daemon,然后 `daemon_running ✗ socket 不存在` —— 是 stat 没等 socket ready。现在 probe_daemon 自动 spawn 后再 check,新机首跑直接全绿。
- `wechat doctor` 的 `key_file_present` 在 4.1.9 用户没 init 时,显示「期望 keys.json 或 key.hex」(之前只显示 key.hex,4.1.9 用户看到 false-negative 路径困惑),hint 改单一 `wechat init`(去掉「4.1.9 用户跑 `wechat init --scan`」—— 用户视角根本没有 `--scan` 这个 flag)。
- `wechat init` 输出 `[init] 完成` 不再说 `[init --scan] 完成`(`--scan` 是内部代号,用户视角无此 flag,看到会困惑)。
- `wechat auth activate <无效码>` 错误信息从「这个激活码已经用过 / 不存在了」改为「激活码无效:可能输错了 / 不存在 / 已经用过」,把「检查粘贴格式」放第一条而不是「你可能已经成功了」误导。
- `wechat send` `DeliveryVerifyTimeout` remediation 从一句话改成 1-5 步骤化(「打开 WeChat → 点文件传输助手 → 输入 hi → 按回车 → 重跑 send」),并明说「辅助功能授权已 OK,不是 TCC 问题」帮新用户排除疑虑。
- `install.sh` 首次安装 bridge `/health` yellow 加解释:「如果你是首次安装这一行通常正常 —— 你下面还没授权辅助功能,bridge crash-restart 中,完成 step 2 后自动起来」。新用户不再以为装坏了。

## v1.13.15 — 2026-05-06

第三轮新用户视角回归 7 修。

- `wechat doctor` 的 `send_delivery_verified` hint 之前误导用户去重跑 `wechat init`(init 修不了 send 自检),现在改为 `跑 wechat send hi filehelper;首次失败先去 WeChat 给文件传输助手手动发一条 warmup`。
- `wechat send` 在 DeliveryVerifyTimeout 时错误信息加 InputView warmup 引导(WeChat 输入框 Qt slot_send signal chain warmup 是首次 send 的常见绊脚石)。
- `wechat members` / `wechat stats` / `wechat export` 找不到联系人/群时,从 `chat not found: X` 改成 friendly error + `wechat contacts --query X` 引导,跟 history / search 一致。
- `wechat export` 描述去掉 "JSONL"(实际只支持 markdown / json,文档撒谎了)。
- `wechat listen --wxid 张三` 找不到联系人立即报错 + 候选,不再 silent 永远不响应。
- `wechat listen --help` 子选项加描述(--wxid / --format / --on-message 之前都是空白)。
- `wechat contacts --brief` 加单行输出模式,跟 sessions --brief 一致(默认 50 条 yaml ≈ 300 行滚屏体验改善)。

## v1.13.14 — 2026-05-06

第二轮新用户视角回归发现的 6 个坑,一次清完。

- **README §3 重写** —— 新用户第一次照 README 跑会得到「init 成功 + send 静默失败」(因为 README 之前漏了「授权辅助功能」这步,且顺序跟 install.sh 不一致)。改成 5 步,跟 install.sh 末尾输出对齐;明确 filehelper 是什么。
- `wechat history "张三"` 找不到联系人时不再 silent 返回空。错误信息改成 `no chat matches "张三". Try wechat contacts --query 张三` —— 跟 send 同款 friendly resolver。多个候选时会列出来。
- `wechat search "会议" --in "项目讨论组"` 找不到群时同样的 friendly error + 候选列表。
- `wechat sessions --brief` 单行 / 会话输出,带未读数。新用户跑 `sessions` 一下滚屏 20×12 行的体验改善。
- `wechat auth --help` 子命令现在有中文描述(activate / status / renew 之前都是空)。
- `wechat auth status` 第一行直接是「剩余 X 天 · 状态」,加 ⚠️ / ⏳ 紧急标记;之前要扫到第二行才看到剩余天数。

## v1.13.13 — 2026-05-06

新用户体验回归 + 命令一致性。

- `wechat history` 现在同时接受 `--chat <CHAT>` flag（之前只支持位置参数，跟 `image get --chat` 不一致，新人常被卡）。位置参数继续工作。
- `wechat unread` 加 `-n / --limit` 选项（之前直接报 `unexpected argument '--limit'`，跟 sessions / contacts 不一致）。
- `wechat image` 帮助文案从「CDN-only」更新为「默认走 heap scan，未命中再 fallback CDN」，跟 v1.13.11/12 实际行为对齐。
- `wechat image get` 在 auto 模式下 heap miss + CDN 也失败时，错误信息改为可操作的 hint：「先在 WeChat 里点开这张图让 plaintext 进 heap，然后重试」。之前裸吐 `cdn_capture_timeout` 没有引导。
- `wechat doctor` 状态拆分：key 已抓但只剩 send 自检未跑时返回 `needs_send_verify`（黄）而不是 `needs_init`，避免新人重跑 init 抓 key。
- `wechat stats` 描述改为「某个会话的消息统计」，明确 `<CHAT>` 必填（之前误导成全库统计）。
- `install.sh` bridge `/health` 检查加二段重试（15s + 10s），消除 LaunchAgent 冷启动 race 误报「bridge 没起来」。

## v1.13.11 / v1.13.12 — 2026-05-05

收图能力上线。`wechat image get <messageId> --chat <id>` 默认走 daemon 内的 heap 扫描（mach_vm syscall 直读 WeChat heap，5–7 s 拉 540 MB），未命中再 fallback CDN replay。

- 触发条件：图先在 WeChat UI 里点开过一次（plaintext 才会进 heap）。
- 比 v1.13.10 lldb 路径快 ~40×（lldb debugserver mach RPC 单调 50–200ms × 600 次 = 几分钟）。
- v1.13.12 加了 `.dat` body size 候选 + `WECHAT_HEAP_SCAN_DEBUG=1` 诊断模式。
- agent 用法见 [SKILL.md](../SKILL.md) 的 image 段。

## v1.13.7 / v1.13.8 / v1.13.9 — 2026-05-04/05

WeChat 4.1.9 per-DB SQLCipher key 适配 + display_name 解析。

- 4.1.9 把单 master key（`~/.wx-rs/key.hex`）拆成 per-DB key（`~/.wx-rs/keys.json`，每个 .db 一把）。v1.13.7 修复 6 个原本 silent fail 的查询命令：`image get/inspect`、`export`、`stats`、`members`、`favorites`、`new-messages`。
- v1.13.8/9 给 `sessions` / `unread` / `contacts` / `history` 全部加上 `display_name`，把 `xxxx@chatroom` 自动映射成群名（28/30 命中）。
- history 同时附带 `chat_display_name`，agent 不需再二次查群名。
- 加 7 条 e2e smoke 测试（`tests/cli_smoke.rs`），盯防同类升级 silent fail 再发生。

---

## v1.12.0 — 2026-04-28

### 🆕 `wechat orchestrate` — SaaS outbox/webhook 接入（NAT-friendly）

让你云上的 SaaS 后端（客服系统 / 订单系统 / 自动化平台）驱动本机微信。**不需要公网 IP / 不需要域名**，Mac 全 outbound 流量 —— 家用宽带 / 公司内网 / GFW 后面都能跑。

```bash
wechat orchestrate setup \
  --outbox-url=https://api.your-saas.com/api/wechat-outbox \
  --webhook-url=https://api.your-saas.com/api/wechat-inbound \
  --bearer=<saas-token> \
  --webhook-secret=<saas-hmac-secret>
```

- 长进程：poll SaaS outbox 拉 send 任务 → 调本机 send → 回报 done/fail；订 SSE 入站 → POST SaaS webhook
- 标准 4 endpoint 协议：`claim` / `done` / `fail` / `inbound`，SaaS 端实现就接入
- 状态机 `pending → claimed (lease=60s) → done/fail`，lease 过期自动 reset
- 幂等键 + HMAC-SHA256 webhook 签名 + 5min replay 窗口
- 持久化 ack：done/fail 落盘 fsync 后才算完成，进程崩了 replay
- bridge_unavailable 触发 worker-level pause（30s → 5min）
- hard config error 触发 launchd bootout self 防死循环

完整协议规范：[docs/v1.12-orchestrate-protocol.md](v1.12-orchestrate-protocol.md)（4 endpoint shape + 状态机 + 错误码 taxonomy + 安全模型）

跟 v1.11.1 tunnel 共存：

| 场景 | 用什么 |
|---|---|
| 真业务长流（持续客户对话 + 异步 send 队列 + inbound dispatch） | **v1.12 orchestrate** ⭐ |
| 偶尔触发的脚本 / CF Worker 收 webhook 立刻发条微信 | v1.11.1 tunnel |
| 同时要两种 | 都装，互不冲突 |

工程：4 轮 codex review，1 critical + 17 major 全闭环（ack durability / SSRF / per-row timeout / backoff array / supervisor / bridge pause / 0600 atomic / launchd loop break / etc.）。66 个 orchestrate-specific test pass（含 6 个 axum mock-server integration）。

---

## v1.11.1 — 2026-04-28

远程 wechaty gateway via Cloudflare Tunnel + ES256 JWT。`wechat tunnel setup --hostname=...` 在用户自己 CF 账号下创建 named tunnel，把本机 REST 桥（:18402）暴露公网。远程客户端 fetch + 1h JWT 同步直连。

详细：[docs/remote-gateway.md](remote-gateway.md)

修了 v1.11.0 实测部署的两个架构问题：bare `<uuid>.cfargotunnel.com` 公网不路由、SSRF allowlist 过严。新增 health probe + 强制 hostname routing。

---

## v1.10.32 — 2026-04-26

代码 review 复盘修补 + Wechaty gateway 重新启用：

### 🆕 Wechaty Puppet gRPC gateway — 真客户端 e2e 通过

`wechat-wechaty-gateway` bin（127.0.0.1:18401，Bearer token 鉴权）从 v1.7
之后第一次重新可编译可服务。**已用真 npm `wechaty@1.20.2` + `wechaty-puppet-service@1.19.9`
端到端验证**：start 握手 / Login 事件（带真账号）/ Event 流持续推真消息（text/image/video/
miniprogram/attachment 全 type 正确），不再只是单元测试。

意义：wechaty 生态（TypeScript / Python / Go SDK）能直接把本仓当 puppet provider，
不再被锁在 wechat-bridge 的 hermes HTTP/SSE 一种 shape。

- **🔒 订阅 gate**：每一个数据 RPC（contact / message / room / event / ...）都必须通过订阅校验才能返回数据。bearer 单独不解锁数据 —— bearer 只是 transport auth，wxp_act_ 才是 entitlement。`Ding` 是唯一 ungated 的（pure 心跳）。`NotActivated` → `Unauthenticated: missing activation`；`Expired` → `PermissionDenied`；客户端在 `start()` 就能拿到清晰错误
- 全量适配上游 `Puppet` 服务最新 schema (pinned SHA `f1ecd6c`，2026-04-25)
- 78 个 RPC 方法（Version / Ding / Start / ContactList / MessageSendText / Event 等）实现
- `MessagePayloadResponse` 完整填充：`MessageType` enum 映射、`talker_id`/`room_id`/`listener_id`/
  `mention_ids`/`receive_time`，wechaty `message` 事件直接消费
- `Login` event 自动在 Event 订阅时发出，带真 self_wxid（daemon ping 现在返回 wxid）
- 30 个 read-only getter（`ContactPayload`/`ContactAvatar`/`RoomMemberList` 等）改返 empty success
  而非 `Unimplemented`，避免 wechaty puppet 在 cache 拉满时 bail
- daemon client 加连接池（Mutex<DaemonClient>），消除高频 RPC 时套接字 stampede
- 加 build.rs 用 `protoc-bin-vendored` 编 vendored proto，系统不需装 protoc
- `Download` / `Upload` streaming RPC 暂返 `Unimplemented`（v1.12 真做文件流）

启动：
```bash
WECHATY_GATEWAY_BEARER=your-secret wechat-wechaty-gateway
# 默认 127.0.0.1:18401
```

Node 客户端：
```js
import { WechatyBuilder } from 'wechaty'
import { PuppetService } from 'wechaty-puppet-service'
const puppet = new PuppetService({
  token: 'puppet_workpro_test',
  endpoint: '127.0.0.1:18401',
  tls: { disable: true },
})
const wechaty = WechatyBuilder.build({ puppet })
wechaty.on('login', (u) => console.log('logged in as', u.id))
wechaty.on('message', (m) => console.log(m.type(), m.talker()?.id, m.text()))
await wechaty.start()
```

### 🐛 Review 复盘修补（无新功能，专门解 v1.10.31 review 找到的几个根因）：

- **`install.sh` codesign 块在 `set -euo pipefail` 下结构性死锁**：旧代码 `EXISTING_IDENT=$(codesign -dv ...)` 在新装机器（无签名）会让 `codesign` 返回非零、`set -e` 直接 abort installer；`codesign --force ... ; CS_RC=$?` 也是 `set -e` 在 codesign 失败时直接退出，永远走不到 warn 分支。改成 `if cmd; then …; else …; fi` 显式控制流，并加自测验证两条路径
- **bridge env-bool 拼错触发 KeepAlive 死循环**：`WECHAT_BRIDGE_GROUP_MENTION_ONLY=ye`（漏字母）以前会让 bridge `bail!` → exit → launchd 立即重生 → 无限循环烧 CPU。现在改成 warn + 用默认值，bridge 仍正常启
- **bridge AX preflight 失败时 launchd 立即重生**：每秒一轮 `lldb attach + dyld load` 烧爆。preflight 失败前现在 `sleep 30` 节流
- **SSE 行 `is_mentioned` 偶发 false negative**：daemon 三处 SELECT 各自重写一份 `sender_wxid.is_empty()` 判定，把"DM 自发"和"群消息 prefix 解码失败"两种语义压成一种 → 群 @ 静默丢。抽 `assemble_extras` 单一入口，`is_none()` 区分两态，遇到第二种 log 警告
- **`widget+0x2B8` SSO/long 形态判别**：旧 heuristic `0x100000000 <= ptr < 0x800000000` 在 ARM64 ASLR 下不可靠（user heap 经常超 32GB），猜错 → 把堆指针字段当 SSO 内联覆盖 → libc++ 析构 free 野指针 → WeChat 进程级崩。换成 libc++ 标准的 `bytes[23] & 0x80` 判别位，VM 上限放宽到 47-bit
- **公开仓 SKILL/README/CHANGELOG 落后 4 个 release**：补上 `isMentioned`、schema URL → v1.10.28、客户清单改为"看 isMentioned 就够"

> v1.10.32 = "review 找出的隐患都修干净再 ship"。客户没新行为差异，但抗操作风险一档上升

## v1.10.28–31 — 2026-04-25/26

群 @ 机器人不响应根治 + TCC 升级体验改进：

- **`isMentioned` 字段直接判**：daemon 解 atuserlist + 比对自己 wxid，bridge 输出布尔。客户群机器人不用再自己拼 `mentionedIds.includes(myWxid)`
- **`WECHAT_BRIDGE_GROUP_MENTION_ONLY=1`**：bridge 出口 filter，群里非 @ 的消息直接丢，agent 端 0 改造
- **`packed local_type` mask 修**：v1.10.27 漏 mask 0xFFFF，导致部分群消息分类落到 unknown
- **bridge 启动 + filter 全程 structured logging**：`[bridge:startup]` 一行 dump effective config，`[bridge:filter] drop/pass` 每条决策点；客户截 5 行 log 就能定位
- **BP install timeout 10s → 30s**：v1.10.30 install.sh 加 `codesign --force` 之后 macOS 重校验签名 + dyld 缓存 8-12s，旧 10s 卡 borderline
- **`install.sh` 自动 codesign + idempotent + orphan kill**：每次升级保留 TCC 授权（不重签同 identifier），杀掉残留 wechat-bridge 进程让 LaunchAgent 真正接管，`bootout + bootstrap` 强 reload plist env（kickstart 不重读 EnvironmentVariables）
- **`wechat doctor --fix-tcc`**：交互式 TCC 修复——开 System Settings + Finder 选中 wechat-bridge，3 次重试后自动 `--check-trust` 验证
- **三级硬 release gate**：`scripts/publish-release.sh` 走 draft → 模拟 install → SHA256SUMS 双重校验 → publish

## v1.10.27 — 2026-04-25

SSE payload 对齐 Wechaty `MessageType` 枚举。bridge 给非 CLI-based agent 平台（Hermes / n8n / Dify / LangChain）一个可直接消费的富消息流。

- **新 `messageKind` 字段**：16 个 Wechaty enum 值（`text` / `image` / `audio` / `video` / `url` / `mini_program` / `recalled` / `transfer` / `red_envelope` / `system` / …）。以前 consumer 要自己从 `mediaType` 字符串 + 原始 XML 猜消息类型，现在 daemon 分类好直接给
- **5 个结构化嵌套对象**（按 `messageKind` 出现）：
  - `urlLink` — `{title, description, url, thumbUrl}` (type=5 appmsg)
  - `miniProgram` — `{title, description, appId, username, pagePath, thumbUrl}` (type=33/36 appmsg)
  - `refer` — `{svrId, fromUser, chatUser, displayName, content}`（引用回复，type=57 appmsg）
  - `recall` — `{replacedMsgId, text}`（撤回 sysmsg）
  - `media` — `{aesKey, md5, cdnUrl, cdnThumbUrl, length, durationSeconds, localPath}`（image/voice/video/file 的 CDN + 校验信息）
- `body` 对 url / quote / mini_program 类消息改成 title（人读文本），原来是原始 `<appmsg>` XML
- 新 schema 固化在 `wx/schema/sse-payload-v1.10.27.schema.json` + 契约单测防字段 drift
- MiniProgram 消息的 body bug 修（以前泄漏原始 XML）
- 向后兼容：所有 v1.10.25 以来字段保留不变，仅新增

## v1.10.25–26 — 2026-04-24/25

**两个大 bug 根治**，影响所有 v1.10.24 之前的用户：

- **`wechat send --wxid X` 被路由到 UI 聚焦的聊天**（`send` 能返回 `sent:true` 但实际发错人）
  - 根因：WeChat 4.x `widget+0x2B8` 是 libc++ `std::string`，有 SSO（内联）+ long（堆指针）双形态；之前的 hijack 只覆盖一种
  - v1.10.23/24：双形态都支持
  - v1.10.22 作 belt-and-suspenders：`send` 完事后根据消息落表的 `Msg_md5(wxid)` 校验是否路由正确，错误就 `reason: delivery_misrouted`
- **DM self-echo loop**：bot 发出去的 DM 在 SSE 里又作 inbound 传回，导致 agent 回自己的消息无限循环
  - v1.10.25：`HermesMessage` 新增 `fromSelf: bool`。bridge 记录每次 `/send` 刚产生的行，SSE emit 时 mark；客户看 `fromSelf === true` 直接 drop
- **群里 @ bot 永远不触发响应**：bridge 之前 `mentionedIds` 硬编码空数组
  - v1.10.25：daemon 读 `Msg_xxx.source` BLOB（zstd 压缩的 msgsource XML），解 `<atuserlist>` 塞到 SSE payload

另外：

- v1.10.26：消息类型分类器（image/voice/video/url/quote/miniprogram/recall），填 `hasMedia` / `mediaType` / `mediaUrls` / `quotedParticipant`
- `wechat-inspect-msg` RE 工具：dump 单行全列 JSON，方便以后 WeChat 升级 schema 时快速抓新字段

## v1.10.0 — 2026-04-23

**面向 agent / bot 平台的大版本**：新出独立二进制 `wechat-bridge`，把 wechatd 的 RPC 包成稳定的本地 HTTP + SSE，Hermes / n8n / Dify / LangChain 可以像接 WhatsApp bridge 一样接 WeChat。

- 8 个 HTTP 路由（`/health` / `/chats` / `/unread` / `/contacts` / `/chat/:wxid/history` / `/resolve` / `/send` / `/messages/stream`）
- `/send` 返回标准化四态：`delivered` / `submitted_unconfirmed` / `status_unknown` / `failed` + 诊断块
- 默认 127.0.0.1-only；`WECHAT_BRIDGE_BEARER` 环境变量可启 Bearer auth（走隧道时用）
- **激活码 gating 100% 保留**：bridge 只转发，发消息仍然过 daemon 的 AEAD + 服务端 expires_at 校验
- 纯手写 HTTP/1.1（无新依赖），二进制 2.7MB

## v1.9.17–1.9.20 — 2026-04-23

- **issue #2 根治**：send 冷启动 InputView 未构造 → 消息静默丢
  - v1.9.17：`wechat doctor` 加 `send_readiness` 三态检查；`wechat init` 完成后打印 warm-up 指引
  - v1.9.18：cache-hit init 路径也打印指引（之前只在完整 calibrate 分支 print）
- **history / search 跨分片 DB 合并**（v1.9.19）：老用户的聊天记录跨多个 MSG_*.db 时不再只取第一个表，完整历史都能拉出来
- **Bot UX 提升**（v1.9.20）：
  - trial 从 15d 扩到 30d
  - admin 审批按钮多 `1月 / 3月 / 1年 / 🌟永久`（lifetime 给亲朋好友 / AI 星球特批）
  - 审批后可点 `✏️ 加备注`，写 "朋友老王 / AI 星球 Leo 邀请" 存 `reviewer_note` 列

## v1.9.16 — 2026-04-22

- send 失败时 CLI 自动在输出末尾打印可复制诊断块（CLI/daemon 版本、完整 dylib SHA、WeChat build、扫表数、候选行数、last_error、baseline_ts）—— 用户整段贴回，维护者无需再问 shasum / plutil
- Telegram bot 加订阅门槛：申请激活码前必须订阅官方频道（`getChatMember` fail-closed）

## v1.9.1 — 2026-04-22

**用户能感受到的变化**：

- 🚀 发消息快了 **3-4 倍**：热路径从 ~2.5s 缩到 ~700ms
- 🔒 token 现在自动存进 macOS Keychain，不再裸文件
- ✅ 修了一个常见的"我自己手动给别人发消息却被路由到上一次 CLI 目标"的 bug
- 📜 v1.9.1 起需要激活码才能用 `wechat send`：跟 [@WechatCliBot](https://t.me/WechatCliBot) 申请，免费内测
- 🤖 全套中文引导（`wechat -h` / `wechat doctor` / `wechat init`）

新命令：
- `wechat auth activate <code>` —— 激活订阅
- `wechat auth status` —— 查 tier + 剩余天数
- `wechat auth renew` —— 看续费方式

## v1.8.x 系列 — 2026-04 init 自动化

- v1.8.13–18：init 自动检测 + 修 macOS 系统前置（DevToolsSecurity + WeChat get-task-allow），失败时 inline 输出完整诊断方便贴给维护者
- v1.8.10：真零闪屏发送（CGEventPostToPid + LLDB hijack BP）
- v1.8.11：支持 WeChat build 37342

## v1.7.x — 全 Rust 重写

- v1.7.0：Python 栈整体重写为 Rust，比 v1.1.3 快 ~385×
- v1.7.2：dylib SHA-256 指纹校验，Tencent 热更立即标红
- v1.7.5：daemon lazy-start，任意 query 自动起 wechatd

## v1.3.x — 实时收消息

- `wechat listen` 实时新消息流
- `--on-message` shell handler 触发，env 传 payload

## v1.2.x — daemon 骨架 + 朋友圈

- `wechatd` 守护进程（持久 SQLCipher 池）
- 朋友圈通知 / 时间线 / 搜索

## v1.1.x — 查询能力

- 联系人 / 会话 / 历史 / 搜索 / 未读 / 群成员 / 收藏 / 统计 / 导出
- one-liner `wechat send TEXT RECIPIENT`
- `wechat doctor` 自检

## v1.0 — 初版

- `wechat init` 抽 SQLCipher key
- `wechat send` 后台发文本（不抢焦点）
