# 详细安装与授权

主 README 的「装一下（5 分钟）」是给已经知道自己在干嘛的开发者看的极简流程。这篇是完整版：每一步在干啥、出问题去哪查。

---

## 0. 前置

- macOS Apple Silicon
- 已订阅频道 <https://t.me/+4PuAO3lB9R82ZTVh>（不订阅 bot 拦截审核）
- 已有 WeChat 4.0.1.52 / 4.1.8 任一版本（build 36830 / 37335 / 37342 已验证）
- 终端有 `~/.local/bin` 在 `PATH`

---

## 1. 拿激活码

跟 [@WechatCliBot](https://t.me/WechatCliBot) 私聊：

1. 发 `/start`
2. 点「📝 申请激活码」按钮
3. 按提示回一行用途说明，例如：
   > 个人调研对话存档，希望让 Claude 自动同步给我每日待办
4. 等管理员审核（通常 1-24h）
5. 通过后机器人会私信你 `wxp_act_xxxxxx`

为什么人工审核 → [docs/why-activation.md](./why-activation.md)。

---

## 2. 装 CLI

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/wechat-skill/main/install.sh | bash
```

`install.sh` 干的事：

1. 下载 binary 到 `~/.local/bin/`：`wechat` / `wechat-bridge` / `wechatd` / `wechat-wechaty-gateway` / `wechat-inspect-msg`
2. 给 binary 加可执行位 + ad-hoc codesign（macOS Gatekeeper 必需）
3. 注册 `ai.wechat.bridge` LaunchAgent（开机自启 wechat-bridge）
4. 启动 LaunchAgent 跑 `/health` 探活

确认 PATH：

- **fish**：`fish_add_path $HOME/.local/bin`
- **zsh / bash**：`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`

---

## 3. 授权「辅助功能」（TCC）<a id="tcc"></a>

**首次用 `wechat send` 前必须做一次，不做会静默失败。**

macOS Sonoma 起，跨进程合成键盘事件的发送方必须在「辅助功能」清单里，否则系统直接把事件丢掉，无错误码无日志。`wechat-bridge` / `wechatd` 走这个 API，必须授权。

打开下面两条，一条弹设置窗口、一条进入文件位置方便拖：

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "$HOME/.local/bin"                    # Finder 打开，选中 wechat-bridge 拖进设置窗
```

然后：

1. 系统设置 → 隐私与安全 → **辅助功能**
2. 点 `+`，选 `$HOME/.local/bin/wechat-bridge`，加进清单
3. 打开右侧开关
4. 重启已经跑起来的 bridge，让它继承新权限：
   - LaunchAgent：`launchctl kickstart -k gui/$(id -u)/ai.wechat.bridge`
   - 手工启的：`pkill wechat-bridge; wechat-bridge &`

> `wechatd` 不用单独加，TCC 按 responsible-process 链继承 `wechat-bridge` 的授权。
> Input Monitoring / 输入监控 不参与 `wechat send` 路径，可以忽略。

确认授权到位：

```bash
wechat doctor --json | jq '.checks[] | select(.name=="ax_trusted")'
# → {"name":"ax_trusted","ok":true,"detail":"wechatd /Users/..../wechatd"}
```

---

## 4. 激活 + 初始化

```bash
wechat auth activate wxp_act_xxxxxx
# ↑ 弹 macOS Keychain 授权框，点「Always Allow」

wechat init
# ↑ 抽 SQLCipher key，会重启微信。第一次会要 1 次 sudo 密码
#   修系统前置（DevToolsSecurity + 给 WeChat 主可执行加 get-task-allow），
#   每步都打印"是什么/为什么/影响"，不偷跑
```

完整 `wechat init` 内部细节 → [docs/why-init.md](./why-init.md)。

---

## 5. 验证

```bash
wechat send "Hello 🎉" filehelper      # 应该 < 1s 在文件传输助手收到
wechat sessions                        # 列出最近会话
wechat doctor                          # 全绿
```

任何一项失败 → [docs/troubleshooting.md](./troubleshooting.md)。
