# wechat-skill

把 macOS 上的微信变成给 AI agent / bot 用的**本地 API**。
不上云、不上 iPad 协议、纯本地 LLDB hook,数据只在你这台 Mac 上动。

---

## 5 秒看明白

按吸引力挑一个进入:

| 你在用 | 装这个 | 做什么 |
|---|---|---|
| **Claude Code / Codex / Cursor** | [SKILL.md](./SKILL.md) | agent 学会发消息、查记录、收消息流 |
| **直接命令行** | `wechat send / sessions / listen` | shell 脚本和 cron 友好 |
| **任意 [wechaty](https://github.com/wechaty/wechaty) bot**(TS / Python / Go) | `wechat-wechaty-gateway`(gRPC :18401) | 首个真号 wechaty macOS 协议,bot 零改动跑在自己微信上 |
| **HTTP-native agent**(Hermes / n8n / Dify / LangChain) | `wechat-bridge`(HTTP + SSE :18400) | WeChat 变成跟 WhatsApp / Slack 同 shape 的本地接口 |
| **接入自己 SaaS / CF Worker** | `wechat orchestrate`(NAT-friendly poll) 或 `wechat tunnel`(CF Tunnel + JWT) | 远程驱动本机微信 |

所有 surface 共享同一个 daemon + 同一个激活码,**装一次全开**。

---

## 装一下(5 分钟)

### 1. 拿激活码

跟 [@WechatCliBot](https://t.me/WechatCliBot) 私聊 → `/start` → 「📝 申请激活码」→ 写一行用途 → 通过后机器人发你 `wxp_act_xxxxxx`。
前置:订阅频道 <https://t.me/+4PuAO3lB9R82ZTVh>。审核 1-24h,[为什么走审核制](./docs/why-activation.md)。

### 2. 装 CLI

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
```

确认 `~/.local/bin` 在 `PATH` 里(fish: `fish_add_path $HOME/.local/bin` / zsh: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`)。

### 3. 激活 + 初始化

```bash
wechat init                              # 自动按 WeChat 版本选提取路径
wechat auth activate wxp_act_xxxxxx
wechat send "Hello 🎉" filehelper        # 后台发,不抢焦点不闪屏
```

辅助功能授权(macOS Sonoma+ 强制) + TCC 细节 → [docs/install.md#tcc](./docs/install.md#tcc)。

---

## 命令行用法

```bash
# 发消息(recipient 可以是 wxid / 昵称 / 备注 / 群名)
wechat send "你好" 张三

# 查聊天
wechat sessions                       # 最近会话
wechat unread                         # 有未读的
wechat history "张三" -n 50
wechat search "会议" --in "项目讨论组"

# 收消息流(agent 神器)
wechat listen --wxid filehelper
wechat listen --on-message ./reply.sh

# 自检
wechat doctor                         # 任何问题先跑这个
wechat auth status
```

完整能力矩阵 → [docs/capabilities.md](./docs/capabilities.md)。

---

## 接 AI agent

**A. Claude Code / Codex / Cursor** — `npx skills add leeguooooo/wechat-skill -y -g`,agent 读 [SKILL.md](./SKILL.md) 自动学会全部命令。先装 CLI 再装 skill。

**B. wechaty bot(任意语言)** — `wechat-wechaty-gateway` 起 gRPC :18401,任意 wechaty 1.x 客户端零改动接入 (`puppet: 'wechaty-puppet-service'` + `endpoint: '127.0.0.1:18401'`)。例子:[`examples/`](./examples/)(echo / mention-only / LLM bot / CF Worker bot)。

**C. HTTP / SSE bridge** — `wechat-bridge` 起 HTTP+SSE :18400,8 个稳定路由,可加 `--shape hermes` 跟 Hermes WhatsApp-bridge 同 shape 零适配。SSE schema → [`wx/schema/sse-payload-v1.10.28.schema.json`](./wx/schema/sse-payload-v1.10.28.schema.json)。

**D. 远程驱动**:
- `wechat orchestrate setup` — Mac 全 outbound poll SaaS outbox,**不需公网 IP / 域名**(家用宽带 / 公司内网 / GFW 后面都行)→ [docs/v1.12-orchestrate-protocol.md](./docs/v1.12-orchestrate-protocol.md)
- `wechat tunnel setup` — Cloudflare Tunnel 暴露 + JWT 同步调,适合 CF Worker 偶发触发 → [docs/remote-gateway.md](./docs/remote-gateway.md)

---

## 出问题 / 安全 / 平台

- **排错**:`wechat doctor` 看哪一项 ✗ → 整段输出 + 报错描述提 [GitHub issue](https://github.com/leeguooooo/wechat-skill/issues/new)。详细 → [docs/troubleshooting.md](./docs/troubleshooting.md)
- **安全**:聊天 / 联系人 / key / wxid **永不出本机**;只向 profile API POST 当前 WeChat dylib SHA-256 拉适配 offsets。`~/.wx-rs/key.hex`(4.1.7/8) / `~/.wx-rs/keys.json`(4.1.9+) 已 chmod 600,**绝不要**贴 git / pastebin / 群聊。激活码 token 进 macOS Keychain。不改 WeChat.app 二进制,只 ad-hoc 加 `get-task-allow` entitlement
- **平台**:macOS Apple Silicon。已验证 WeChat 4.0.1.52 / 4.1.8(builds 36830 / 37335 / 37342) / 4.1.9(build 268575)。Tencent 热更后 server-side profile 推送新 build 适配,**无需重发 release**

---

## 文档

- [docs/why-init.md](./docs/why-init.md) — init 在干嘛(LLDB BP 抓 key vs 内存扫描)
- [docs/why-activation.md](./docs/why-activation.md) — 审核制理由
- [docs/capabilities.md](./docs/capabilities.md) — 完整能力矩阵
- [docs/install.md](./docs/install.md) — 详细安装 / TCC / 多账号 / LaunchAgent
- [docs/troubleshooting.md](./docs/troubleshooting.md) — 热更 / 签名 / 0 hits 等
- [docs/v1.12-orchestrate-protocol.md](./docs/v1.12-orchestrate-protocol.md) / [docs/remote-gateway.md](./docs/remote-gateway.md) — 远程驱动两条路
- [docs/CHANGELOG.md](./docs/CHANGELOG.md) / [docs/ROADMAP.md](./docs/ROADMAP.md)

---

## License + 免责

[非商业自研协议](./LICENSE) + [DISCLAIMER](./DISCLAIMER.md)。仅个人学习 / 研究 / 个人自动化,商业使用需另谈授权(目前不开放)。

本工具基于 macOS 公开调试接口(LLDB)实现,与腾讯公司无关联;**不得**用于商业 / 群发营销 / 刷单 / 爬取他人数据 / 监控他人账号。使用即表示用户**自行承担全部风险**(含微信账号被限制 / 封禁的可能)。
