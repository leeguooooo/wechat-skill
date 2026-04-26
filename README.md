# wechat-skill

macOS 微信本地命令行：发消息、查聊天记录、收新消息流。给 Claude / Codex / Cursor 等 agent 用尤其顺手。

---

## ⚠️ 使用前必读（免责声明）

- 本工具基于 macOS 公开调试接口（LLDB）实现，**仅用于用户本人设备上的个人自动化**。
- **不得**用于任何商业场景、群发营销、刷单拉新、爬取他人数据、监控他人账号等滥用行为。
- 所有数据读取 / 解密均在**用户本人设备本地完成**，不向任何第三方传输聊天内容、联系人、二进制明文或解密密钥。仅向 profile API 发送当前 WeChat dylib 的 SHA-256 用于版本适配（不含任何账号信息）。
- 使用本工具即表示用户**了解并自行承担全部风险**，包括但不限于微信账号被限制 / 封禁的可能。
- 本工具**与腾讯公司无任何关联**，腾讯保留依据《微信软件许可及服务协议》采取相应措施的权利。

---

## 3 分钟跑通

### 1. 拿激活码（v1.9.1 起必需）

1. **先订阅官方频道**（必需前置条件）：<https://t.me/+4PuAO3lB9R82ZTVh>
   版本适配 / 热更新 / 安全公告只在这里发；未订阅的申请会被 bot 直接拦截，不进入审核队列。
2. 跟 [@WechatCliBot](https://t.me/WechatCliBot) 私聊 → 发 `/start`
3. 点「📝 申请激活码」按钮 → 按提示回一行用途说明，例如：
   > 个人调研对话存档，希望让 Claude 自动同步给我每日待办
4. 等管理员审核（通常 1-24h）
5. 通过后机器人会私信你 `wxp_act_xxxxxx`

> 💡 **为什么走审核制**：微信反自动化 + 账号风控一直在收紧，我必须控制分发、禁止滥用（群发营销、刷单、钓鱼、监控他人一律不批），所以每个激活码都要人工过。申请时把"你是谁 + 想做什么"写清楚通过会快很多。AI 星球成员申请时备注星球身份 / 邀请人，走快速通道。机构 / 商业场景请另外联系商谈授权（目前不开放批量发放）。

### 2. 装 CLI

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
```

确认 `~/.local/bin` 在 PATH 里：

- **fish**: `fish_add_path $HOME/.local/bin`
- **zsh / bash**: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`

### 2.5 必做：授权「辅助功能」

**首次用 `wechat send` 前必须做一次，不做会静默失败。**

macOS Sonoma 起，跨进程合成键盘事件的发送方必须在「辅助功能」清单里，否则系统直接把事件丢掉，无错误码无日志。`wechat-bridge` / `wechatd` 走这个 API，必须授权。

打开下面两条，一条弹设置窗口、一条进入文件位置方便拖进去：

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "$HOME/.local/bin"                    # Finder 打开，选中 wechat-bridge 拖进设置窗
```

然后：

1. 系统设置 → 隐私与安全 → **辅助功能**
2. 点 `+`，选 `$HOME/.local/bin/wechat-bridge`（Finder 窗口里那个），加进清单
3. 打开右侧开关
4. 有运行中的 bridge 就重启一次，让它继承新权限：
   - 用 LaunchAgent 的：`launchctl kickstart -k gui/$(id -u)/ai.wechat.bridge`
   - 手工启的：`pkill wechat-bridge; wechat-bridge &`

> `wechatd` 不用单独加，TCC 按 responsible-process 链继承 `wechat-bridge` 的授权。
> Input Monitoring / 输入监控 不参与 `wechat send` 路径，可以忽略。

装完跑一次 `wechat doctor` 确认：

```bash
wechat doctor --json | jq '.checks[] | select(.name=="ax_trusted")'
# → {"name":"ax_trusted","ok":true,"detail":"wechatd /Users/..../wechatd"}
```

### 3. 激活 + 初始化 + 发消息

```bash
wechat auth activate wxp_act_xxxxxx
# ↑ 弹 macOS Keychain 授权框，点「Always Allow」

wechat init
# ↑ 抽 SQLCipher key，会重启微信。第一次会要 1 次 sudo 密码
#   修系统前置（DevToolsSecurity + 给 WeChat 主可执行加 get-task-allow），
#   每步都打印"是什么/为什么/影响"，不偷跑

wechat send "Hello 🎉" filehelper
# ↑ 后台发，不抢焦点不闪屏。热路径 ~700ms
```

完成。

---

## 常用命令

```bash
# 发消息（recipient 可以是 wxid / 昵称 / 备注 / 群名）
wechat send "你好" 张三
wechat send "汇报" wxid_abc123
wechat send "周报" "项目讨论组"

# 看聊天
wechat sessions                       # 最近会话
wechat unread                         # 有未读的
wechat history "张三" -n 50           # 某人的最近 50 条
wechat search "会议" --in "项目讨论组"  # 全库搜或限范围

# 收消息流（agent 神器）
wechat listen --wxid filehelper
wechat listen --on-message ./reply.sh   # 每条消息触发，env 传 payload

# 订阅 / 自检
wechat auth status                    # 看 tier + 剩余天数
wechat auth renew                     # 到期后重新提交审核
wechat doctor                         # 任何时候出问题先跑这个
```

完整能力矩阵 → [docs/capabilities.md](./docs/capabilities.md)

---

## 给 AI agent / Hermes / OpenClaw / n8n / Dify / LangChain 用

两种接入方式，按你的场景选：

### A. Claude Code / Codex / Cursor 这类 CLI-agent

```bash
npx skills add leeguooooo/wechat-skill -y -g
```

agent 读 [SKILL.md](./SKILL.md) 自动学会全部命令。**先装 CLI 再装 skill**（顺序反了 agent 会以为命令不存在）。

### B. Hermes / OpenClaw / n8n / Dify / LangChain 这类 HTTP-native agent 平台（v1.10+）

> 💡 OpenClaw / Hermes 这类本地 AI 助手框架已经接了 WhatsApp / Telegram / Discord / Slack / Signal / iMessage，没内建 WeChat。用 `wechat-bridge` 就是他们接微信的标准入口——单机 HTTP、不上云、激活码走服务端权威校验。

独立二进制 `wechat-bridge`，本地 HTTP + SSE 网关：

```bash
wechat-bridge &                          # 默认 127.0.0.1:18400
wechat-bridge --shape hermes &           # Hermes WhatsApp-bridge 同 shape
```

8 个稳定路由：`/health` / `/send` / `/chats` / `/unread` / `/contacts` / `/chat/:wxid` / `/chat/:wxid/history` / `/resolve` / `/messages/stream`（SSE）。**激活码订阅不绕** —— 每次 `/send` 仍然走 daemon 的 AEAD + 服务端 `expires_at` 校验。

#### SSE payload（v1.10.28 对齐 Wechaty + isMentioned）

`/messages/stream` 每条 `event: messages` 是一组对象，字段固定在 [`wx/schema/sse-payload-v1.10.28.schema.json`](https://github.com/leeguooooo/wechat-skill/blob/main/wx/schema/sse-payload-v1.10.28.schema.json)（JSON Schema draft-07，`additionalProperties:false`）。关键字段：

- `messageKind`：Wechaty `MessageType` 枚举小写，如 `text` / `image` / `audio` / `video` / `url` / `mini_program` / `recalled` / `system` 共 16 值
- `mentionedIds`：群里权威 @-wxid 列表（v1.10.25 起来自 msgsource XML `<atuserlist>`）；**之前一直是空数组**
- `isMentioned`：v1.10.28+ bridge 已经做完"我自己被 @ 了吗"判定的 boolean。**群机器人只看这个字段就够，别再 client-side 拿 mentionedIds.includes(myWxid) 重做**（你的 wxid 可能是 remark / 主键映射，daemon 这边知道得最准）。配合 `WECHAT_BRIDGE_GROUP_MENTION_ONLY=1` 可以让 bridge 在出口直接把"群里非 @"的消息丢掉，agent 端连 filter 都省了
- `fromSelf`：bridge 刚 POST /send 过的行会是 true；**用来过 self-echo 最可靠**，比 `senderId === myWxid` 靠谱
- `urlLink` / `miniProgram` / `refer` / `recall` / `media`：按 `messageKind` 出现的结构化嵌套对象（title / url / appId / aesKey / cdnUrl / duration / …）
- `hasMedia` + `mediaUrls`：legacy 扁平接口，仍保留

向后兼容：v1.10.25 以来所有已发字段全部保留不变，仅新增。客户旧代码不改能直接跑。

详细 schema 见 [SKILL.md](./SKILL.md#http-bridge-for-agent-integration-v110) + [docs/capabilities.md](./docs/capabilities.md#接-agent-平台hermes--n8n--dify--langchain)。

---

## 出问题了？

1. **第一步**：`wechat doctor` —— 一行看完 lldb / WeChat 版本 / 签名 / key / daemon / dylib 指纹哪一项 ✗
2. **第二步**：vlaag 把 `wechat doctor` 整段输出 + 报错描述发给 [@WechatCliBot](https://t.me/WechatCliBot)
3. **init 失败时**：v1.8.13+ 起会在终端 inline dump 完整诊断（`================ 诊断信息 ================`），把那段贴过来

详细排错矩阵 → [docs/troubleshooting.md](./docs/troubleshooting.md)

---

## 这是什么 / 怎么实现的

- [docs/why-init.md](./docs/why-init.md) — `wechat init` 在干嘛（怎么从内存里抓 SQLCipher key）
- [docs/capabilities.md](./docs/capabilities.md) — 完整能力矩阵 + 不打算做的
- [docs/troubleshooting.md](./docs/troubleshooting.md) — Tencent 热更后 / 签名问题 / 0 hits 等常见排错
- [docs/CHANGELOG.md](./docs/CHANGELOG.md) — 完整版本历史
- [docs/ROADMAP.md](./docs/ROADMAP.md) — 路线图 / 不做的事

---

## 安全

- **只读 / 本地**：所有聊天内容、联系人、解密密钥的读取都在你自己机器上完成。出站流量只有一条：向 profile API POST 当前 WeChat dylib 的 SHA-256 拉对应 offsets 表。聊天内容 / 联系人 / key / wxid **永远不出本机**。
- **key 文件** `~/.wx-rs/key.hex` 是你微信账号所有本地数据的万能解密钥。chmod 600 自动设。**绝不要**提到 git / pastebin / 群聊。怀疑泄漏：微信里退出再重新登录 → 新账号目录 + 新 key，旧的作废。
- **激活码 token** 进 macOS Keychain（service `wechat-skill-profile-api`），不裸文件。
- **不改 WeChat.app 二进制 / 不签新 dylib** —— 仅 ad-hoc 给 WeChat 主可执行加 `get-task-allow` entitlement（LLDB 必需），Tencent 自动更新会覆盖，下次 init 自动再加。

---

## 平台支持

- macOS Apple Silicon
- WeChat 4.0.1.52 / 4.1.8 (build 36830 / 37335 / 37342) 已验证；Tencent 热更新版本 `wechat doctor` 会标注；新 build 通过 server-side profile 推送，**无需重新发 release**

---

## License

[非商业自研协议](./LICENSE) + [DISCLAIMER（中英）](./DISCLAIMER.md)。

仅个人学习 / 研究 / 个人自动化。商业使用需另谈授权（目前不开放）。
