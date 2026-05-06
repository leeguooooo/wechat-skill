# 为什么 `wechat init` 要重启微信

微信在 macOS 本地存的所有数据（聊天记录、联系人、朋友圈缓存、收藏……）都是 **SQLCipher 加密**的。没有解密 key，磁盘上的 `.db` 文件全是乱码，任何查询命令都无法工作。

## init 在干什么

1. **重启 WeChat**：解密 key 只在微信启动的某个瞬间写入内存特定位置，之后就被覆盖。要用 **最轻量、非侵入** 的方式拿到它，就必须卡在启动这一瞬间 —— 所以 init 必须先把当前 WeChat 关掉再重新打开。
2. **用 LLDB 断点精确抓 key**：仅在那个写入瞬间触发一次断点，读 32 字节 raw key，然后立刻 detach。**不会改 WeChat 二进制 / 不会写任何东西 / 不需要 sudo（除了 v1.8.16+ 的一次性系统前置）/ 不会对 wechat.dylib 重签名**（其他同类方案会改你的 WeChat.app，我们不改）。
3. **缓存到 `~/.wx-rs/key.hex`**：后续所有查询命令（`sessions` / `history` / `search` / ...）都从这里读 key，无需再 init。

只有微信**重启过**（机器重启、手动 quit、系统更新等）之后，key 才会失效，这时再跑一次 `wechat init` 即可。

## 为什么第一次跑要 sudo 密码（一次性）

v1.8.16 起 init 自动检测 + 修复两项 macOS 系统前置：

1. **macOS Developer mode** — 关着 `lldb` 连任何进程都不能 attach。修复：`sudo DevToolsSecurity -enable`（系统级一次性开启）
2. **WeChat 二进制 entitlement `get-task-allow`** — 腾讯官方签名禁止 debugger attach。修复：`sudo codesign --force --sign - --entitlements <plist> /Applications/WeChat.app/Contents/MacOS/WeChat`（本地 ad-hoc 重签，**只动主可执行文件**，wechat.dylib + 登录态 + 数据全不动）

每步执行前 init 会打印「是什么 / 为什么 / 执行 / 影响」四段说明，**不会偷偷跑 sudo**。如果你不想自动跑，按 Ctrl-C，自己手敲也一样。

WeChat 自动更新后第二项会被覆盖，下次 init 自动再修一次。

## v1.8.13+ 自动 calibrate

Tencent 热更可能在「自动升级」关闭的情况下仍然把 `wechat.dylib` 换成新版本（Sparkle / WeChat 内置更新路径）。新 dylib 的 SQLCipher init 函数 RVA 会偏移。

v1.8.13 起，init 默认带 `--calibrate`：通过字符串 xref 静态定位 SQLCipher config 函数 → 在线 BP → memcpy 抓 key。**每个新 dylib SHA 上自动重新校准并缓存。不再需要手动 `--force` 或换 dmg。**

## 失败怎么办

v1.8.15+ 起，init 失败时会把所有诊断信息（`================ 诊断信息 ================`）直接打印在终端里，**贴整段输出到 [@WechatCliBot](https://t.me/WechatCliBot) 即可**，不用再去 `/var/folders/.../wx-calibrate-NNN/` 翻 log。

常见排错见 [troubleshooting.md](./troubleshooting.md)。
