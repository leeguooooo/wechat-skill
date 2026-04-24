# 完整能力矩阵

| 能力 | 状态 | 命令 | 说明 |
|------|------|------|------|
| 提取 SQLCipher key | ✅ v1.1 | `wechat init` | 一次性；WeChat 重启后重跑 |
| 抗 Tencent 热更（auto-calibrate） | ✅ v1.8.13 | `wechat init` 默认 | 字符串 xref 自动定位新 dylib 的 SQLCipher init |
| 后台发文本（零闪屏） | ✅ v1.0 / v1.8.10 真零闪 | `wechat send TEXT RECIPIENT` | CGEvent + LLDB hijack |
| daemon-backed send（~700ms 热路径） | ✅ v1.9.0 | 默认走 daemon | 持久 LLDB 会话；CLI 只 RPC |
| 不劫持用户手动发消息 | ✅ v1.9.1 | 默认 | 一次性 sentinel + 800ms 过期 |
| recipient 模糊解析（昵称 / 备注 / wxid） | ✅ v1.1.5 | 默认 | 多匹配返回候选清单 |
| 群发到群聊 | ✅ v1.1 | `wechat send "..." "群名"` | |
| `wechat doctor` 自检 | ✅ v1.1.3 | `wechat doctor` | lldb / 签名 / dylib 指纹 / daemon 一行看完 |
| Telegram 激活码订阅模型 | ✅ v1.9.1 | `wechat auth activate/status/renew` | trial 30d，machine_id 一次 |
| Telegram 频道订阅门槛 | ✅ v1.9.16 | 自动（bot 侧） | 申请前必须订阅官方频道，否则 /request / 按钮一律被拦 |
| 审批时加备注 | ✅ v1.9.20 | admin 点 ✏️ 加备注 | `reviewer_note` 列，亲朋好友 / 邀请来源长期可查 |
| 永久 tier（亲朋好友特批） | ✅ v1.9.20 | admin 面板 🌟 按钮 | `lifetime` tier，DM 显示 "永久有效" |
| token 进 macOS Keychain | ✅ v1.9.1 | 自动 | service `wechat-skill-profile-api` |
| AEAD 加密 profile API | ✅ v1.9.1 | 自动 | XChaCha20-Poly1305 + HKDF(token) + 6h TTL |
| send 冷启动预警 | ✅ v1.9.17 | `wechat doctor` + `wechat init` | doctor 三态 + init 完成打印 warm-up 指引 |
| send 失败自动诊断块 | ✅ v1.9.16 | `wechat send` | 失败时打印可复制诊断块，一行贴回就能定位问题 |
| history / search 跨分片 DB 合并 | ✅ v1.9.19 | `wechat history`、`search` | 多个 MSG_*.db shard 自动合并 + create_time 排序 |
| **本地 HTTP bridge（agent 集成）** | ✅ v1.10.0 | `wechat-bridge` | 127.0.0.1:18400；8 路 HTTP + SSE；可选 `WECHAT_BRIDGE_BEARER` |
| 权威 @-mention 列表（群） | ✅ v1.10.25 | SSE `mentionedIds` | 从 WeChat msgsource `<atuserlist>` 解；之前是空数组 |
| Self-echo 防护 | ✅ v1.10.25 | SSE `fromSelf:bool` | bridge 记录自己 /send 过的行；客户 `fromSelf===true` 直接 drop，避免 agent 回自己 |
| 消息类型分类（Wechaty 对齐） | ✅ v1.10.26 | SSE `messageKind` | 16 enum 值，text/image/audio/video/url/mini_program/recalled/… |
| 结构化 URL 卡片 | ✅ v1.10.27 | SSE `urlLink` | `{title, description, url, thumbUrl}` |
| 结构化小程序 | ✅ v1.10.27 | SSE `miniProgram` | `{title, description, appId, username, pagePath, thumbUrl}` |
| 结构化引用回复 | ✅ v1.10.27 | SSE `refer` | `{svrId, fromUser, chatUser, displayName, content}` |
| 结构化撤回 | ✅ v1.10.27 | SSE `recall` | `{replacedMsgId, text}` |
| 结构化媒体元数据 | ✅ v1.10.27 | SSE `media` | `{aesKey, md5, cdnUrl, cdnThumbUrl, length, durationSeconds, localPath}` |
| SSE payload JSON schema 契约 | ✅ v1.10.26/27 | `wx/schema/sse-payload-v1.10.27.schema.json` | draft-07，additionalProperties:false，daemon 构建期跑契约单测 |
| 列最近会话 | ✅ v1.1 | `wechat sessions` | |
| 联系人列表 / 搜索 | ✅ v1.1 | `wechat contacts [--query]` | 昵称 / 备注 / wxid 模糊 |
| 查聊天记录 | ✅ v1.1 | `wechat history <chat> [-n] [--since/--until]` | |
| 全库消息搜索 | ✅ v1.1 | `wechat search <keyword> [--in <chat>]` | |
| 有未读的会话 | ✅ v1.2 | `wechat unread` | private/group/official 过滤 |
| 群成员 | ✅ v1.2 | `wechat members <group>` | |
| 收藏 | ✅ v1.2 | `wechat favorites` | text/image/article/card/video |
| 统计 | ✅ v1.2 | `wechat stats <chat>` | 活跃度 / 发言人 / 时段 |
| 导出（Markdown / JSON） | ✅ v1.2 | `wechat export <chat>` | |
| 朋友圈通知 | ✅ v1.3 | `wechat sns-notifications` | |
| 朋友圈时间线 | ✅ v1.3 | `wechat sns-feed` | 本地缓存过的帖子 |
| 朋友圈搜索 | ✅ v1.3 | `wechat sns-search <keyword>` | |
| 实时收消息 | ✅ v1.3 | `wechat listen` | 新消息 <500ms push |
| AI 回调触发 | ✅ v1.3 | `wechat listen --on-message ...` | env 变量传 payload，免 shell 注入 |
| 后台 daemon | ✅ v1.2 / v1.7.5 自动 | `wechat daemon start` (可选) | 持久 SQLCipher 池；查询 <30ms |
| 全 Rust 二进制 | ✅ v1.5+ | `wechat` + `wechatd` | 比旧 Python 快 ~385× |
| dylib SHA-256 指纹校验 | ✅ v1.7.2 | `wechat doctor` | 漂移立即标红 |
| 发图片 / 文件 | ⏳ roadmap | — | 需要 RE slot_send 的 media 分支 |
| 群发 / 定时 | ❌ 不做 | — | 反滥用；LICENSE 禁止 |
| Linux / Windows / Intel Mac | ❌ | — | macOS arm64 only |
| 不在已验证 build 表里的 WeChat | ⚠️ profile API 推送中 | — | 通过 server-side profile，无需重发 release |

图例：✅ 生产可用 · ⏳ 开发中 · ❌ 不做 · ⚠️ 需配置

## 不打算做的

- **群发 / 自动加好友 / 反向爬别人朋友圈**：这是协议侧滥用，LICENSE 禁止
- **Linux / Windows / Intel Mac**：精力有限，且 LLDB 流程是 macOS arm64 强相关
- **公开 reverse-engineering 资料**：profile（offsets / RVA）不公开，靠订阅 API 分发

## 输出格式

所有查询命令默认输出 **YAML**（agent / 人都友好，省 token）。加 `--json` 切换 JSON：

```bash
wechat sessions --json | jq '.[] | select(.chat_type=="private")'
```

## 接 agent 平台（Hermes / n8n / Dify / LangChain）

两种方式都稳定、都走同一套激活码 gating，任选：

### CLI-subprocess 模式（zero setup）

```bash
# 入站流
wechat listen --format json | your-adapter.py

# 出站
wechat send --text "$BODY" --wxid "$TARGET" --json
```

### HTTP bridge 模式（v1.10.0+，适合 Hermes 这类 HTTP-native adapter）

```bash
wechat-bridge &          # 默认 127.0.0.1:18400
curl http://127.0.0.1:18400/health
curl -X POST http://127.0.0.1:18400/send \
  -H 'Content-Type: application/json' \
  -d '{"wxid":"filehelper","text":"hello"}'
curl -N http://127.0.0.1:18400/messages/stream
```

路由列表见 [SKILL.md](../SKILL.md#http-bridge-for-agent-integration-v110)。`/send` 返回 `{status: delivered / submitted_unconfirmed / status_unknown / failed, diagnostic, ...}`，正好对得上 Hermes / WhatsApp bridge 那种 contract。

**激活码不会被绕**：bridge 只转发，wechatd 仍然做 AEAD + 服务端过期校验；未激活 / 已过期 → HTTP 401 / 402。
