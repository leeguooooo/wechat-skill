# 排错手册

> **第一招**：跑 `wechat doctor` 看哪一行 ✗，然后照 hint 提示做。
> **第二招**：把 `wechat doctor` 整段输出 + 你的报错 DM 给 [@WechatCliBot](https://t.me/WechatCliBot)。

## init 相关

| 现象 | 原因 | 自救 |
|---|---|---|
| `Not allowed to attach to process` | DevToolsSecurity 没开 / WeChat 没 get-task-allow | v1.8.16+ init 自动修；老版本手动跑诊断信息里的命令 |
| `观察到 0 次 32-byte memcpy 触发` | 用户已登录但 init 错过了 SQLCipher init 时刻 | v1.8.13+ SIGSTOP race fix 已修；如还 0 hits 贴诊断 |
| `dylib SHA 不一致` 警告 | Tencent 热更过 dylib | calibrate 自动重新定位；如失败贴诊断 |
| init 卡 5 分钟超时 | 没及时点「进入 WeChat」按钮 | WeChat 重启后立刻点 / 扫码登录，否则 SQLCipher init 不会触发 |

v1.8.15+ 起，init 失败时**会在终端 inline dump 完整诊断**（`================ 诊断信息 ================`）—— 贴整段就够。

## send 相关

| 现象 | 原因 | 自救 |
|---|---|---|
| `请先 wechat auth activate` | 没激活订阅 | DM bot 拿激活码 → `wechat auth activate <code>` |
| `订阅已过期` | 过期了 | `wechat auth renew` 看续费方式 |
| `unsupported WeChat build` | 当前 dylib SHA-256 还没在 profile API 注册 | 把 `wechat doctor` 输出的 SHA 发给 bot，几小时内会推 |
| 消息发了但没到 | 检查 `wechat sessions` 里目标对话最新时间 | 重试一次 |
| 用户手动给别人发消息被路由错 | v1.9.0 早期 bug | v1.9.1 已修；升级到最新版本 |

## auth / 订阅

| 现象 | 原因 | 自救 |
|---|---|---|
| `该设备已领取过试用` | 同 machine_id 一次 trial | DM bot 申请 m1 / 续费 |
| `auth status` 显示 expired | token 过期 | `wechat auth renew` |
| Keychain 弹框反复弹 | 没点「Always Allow」 | 第一次激活时点 Always Allow 即可永久 |
| 没有 macOS Keychain（headless SSH） | 服务器场景 | `WECHAT_AUTH_TOKEN_ENV=wxp_tok_xxx wechat ...`（token 走环境变量不落盘） |

## daemon / 性能

| 现象 | 原因 | 自救 |
|---|---|---|
| 第一次 send 慢 5-7s | 冷启 daemon LLDB session | 后续 send 都是 ~700ms，正常 |
| daemon 莫名退出 | WeChat 自身 quit / 系统 sleep 唤醒 | 任意 query 命令会 lazy-spawn 新 daemon，无感 |
| `daemon ping` 失败 | wechatd 没起来或 socket 坏了 | `wechat daemon stop && wechat daemon start` |

## Tencent 热更后

WeChat 可能在「自动升级」关闭的情况下仍然换 `wechat.dylib`（Sparkle / WeChat 自带更新）。

- **抓 key (`wechat init`)**：v1.8.13+ 默认 `--calibrate`，每个新 dylib SHA 自动校准并缓存。**不需要手动 `--force` / 换 dmg。**
- **发消息 (`wechat send`)**：v1.9.1 起从 server-side profile API 拉 RVA，新版本由我们后端推送，**客户端不用升级**。如果 profile API 上没有当前 dylib SHA，会报 `unsupported WeChat build` —— 把 SHA 发给 bot 我们登记。

## 我没看到我的问题

DM [@WechatCliBot](https://t.me/WechatCliBot)，附上：

1. `wechat doctor` 整段输出
2. 报错命令 + 完整错误信息
3. （如果是 init / send 问题）`================ 诊断信息 ================` 整段
4. WeChat 版本：System Settings → Apps → WeChat → 看 build 号

通常 1-12h 回复。
