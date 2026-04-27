# wechat-skill

把你自己 macOS 上的微信，变成给 AI agent / bot 用的**本地 API**。
不上云、不上 iPad 协议、不爬别人 —— 纯本地 LLDB + 进程内 hook，所有数据只在你这台 Mac 上动。

---

## 5 秒看明白

按吸引力排序，挑一个进：

| 你在用 | 装这个 | 做什么 |
|---|---|---|
| **Claude Code / Codex / Cursor** | [SKILL.md](./SKILL.md) | agent 自动学会发消息、查记录、收消息流 —— 让 Claude 帮你回微信 |
| **直接命令行** | `wechat send / sessions / listen` | 一行命令发消息 / 查记录 / 订阅消息流，shell 脚本和 cron 友好 |
| **任意 [wechaty](https://github.com/wechaty/wechaty) bot（TS / Python / Go）** | `wechat-wechaty-gateway`（gRPC :18401） | **首个真号 wechaty macOS 协议**。已写好的 wechaty bot 零改动跑在自己微信上，不再走 iPad / puppet-padlocal |
| Hermes / OpenClaw / n8n / Dify / LangChain | `wechat-bridge`（HTTP + SSE） | WeChat 变成跟 WhatsApp / Slack 同 shape 的本地接口 |
| 想要网页版微信 / 自定义前端 | fork [wechat-skill-web-demo](https://github.com/leeguooooo/wechat-skill-web-demo) | Svelte 5 + Tailwind 已接好 wechaty SDK，开箱即用 |

所有 surface 共享同一个 daemon + 同一个激活码，**装一次全开**。

---

## 装一下（5 分钟）

### 1. 拿激活码

跟 [@WechatCliBot](https://t.me/WechatCliBot) 私聊 → 发 `/start` → 点「📝 申请激活码」→ 写一行用途 → 通过后机器人发你 `wxp_act_xxxxxx`。
（前置：先订阅频道 <https://t.me/+4PuAO3lB9R82ZTVh>，不然 bot 拦截。审核 1-24h，[为什么走审核制](./docs/why-activation.md)）

### 2. 装 CLI

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
```

确认 `~/.local/bin` 在 `PATH` 里：
- fish：`fish_add_path $HOME/.local/bin`
- zsh / bash：`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`

### 3. 开辅助功能 + 激活 + 初始化

```bash
wechat init                                # 抽 SQLCipher key、修 entitlement、引导你开「辅助功能」开关
wechat auth activate wxp_act_xxxxxx        # 弹 Keychain 授权框，点 Always Allow
wechat send "Hello 🎉" filehelper          # 后台发，不抢焦点不闪屏
```

辅助功能授权细节（macOS Sonoma+ 强制）→ [docs/install.md#tcc](./docs/install.md#tcc)。

---

## 命令行用法

```bash
# 发消息（recipient 可以是 wxid / 昵称 / 备注 / 群名）
wechat send "你好" 张三
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
wechat doctor                         # 任何时候出问题先跑这个
```

完整能力矩阵 → [docs/capabilities.md](./docs/capabilities.md)。

---

## 接 AI agent

### A. Claude Code / Codex / Cursor（SKILL.md）

```bash
npx skills add leeguooooo/wechat-skill -y -g
```

agent 读 [SKILL.md](./SKILL.md) 自动学会全部命令 —— "帮我回一下张三的消息"、"把昨天群里讨论 X 的消息归档"、"等小李回我后告诉我"。**先装 CLI 再装 skill**，顺序反了 agent 会以为命令不存在。

### B. 任意 wechaty bot（v1.10.32+）

**首个真号 wechaty macOS 协议**。你已经写好的任意 wechaty bot（npm 上几百个 plugin、各种 LLM 接入示例）**不改一行代码**就能跑在自己的真号上，不再需要 puppet-wechat / puppet-padlocal / iPad 协议这些灰产路径。

```bash
wechat-wechaty-gateway &       # 起 gRPC 监听 127.0.0.1:18401
```

```ts
// 任意 wechaty 1.x 客户端，零改动接你本机微信
import { WechatyBuilder } from 'wechaty';
const bot = WechatyBuilder.build({
  puppet: 'wechaty-puppet-service',
  puppetOptions: {
    endpoint: '127.0.0.1:18401',
    token: 'puppet_workpro_local',
    tls: { disable: true },
  },
});
bot.on('message', m => m.text() === 'ping' && m.say('pong'));
bot.start();
```

配套示例：

- **[wechat-skill-examples](https://github.com/leeguooooo/wechat-skill-examples)** — 终端 bot（echo / 群 @ 过滤 / LLM 接入），三个文件就能跑
- **[wechat-skill-web-demo](https://github.com/leeguooooo/wechat-skill-web-demo)** — 完整网页版微信（Svelte 5 + Tailwind + wechaty SDK），可直接 fork 改成自定义前端

![wechat-skill-web-demo](docs/images/wechat-skill-web-demo.png)

### C. HTTP-native agent（Hermes / OpenClaw / n8n / Dify / LangChain）

独立二进制 `wechat-bridge`，本地 HTTP + SSE：

```bash
wechat-bridge &                          # 默认 127.0.0.1:18400
wechat-bridge --shape hermes &           # Hermes WhatsApp-bridge 同 shape，零适配
```

8 个稳定路由：`/health` / `/send` / `/chats` / `/unread` / `/contacts` / `/chat/:wxid` / `/chat/:wxid/history` / `/resolve` / `/messages/stream`（SSE）。

> Hermes / OpenClaw 已经接了 WhatsApp / Telegram / Discord / Slack / Signal / iMessage，没内建 WeChat —— `wechat-bridge` 就是他们接微信的标准入口。

SSE payload 字段（`messageKind` / `mentionedIds` / `isMentioned` / `fromSelf` / `urlLink` / `miniProgram` / `refer` / `recall` / `media` / …）固定在 [`wx/schema/sse-payload-v1.10.28.schema.json`](./wx/schema/sse-payload-v1.10.28.schema.json)。详细字段说明 → [docs/capabilities.md#http-bridge](./docs/capabilities.md#接-agent-平台hermes--n8n--dify--langchain)。

---

## 出问题了？

1. `wechat doctor` —— 一行看完 lldb / WeChat 版本 / 签名 / key / daemon / dylib 指纹哪一项 ✗
2. 把 `wechat doctor` 整段输出 + 报错描述发给 [@WechatCliBot](https://t.me/WechatCliBot)
3. `wechat init` 失败时（v1.8.13+）会在终端 inline dump 完整诊断块，把那段贴过来

详细排错矩阵 → [docs/troubleshooting.md](./docs/troubleshooting.md)。

---

## 安全

- **只读 / 本地**：聊天内容、联系人、解密密钥的读取全在你自己机器上做。出站流量只有一条：向 profile API POST 当前 WeChat dylib 的 SHA-256 拉对应 offsets 表。聊天内容 / 联系人 / key / wxid **永远不出本机**。
- **key 文件** `~/.wx-rs/key.hex` 是你微信账号所有本地数据的万能解密钥。chmod 600 自动设。**绝不要**贴到 git / pastebin / 群聊。怀疑泄漏：微信里退出再登录 → 新账号目录 + 新 key，旧的作废。
- **激活码 token** 进 macOS Keychain（service `wechat-skill-profile-api`），不裸文件。
- **不改 WeChat.app 二进制 / 不签新 dylib** —— 仅 ad-hoc 给 WeChat 主可执行加 `get-task-allow` entitlement（LLDB 必需），Tencent 自动更新会覆盖，下次 init 自动再加。

---

## 平台支持

- macOS Apple Silicon
- WeChat 4.0.1.52 / 4.1.8（build 36830 / 37335 / 37342）已验证
- Tencent 热更后通过 server-side profile 推送新 build 适配，**无需重新发 release**

---

## 文档导航

- [docs/why-init.md](./docs/why-init.md) — `wechat init` 在干嘛（怎么从内存里抓 SQLCipher key）
- [docs/why-activation.md](./docs/why-activation.md) — 为什么走人工审核制
- [docs/capabilities.md](./docs/capabilities.md) — 完整能力矩阵 + 不打算做的
- [docs/install.md](./docs/install.md) — 详细安装 / TCC 授权 / 多账号 / LaunchAgent
- [docs/troubleshooting.md](./docs/troubleshooting.md) — Tencent 热更 / 签名 / 0 hits 等常见排错
- [docs/CHANGELOG.md](./docs/CHANGELOG.md) — 完整版本历史
- [docs/ROADMAP.md](./docs/ROADMAP.md) — 路线图 / 不做的事

---

## License

[非商业自研协议](./LICENSE) + [DISCLAIMER（中英）](./DISCLAIMER.md)。

仅个人学习 / 研究 / 个人自动化。商业使用需另谈授权（目前不开放）。

---

## ⚠️ 使用前必读（免责声明）

- 本工具基于 macOS 公开调试接口（LLDB）实现，**仅用于用户本人设备上的个人自动化**。
- **不得**用于任何商业场景、群发营销、刷单拉新、爬取他人数据、监控他人账号等滥用行为。
- 所有数据读取 / 解密均在**用户本人设备本地完成**，不向任何第三方传输聊天内容、联系人、二进制明文或解密密钥。仅向 profile API 发送当前 WeChat dylib 的 SHA-256 用于版本适配（不含任何账号信息）。
- 使用本工具即表示用户**了解并自行承担全部风险**，包括但不限于微信账号被限制 / 封禁的可能。
- 本工具**与腾讯公司无任何关联**，腾讯保留依据《微信软件许可及服务协议》采取相应措施的权利。
