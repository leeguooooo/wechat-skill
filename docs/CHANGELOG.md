# 更新日志

## v1.13.30 — 2026-05-06

修 codex review v1.13.29 找到的 1 BLOCKER + 4 SHOULD + 1 NICE,叠加 user feedback 的 **warmup 自动 retry**(daemon 重启后第一次 send 不再要用户手动重跑命令)+ agent 友好 `created_at` 字段。

**BLOCKER** — `🔊 ` marker 泄漏到下游 bridge / wechaty gateway:v1.13.29 默认在 `display_text` 加 `🔊 ` marker,但 SSE bridge 跟 wechaty-puppet gateway 都直接读这个字段推下游,LLM agent 收到 `"🔊 你好"` 而不是 `"你好"`。修:**`display_text` 永远 raw**,新增 `display_text_rendered` 字段在 audio + transcribed 时带 marker。`brief` 视图优先读 `_rendered`,bridge / gateway 不变自动拿 raw。

**`SlotSendBpArmedNoFire` 自动 warmup retry**:daemon 检测到 BP 没 fire 时(WeChat 重启后 Qt slot_send signal chain 还没 wired),不再立即返回失败。**daemon 同步 watch FSEvents on `message_*.db` 父目录 60s**,检测到用户在 WeChat 里手动发任意消息(任何聊天)的 DB 写入 → 0.8s 沉淀 → 重跑 hijack.send + verify_delivery。匹配 + 路由正确 → 返回 success(用户 CLI 看到原 send 成功,**不需要重跑命令**)。失败沿用原响应。

**SHOULD 修复:**

- `doctor audio_transcribe_default_model` Auto-aware:v1.13.29 hardcode `ggml-medium.bin` → 用户装 small 没装 medium 时 ok=false 误报,但 Auto 解析其实用 small 转写正常。改成 `any_model_present` 真实反映状态。
- `--kind` 不含 audio 时跳 transcribe:v1.13.29 用 `--kind text` 仍 transcribe 所有 audio 再 filter 掉,浪费最多 10s。peek kind filter 在 enrich 之前。
- `AudioSummary.model_used` 进 stderr meta:agent 通过 stderr `[history] meta: {... "model_used":"small" ...}` 直接看到 Auto 解析到哪个模型,不再要猜。
- `parse_relative_time` 加 `d` / `w` 单位:`--since "3 d ago"` / `--since "2 w ago"` 现接受。

**Plus**(codex CLI 实测反馈):

- `wechat history` JSON 每条 row 加 `created_at` 字段(本地时区 `YYYY-MM-DD HH:MM:SS` 格式)。agent 不再要从 `create_time` epoch 自己转换时间做 jq pipeline。原 `create_time` 字段保留。

测试:213 lib tests pass,e2e history `--since yesterday --kind audio` 5 case OK。

**留 v1.13.31+**(codex CLI 反馈未做):
- daemon stale socket 自动清理(踩过 `/tmp/wechatd-501.sock` 残留 → connection refused 要手动删)
- `history --strip-xml` / `--fields a,b,c`(appmsg XML 撑爆 agent context window)
- `doctor needs_init` vs `needs_send_verify` 状态机 disambiguation
- `wechat digest <chat>` 内置摘要命令(大 feature 单独立项)

## v1.13.29 — 2026-05-06

`wechat history` 真用 1 次查 2 天群历史后撞到 **6 个糙点**全修。

- **`--limit` 默认 20 → 100**:看 2 天群历史 20 条根本不够。新用户也会撞;新默认覆盖大多数场景,真要看更多 `-n 500`。
- **`--since` 接自然语言时间**:`today` / `yesterday` / `now` / `N seconds|minutes|hours|days|weeks ago`。例:`wechat history "群名" --since "2 days ago"`,告别手动算 `2026-05-04` ISO date。case-insensitive,fall through 到老 ISO + epoch 路径不破坏老用法。
- **`--transcribe-model auto`(新默认)**:`WhisperModel` 加 `Auto` variant + `resolve_installed()` 自动选已装最大(Large > Medium > Small)。装 small 没装 medium 的用户终于不用手动加 `--transcribe-model small` 了。`wechat audio transcribe` 也走同样默认。
- **转写文字加 `🔊 ` prefix**:`display_text = "🔊 这PP付费啊..."`。agent 直接读能识别这条是语音转写来源(语气 / 同音字误差跟文字打字不同)。`--no-transcript-marker` 关掉前缀;`media.transcript` 字段始终是 raw 文字(无前缀)。
- **`--brief` 紧凑视图**:`<MM-DD HH:MM>  <sender>  <text>` 一条一行 chrono 正序,适合 `less` / `tail` 翻看。system 消息跳过(revoke 噪声),emoticon/image/video 无 display_text 时填占位。
- **`--kind <KIND[,KIND...]>` 过滤**:`--kind audio` 只看语音、`--kind text,audio` 文字+语音、等等。filter 在 transcribe 之后,所以 audio 行带 transcript 后再筛。
- **`--json` 模式 stderr `[history] meta:` 汇总**:agent 跑 `--quiet --json` 之前完全拿不到转写汇总。新增单行 `[history] meta: {"audio_total":N,"cached":X,"transcribed":Y,"no_deps":Z,"failed":W,"skipped":S,"elapsed_ms":T}` 到 stderr,**`--quiet` 不静默这条**(只静默 verbose 进度),`2>` 可独立 capture。

测试:5 unit tests for `parse_relative_time`(today / yesterday / now / N units ago / unknown / case-insensitive)。208 → 213 全 lib pass。e2e 实测 6 个 feature 全 OK。

**Skip**(留下次):whisper confidence score 标记同音字段(whisper-cli wrap 复杂,长期),emoticon caption 抽取(用户 sticker 没 metadata 源)。

## v1.13.28 — 2026-05-06

修 codex round-3 review v1.13.27 找到的 1 BLOCKER + 1 SHOULD。

**BLOCKER — 4 个 `pub mod` 引用的源文件 untracked**:`wx/src/instance.rs`(226 LOC)、`wx/src/cli/cdninfo_decoder.rs`(327 LOC)、`wx/src/cli/image_get_replay.rs`(286 LOC)、`wx/src/daemon/cdn_capture.rs`(340 LOC)早期 session 写的,本机一直在 working tree build 出来 OK 但 git 没 track。clean clone 从源码编译会失败 missing module。补 `git add`。装 prebuilt binary 的用户不受影响。

**SHOULD — `fetch_silk_blob` multi-shard warning 无条件写 stderr**:v1.13.27 这个 helper 命中多 shard 时无条件 `eprintln!`,history per-row 调用时 `redact=false` → 泄漏 `xwechat_files/<account>/` 完整路径到 stderr,JSON / `--quiet` 模式都漏。9 条 audio history 可能 fire 18 次。新增 `emit_warnings: bool` 参数:`lookup_cache_for_history` + `transcribe_with_cache` 都传 `false`(history 调用 per-row 噪声 + leak),`get_audio` 仍传 `true`(终端用户 debug 哪个 shard 命中)。

测试:14 audio + 全 lib 208 tests pass。

## v1.13.27 — 2026-05-06

修 codex round-2 review v1.13.26 找到的 4 SHOULD,无 BLOCKER。

- **`history` cache hit 路径改 in-memory**(`audio.rs::lookup_cache_for_history`):v1.13.26 这个 fn 内部调 `audio get` → silk 写盘 → 读盘 → SHA → cache lookup,silk 写失败被当作 cache miss(逻辑错误,cache 实际有 entry 但拿不到)。新增 `fetch_silk_blob` 纯内存 SQLCipher fetch + strip,lookup 路径 0 disk 副作用。`get_audio` + `transcribe_with_cache` 都 refactor 到共用这个 helper,transcribe pipeline 内部 silk 改写到 tempdir 不再 trample 用户可见 `~/.wechat/audio-cache/`。
- **`install_silk_decoder` 也用 `tempfile::TempDir`**:v1.13.26 转写 pipeline 已经换了,但 setup 时构建 silk-decoder 仍用 `/tmp/wechat-silk-build-<pid>` 可预测路径 + 先 `remove_dir_all`。symlink race 攻击面同款。统一换 random tempdir + auto cleanup on drop。
- **Crate-wide `testkit::home_lock()`**:v1.13.26 `transcript_cache::tests` 有私有 `HOME_LOCK`,`auth::tests` 独立 `env_lock()`,并行测试两边都 `set_var("HOME")` 仍 race(macOS 上 UB)。新增 `wx::testkit` pub mod 提供单一 `home_lock()` 给两边共用。`auth::env_lock` 改 delegate。
- **`doctor` 拆 2 条 audio check**:v1.13.26 `audio_transcribe_deps` 总 `ok=true`,机器消费者 parse JSON 看 `ok` 永远绿,即使 `ggml-medium.bin` 缺(history 默认用 medium → 实际转写会 NoDeps)也看不出来。拆成:
  - `audio_transcribe_setup`(3 工具 ffmpeg/whisper-cli/silk-decoder 整体在不在,**总 ok=true**,只走 detail/hint)
  - `audio_transcribe_default_model`(`ggml-medium.bin` 存在 + size>0,**`ok` 反映现实**)
  Status 计算把 `audio_transcribe_default_model` 加进 exempt 名单(同 `send_delivery_verified` 待遇),medium 缺也不会 push 整体 status 到 `needs_init`。机器消费者 parse `checks[].name == "audio_transcribe_default_model"` 那条直接看 `ok` 字段就知道 history 默认转写能不能跑。

**Plus:** `scripts/preflight-release.sh` 跟着改 — 用 `doctor --json` 看 `status` 而不是 grep `✗`,避免 `audio_transcribe_default_model` 这种 exempt 信号让 release 误失败。

测试:208 passed,e2e 验证 history cache hit 0 disk 副作用,`audio get` 仍写 `audio-cache`,doctor JSON `all_ok=true status=ok` 即使 `default_model.ok=false`。

## v1.13.26 — 2026-05-06

修 codex round-1 review v1.13.25 找到的 5 SHOULD + 2 NICE,无 BLOCKER。

**5 SHOULD:**

- **`pipeline_version` 进 cache key**(`transcript_cache.rs`):v1.13.25 把 `tool_version` 存进 CachedTranscript 但没进 filename;tool 升级后旧 cache 永远 hit。新增 `PIPELINE_VERSION = "1"` 常量,filename 改 `<sha>__<model>__<lang>__v1.json`,lookup 加 schema 检查,bump constant 自动 invalidate 全部历史 entry。新增 `pipeline_version_mismatch_misses` unit test。
- **`tempfile::TempDir` 替预测 tempdir**(`audio.rs`):v1.13.25 用 `/tmp/wechat-transcribe-<pid>-<svr_id>/` 可预测路径,`/tmp` 共享 + symlink race 风险。改用 random tempdir(`tempfile` 升级到主 deps)。
- **`history` 末尾 transcribe 汇总行**(`history.rs`):v1.13.25 只在最前面 stderr 一次 no_deps warning,长 history 用户容易错过。新增 `[history] 语音转写汇总(N 条 audio): X 命中缓存 / Y 现转 / Z 跳过(依赖缺) / W 失败` 末尾汇总行。
- **Cache lookup 移到 deps check 之前**(`audio.rs`):v1.13.25 `transcribe_for_history` 先检查 ffmpeg/whisper-cli/silk-decoder/model 再查 cache,装好用过再卸掉的用户拿不到 cache hit 强迫重转。新增 `lookup_cache_for_history`(只读 SQLCipher + SHA + JSON parse,不依赖外部工具),命中直接返回;只有 miss 才 deps check。
- **`doctor` 检 default model 而不是任意 .bin**(`doctor.rs`):v1.13.25 看到 `ggml-small.bin` 就报 ok,但 history 默认用 medium → doctor 绿但 transcribe 红。改成检 `ggml-medium.bin` 是否存在,装了 small/large 没装 medium 时 detail 行明确说 "装了 X 但 history 默认用 medium",hint 给精准引导(`--transcribe-model X` 切已装 / `wechat audio setup --model medium` 补齐)。

**2 NICE:**

- **`history --quiet` flag**(`history.rs`):JSON 模式默认自动启用,防 `2>&1 | jq` 撞 JSON。手动 flag 给非 JSON shell pipeline 用。
- **Cache write 失败 log warning**(`audio.rs`):v1.13.25 `let _ = transcript_cache::store(&entry)` 吞掉,disk-full / 权限错误下每次重转用户不知道为啥。改 stderr 一行 `cache store failed (...)` warning。

**Skip:**

- NICE #3 cache hit 仍走 SQLCipher 读(codex 自己说当前规模可接受)
- NICE #4 WhisperModel double source of truth 清理(低优先级 cleanup)

测试:cache 测试加 HOME_LOCK mutex 防并发 race,新增 `pipeline_version_mismatch_misses`,共 4 transcript_cache + 14 audio = 18 unit tests。e2e 实测:cache 二次访问 0.3s 全 hit,doctor 正确报 medium 缺(本机只有 small)。

## v1.13.25 — 2026-05-06

新增**语音转文字端到端 + history 自动转写**,过 codex 1 BLOCKER + 6 SHOULD review 全采纳。

**3 个新命令 + history 集成:**

- `wechat audio setup [--model small|medium|large]` — 一次性装齐 4 个依赖:`brew install ffmpeg whisper-cpp` + `git clone+make` kn007 silk-decoder 到 `~/.wechat/bin/silk-decoder`(本地构建避开 macOS Gatekeeper / quarantine / Developer-ID 签名顾虑)+ 下载默认 `ggml-medium.bin` (~1.5GB) 到 `~/.wechat/whisper-models/`。`--force-reinstall` 强制重装,`--yes` 非交互。
- `wechat audio transcribe <svr_id>` — 一条龙 audio get → silk-decoder → ffmpeg PCM → 16kHz wav → whisper-cli。默认 `--language zh --model medium`。**`--json` 默认 `transcriptRedacted: true` 不出文字内容**(防 agent log 外泄),`--include-transcript` 才出。
- **`wechat history` 自动转写语音**(关键!):看群聊历史时,语音消息会被自动 whisper 转成文字塞进 `display_text` + `media.transcript`,**agent 不再看到 `[语音消息]` 占位、上下文连贯**。SHA-256 内容寻址 cache(`~/.wechat/transcript-cache/<sha>__<model>__<lang>.json`),实测**首次 9 条语音 ~30s,二次访问 0.4s 全 cache 命中**。`--no-transcribe` 跳过转写;`--transcribe-model` / `--transcribe-language` 切模型/语种。`media.transcript_status` 字段(`cached`/`transcribed`/`no_deps`/`failed`)告诉 agent 这条转写从哪来。

**`wechat doctor` 加 `audio_transcribe_deps` 信息行**:列 4 个依赖现状,缺什么提示 `wechat audio setup`。**永远 ✓**(audio 是 optional feature,不让 doctor 误转 needs_init)。

**关键设计决策:**
- 不 vendor SILK SDK 进 Rust(SKP_SILK_SDK 1500+ LOC C 代码维护负担);走 shell-out + 本地 build
- 不 ship prebuilt silk-decoder binary(没 Apple Developer ID,prebuilt 会撞 Gatekeeper / quarantine);用户机器自己 git clone + make,无需我们签名
- 不自动装 Homebrew(那要 sudo + 动 /opt/homebrew 整目录);brew 没装就 bail 给手动指引
- 默认 `medium` 模型(1.5GB)而不是 `small`(487MB)— 中文准度差异远大于下载耗时
- 隐私三态:`audio transcribe --json` 默认隐藏文字(reverse opt-in `--include-transcript`);`audio get` 默认 redact 路径;**`history` 默认出文字**(跟普通文本消息同等待遇,opt-out 用 `--no-transcribe`)
- Cache 走 SHA-256(silk_blob)+ model + language 作 key(codex Q5 BLOCKER 修),防 schema 漂移 / svr_id 复用产生 stale transcript

**Bug fix:** 修 wav header parser — ffmpeg 写的 wav 有时在 fmt 跟 data 之间插 JUNK chunk,固定偏移 40 读 data_size 会读到垃圾。walker 现在扫 chunk magic。

**测试:** 新增 `wx/src/cli/transcript_cache.rs` (138 行,3 unit tests:SHA-256 known-vector / roundtrip / corrupt-cache-misses-silently),audio.rs 14 tests,共 17 audio/cache tests + 历史 9 voices 端到端实测(冷转 30s vs cache 0.4s)。

## v1.13.24 — 2026-05-06

`wechat audio get` 修 codex round-3 review 1 BLOCKER + 2 SHOULD + 1 NICE。

**BLOCKER — JSON 模式 stderr 漏 raw 路径**(privacy regression):v1.13.22-23 在 stdout JSON 里 redact 了 `~/...` / `<account>/...`,但 sentinel 仍然带 raw `err.to_string()`,导致 `wechat ... 2>&1 | tee` 这种 capture 仍能在 stderr 看到 `/Users/leo/...` 完整路径。这次 sentinel 改用 redacted 后的 `printed` msg,stdout / stderr 在 JSON 模式下完全一致 redact。

**SHOULD — no-shards bail 路径无条件 redact**:文本模式 / `--reveal-path` 用户拿到 placeholder 路径无法 debug。这次跟 success 路径一致,读 `redact` bool 决定。

**SHOULD — redact_xwechat_account 末尾无斜杠 segment 漏**:类似 `unable to write "/x/xwechat_files/wxid_xyz"`(末尾无 `/`)的 error 字符串里 segment 仍然漏。terminator 现在接受 `/` + whitespace + 引号 `'`/`"` + 括号 `)`/`]` + `,` + `;` + 字符串结尾,任何边界都安全。

**NICE — multi-shard warning 始终 redact**:文本模式诊断不了哪个 shard。跟随 `redact` bool。

11 → 12 单元测试(replace 弱断言为强 assert + 加 quoted-path / end-of-string 边界用例)。

## v1.13.23 — 2026-05-06

`wechat audio get` 修 codex round-2 review 3 个 SHOULD-FIX(无 BLOCKER):

- **文本模式默认 reveal,JSON 模式默认 redact**:v1.13.22 文本模式也 redact `~/.wechat/...`,导致 `cat $(wechat audio get $X)` 拿不到能直接 cat 的路径。现在 reveal 决策由输出模式驱动:终端 / shell pipeline 用真路径,agent 消费的 JSON 默认 redact,`--reveal-path` 在 JSON 模式下强制完整路径。
- **`xwechat_files/<account>/` 通用 anchor**:v1.13.22 redact 实现假设 `db_dir` 以 `db_storage` 结尾,clone bundle / 自定义 db_dir 路径不命中 → fallback 到只 redact home,账号名仍漏。现在用纯字符串 anchor 找 `xwechat_files/<segment>/` 模式,任何布局都生效。
- **JSON error 路径也走 redact 管道**:v1.13.22 只在 success 路径 redact `AudioGetResult` 字段,error chain 里 `unable to write /Users/leo/.wechat/...` 这种消息照漏到 stdout。现在 JSON `error` 字段在 redact 模式下走 `redact_paths_in_message` 清洗。

新增 6 个单元测试覆盖 redact 行为(总 11 audio tests,11/11 pass)。

`with_auth` 在 audio::run 之前跑导致 subscription 错走纯 stderr 不出 JSON envelope 的 cross-cutting 问题待 v1.13.24+ 系统性修(image / sessions / contacts 都有同款问题,audio-only 修不彻底)。

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
