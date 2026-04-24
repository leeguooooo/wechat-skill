# 更新日志

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
