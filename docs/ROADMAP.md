# 路线图

## 在做 / 即将做

- **发图片 / 文件**：`wechat send --image <path>` / `--file <path>`
- **非文本消息解析（listen 侧）**：当前 XML `appmsg` / 引用 / 图片消息出原始 XML，要二次解析提 title / url
- **付款集成**：当前内测期免费 + 人工审核；后续接 Stripe / 加密货币

## 已完成（最近）

- ✅ v1.9.1 订阅模型 + 自动从服务端拉新版本 profile（Tencent 热更不用重发 release）
- ✅ v1.9.0 daemon-backed 发送（4× 提速）
- ✅ v1.8.13 init 自动 calibrate（Tencent 热更不用手动 `--force`）
- ✅ v1.8.10 真零闪屏（CGEvent + LLDB hijack）

## 不打算做

- 群发 / 自动加好友 / 反向爬别人朋友圈
- Linux / Windows / Intel Mac
- 反调试 / 二进制混淆
- 公开 RE 资料（offsets / RVA）

## 想看新版本？

订阅 Telegram 频道：<https://t.me/+4PuAO3lB9R82ZTVh>
