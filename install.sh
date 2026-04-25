#!/usr/bin/env bash
# install.sh — one-liner installer for wechat + wechatd
#
# Default: install to ~/.local/bin (no sudo). Override with INSTALL_DIR.
# Example: INSTALL_DIR=/usr/local/bin ./install.sh  (will use sudo if needed)
set -euo pipefail

REPO="leeguooooo/wechat-skill"
BINS=(wechat wechatd wechat-bridge)
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Verified WeChat builds — keep in sync with VERIFIED_DYLIB_FINGERPRINTS in
# wx/src/config.rs. Surfaced at install time so the user immediately knows
# whether their WeChat is in our calibrated set.
SUPPORTED_WECHAT_VERSIONS="4.0.1.52, 4.1.8"
SUPPORTED_WECHAT_BUILDS="36830, 37335, 37342"
WECHAT_DOWNLOAD_URL="https://mac.weixin.qq.com/en"

# ANSI color helpers — only emit if stderr/stdout is a tty so logs piped to
# files or grep stay readable.
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""
fi

info()    { printf '%s[install]%s %s\n'      "${C_CYAN}"  "${C_RESET}" "$1"; }
success() { printf '%s[install] ✓%s %s\n'    "${C_GREEN}" "${C_RESET}" "$1"; }
warn()    { printf '%s[install] !%s %s\n'    "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err()     { printf '%s[install] ✗%s %s\n'    "${C_RED}"   "${C_RESET}" "$1" >&2; }
step()    { printf '%s[install] →%s %s\n'    "${C_YELLOW}" "${C_RESET}" "$1"; }
cmd()     { printf '%s%s%s'                  "${C_CYAN}"  "$1"          "${C_RESET}"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "macOS only"
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  err "Apple Silicon only"
  exit 1
fi

mkdir -p "${INSTALL_DIR}" 2>/dev/null || true
STAGE=$(mktemp -d)
trap 'rm -rf "${STAGE}"' EXIT

# Resolve the latest release tag so we can fetch a versioned tarball +
# SHA256SUMS. Using /releases/latest/download/<file> would save one API
# round-trip, but following the redirect to a specific tag lets us
# print the version up front and also cleanly handles the case where
# the tarball name is version-suffixed.
LATEST_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
  "https://github.com/${REPO}/releases/latest" 2>/dev/null \
  | sed -E 's#.*/tag/##')
if [[ -z "${LATEST_TAG}" ]]; then
  err "无法解析最新 release tag（网络/GitHub API 不可达？）"
  exit 1
fi
info "最新版本：${LATEST_TAG}"

TARBALL="wechat-${LATEST_TAG}-darwin-arm64.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}"
info "下载 ${TARBALL}"
if ! curl -fsSL "${BASE_URL}/${TARBALL}" -o "${STAGE}/${TARBALL}"; then
  err "无法下载 ${TARBALL}，release 可能缺少此文件。"
  exit 1
fi
info "下载 SHA256SUMS"
if ! curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${STAGE}/SHA256SUMS.release"; then
  err "无法下载 SHA256SUMS，release 可能缺少此文件。"
  exit 1
fi

# Verify tarball integrity against the published SHA256SUMS. The
# published file lists per-binary hashes (wechat / wechatd), not the
# tarball, so we compute + check here explicitly before extracting.
info "校验 tarball SHA-256"
(
  cd "${STAGE}"
  tar xzf "${TARBALL}"
  # SHA256SUMS lives inside the tarball too — prefer that (maintainer
  # hashes) and cross-check against the separately-uploaded copy so a
  # tampered tarball can't ship mismatched hashes.
  if [[ ! -f SHA256SUMS ]]; then
    err "tarball 内缺少 SHA256SUMS，拒绝继续。"
    exit 1
  fi
  if ! cmp -s SHA256SUMS SHA256SUMS.release; then
    err "tarball 内 SHA256SUMS 与 release 附件不一致，拒绝继续。"
    exit 1
  fi
  if ! shasum -a 256 -c SHA256SUMS >/dev/null; then
    err "二进制 SHA-256 校验失败，拒绝继续。"
    exit 1
  fi
)
success "SHA-256 校验通过"

for BIN_NAME in "${BINS[@]}"; do
  SRC="${STAGE}/${BIN_NAME}"
  if [[ ! -s "${SRC}" ]]; then
    err "tarball 里缺少 ${BIN_NAME}"
    exit 1
  fi
  if [[ -w "${INSTALL_DIR}" ]]; then
    install -m 755 "${SRC}" "${INSTALL_DIR}/${BIN_NAME}"
  else
    info "把 ${BIN_NAME} 装到 ${INSTALL_DIR} 需要 sudo 授权……"
    sudo install -m 755 "${SRC}" "${INSTALL_DIR}/${BIN_NAME}"
  fi

  # Ad-hoc signed binary — 去掉 quarantine 避免 Gatekeeper 弹窗
  if [[ -w "${INSTALL_DIR}/${BIN_NAME}" ]]; then
    xattr -d com.apple.quarantine "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null || true
  else
    sudo xattr -d com.apple.quarantine "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null || true
  fi

  # Ad-hoc codesign with a stable identifier. Without this, every
  # upgrade gets a new content hash → TCC (Accessibility /
  # Input Monitoring) sees it as a NEW binary → user has to re-grant.
  # With a stable --identifier, some macOS builds will recognize the
  # new binary as a continuation of the previous grant and skip the
  # re-auth prompt. Not guaranteed (Sonoma+ is strict), but measurably
  # better than nothing.
  #
  # CRITICAL: only sign if the existing signature isn't already ours.
  # Re-running `codesign --force` on a binary that ALREADY has our
  # stable identifier still rotates the CDHash, which on Sonoma+ is
  # often enough to invalidate the existing TCC grant. So we skip the
  # sign when the binary's already correctly signed (e.g. user re-ran
  # install.sh with no upgrade). Customer report v1.10.32: every reinstall
  # was kicking them out of Accessibility because of unconditional
  # `--force` re-signing.
  IDENTIFIER="ai.wechatskill.${BIN_NAME}"
  EXISTING_IDENT=$(codesign -dv "${INSTALL_DIR}/${BIN_NAME}" 2>&1 \
    | awk -F'=' '/^Identifier=/ { print $2 }' | tr -d '\r')
  if [[ "${EXISTING_IDENT}" == "${IDENTIFIER}" ]]; then
    # Already signed by us with the same identifier — leave alone, TCC
    # is presumably still in effect.
    info "${BIN_NAME} 已 ad-hoc 签名 (${IDENTIFIER})，跳过 re-sign 保留 TCC 授权"
  else
    CODESIGN_ERR=$(mktemp "${TMPDIR:-/tmp}/wechat-install-codesign.XXXXXX")
    if [[ -w "${INSTALL_DIR}/${BIN_NAME}" ]]; then
      codesign --force --sign - --identifier "${IDENTIFIER}" \
        "${INSTALL_DIR}/${BIN_NAME}" 2>"${CODESIGN_ERR}"
      CS_RC=$?
    else
      sudo codesign --force --sign - --identifier "${IDENTIFIER}" \
        "${INSTALL_DIR}/${BIN_NAME}" 2>"${CODESIGN_ERR}"
      CS_RC=$?
    fi
    if [[ ${CS_RC} -ne 0 ]]; then
      warn "codesign 对 ${BIN_NAME} 失败（rc=${CS_RC}）："
      sed 's/^/    /' "${CODESIGN_ERR}" >&2
      warn "  binary 已安装但未签名；Accessibility TCC 可能每次升级都要重新勾"
    else
      # Verify signature was actually applied — catches "silent"
      # codesign no-ops where exit 0 but sig wasn't written.
      if ! codesign --verify "${INSTALL_DIR}/${BIN_NAME}" 2>>"${CODESIGN_ERR}"; then
        warn "codesign --verify ${BIN_NAME} 不通过 —— 签名可能没真正落到 binary 上"
        sed 's/^/    /' "${CODESIGN_ERR}" >&2
      fi
    fi
    rm -f "${CODESIGN_ERR}"
  fi

  success "已安装：${INSTALL_DIR}/${BIN_NAME}"
done
echo ""

# Stop any running wechatd so it picks up the new binary on next invocation.
# Otherwise a previously-spawned daemon keeps running old RPC code while the
# installed CLI is new — causes silent protocol mismatches (delivered_verified
# returning None because old daemon didn't serialize that field).
if pgrep -x wechatd >/dev/null 2>&1; then
  info "检测到旧 wechatd 还在跑，停掉好让新二进制下一次自动拉起"
  "${INSTALL_DIR}/wechat" daemon stop >/dev/null 2>&1 || true
  pkill -x wechatd 2>/dev/null || true
fi

# Reload bridge LaunchAgent so it (a) picks up the new binary and (b)
# re-reads the plist environment block.
#
# Why not `launchctl kickstart -k`: kickstart re-execs the process but
# does NOT re-parse the plist's EnvironmentVariables — env only refreshes
# on a fresh `bootstrap` after `bootout`. v1.10.30 customers hit exactly
# this: they edited the plist, ran kickstart, plist showed correct env,
# but the actual running process inherited the OLD env and the new
# `WECHAT_BRIDGE_GROUP_MENTION_ONLY` flag never made it.
#
# bootout + bootstrap is idempotent + ~2s overhead. Cheaper than the
# half-hour of confused debugging it saves.
#
# CRITICAL: kill any stray manually-launched wechat-bridge first. Real
# customer report (v1.10.31 era): they had a hand-started bridge from
# weeks ago holding port 18400. LaunchAgent got stuck in "spawn
# scheduled / active=0" indefinitely because bind failed silently. The
# stray bridge had no plist env, no v1.10.30 codesign, no v1.10.31 logs.
# Customer thought new install was running but actually nothing changed.
# install.sh must own this — clean up rogue processes before bootstrap.
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/ai.wechat.bridge.plist"
STRAY_PIDS=$(pgrep -f "${INSTALL_DIR}/wechat-bridge" 2>/dev/null || true)
if [[ -n "${STRAY_PIDS}" ]]; then
  info "杀掉旧 wechat-bridge 进程（pid: ${STRAY_PIDS}），让 LaunchAgent 重新接管"
  echo "${STRAY_PIDS}" | xargs kill 2>/dev/null || true
  sleep 2
  # SIGKILL fallback if any survived TERM
  STRAY_PIDS=$(pgrep -f "${INSTALL_DIR}/wechat-bridge" 2>/dev/null || true)
  if [[ -n "${STRAY_PIDS}" ]]; then
    echo "${STRAY_PIDS}" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi
fi
if [[ -f "${LAUNCHAGENT_PLIST}" ]]; then
  info "重新加载 LaunchAgent ai.wechat.bridge（bootout + bootstrap，刷新 env）"
  launchctl bootout "gui/$(id -u)/ai.wechat.bridge" 2>/dev/null || true
  sleep 1
  launchctl bootstrap "gui/$(id -u)" "${LAUNCHAGENT_PLIST}" 2>/dev/null || true
  sleep 2
  # Verify the running bridge is actually launchd-managed (not another
  # stray manually-launched copy). If launchd's job is "spawn scheduled"
  # but never reaches "running", port 18400 is probably blocked.
  RUNNING_PID=$(pgrep -f "${INSTALL_DIR}/wechat-bridge" 2>/dev/null | head -1)
  if [[ -n "${RUNNING_PID}" ]]; then
    success "LaunchAgent 已接管 (pid=${RUNNING_PID})"
  else
    LD_STATE=$(launchctl print "gui/$(id -u)/ai.wechat.bridge" 2>/dev/null \
      | grep -E "^\s+state\s*=" | head -1 | awk '{print $3}')
    warn "LaunchAgent 启动后看不到 wechat-bridge 进程 (state=${LD_STATE:-unknown})"
    warn "  常见原因：端口 18400 被另一进程占用 / plist 配置错"
    warn "  排错: lsof -nP -iTCP:18400 | grep LISTEN"
  fi
elif launchctl list 2>/dev/null | grep -q ai.wechat.bridge; then
  info "LaunchAgent 注册但 plist 不在标准路径，用 kickstart 重启"
  launchctl kickstart -k "gui/$(id -u)/ai.wechat.bridge" 2>/dev/null || true
fi

# Post-install TCC sanity check. wechat-bridge 1.10.30+ supports
# --check-trust probe mode: exits 0 if Accessibility granted, 1 if not.
# Retry a few times with short backoff: right after `codesign --force`
# and `launchctl kickstart`, macOS TCC cache can briefly report stale
# state. A false-negative warning right on install would spook the
# customer unnecessarily.
TCC_OK=0
for attempt in 1 2 3; do
  if "${INSTALL_DIR}/wechat-bridge" --check-trust >/dev/null 2>&1; then
    TCC_OK=1
    break
  fi
  sleep 1
done
if [[ ${TCC_OK} -eq 1 ]]; then
  success "Accessibility TCC: 已授权 ✓"
  echo ""
else
  # TCC missing — auto-trigger the GUI windows so user can't miss the step.
  # Many customers skim past a single yellow warn line and end up with a
  # silently broken send path. Open the Accessibility pane + a Finder
  # window selecting wechat-bridge, RIGHT NOW, before they close the
  # terminal. Then print a big red banner with the exact 3 actions.
  echo ""
  echo ""
  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_RED}" "${C_RESET}"
  printf '%s🛑 STOP — Accessibility 授权没勾，bridge 无法发消息！%s\n' "${C_RED}" "${C_RESET}"
  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_RED}" "${C_RESET}"
  echo ""
  echo "macOS Sonoma+ 要求 wechat-bridge 在「辅助功能」清单里。没勾的话："
  echo "  • wechat send 看似成功但消息其实没发出"
  echo "  • bridge 启动直接 exit 1，hermes / agent 平台拿不到数据"
  echo ""
  echo "我现在帮你打开两个窗口（30 秒动作）："
  echo "  1. System Settings → 隐私与安全 → 辅助功能（要勾的清单）"
  echo "  2. Finder 高亮选中 wechat-bridge（你拖到清单里的源文件）"
  echo ""
  # Best-effort GUI open — these are fire-and-forget; failures don't
  # block the install (some CI/headless scenarios won't have a GUI).
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
  sleep 1
  open -R "${INSTALL_DIR}/wechat-bridge" 2>/dev/null || true
  echo "已打开。请：把 Finder 里的 wechat-bridge 拖到设置窗里 + 打开右侧开关。"
  echo ""
  printf '%s拖完后跑一条命令验证 + 重启 bridge：%s\n' "${C_YELLOW}" "${C_RESET}"
  echo ""
  printf '   %s%s wechat doctor --fix-tcc%s\n' "${C_GREEN}" "${INSTALL_DIR}" "${C_RESET}"
  echo ""
  echo "（这条命令会再次开窗口 + 验证授权 + 重启 LaunchAgent，最多 30 秒。"
  echo " 如果你已经在前两步窗口里勾完了，跑它只是为了 verify + restart bridge。）"
  echo ""
  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_RED}" "${C_RESET}"
  echo ""
fi

# Print installed CLI version + the supported WeChat matrix so the user
# immediately knows what they got and what their WeChat needs to look like.
INSTALLED_VER="(unknown)"
if [[ -x "${INSTALL_DIR}/wechat" ]]; then
  INSTALLED_VER=$("${INSTALL_DIR}/wechat" --version 2>/dev/null | awk '{print $2}')
  [[ -z "${INSTALLED_VER}" ]] && INSTALLED_VER="(unknown)"
fi
INSTALLED_DAEMON_VER="(unknown)"
if [[ -x "${INSTALL_DIR}/wechatd" ]]; then
  INSTALLED_DAEMON_VER=$("${INSTALL_DIR}/wechatd" --version 2>/dev/null | awk '{print $2}')
  [[ -z "${INSTALLED_DAEMON_VER}" ]] && INSTALLED_DAEMON_VER="(unknown)"
fi

# Best-effort detect locally-installed WeChat version+build for the
# "do they match" headline.
DETECTED_WECHAT_VERSION=""
DETECTED_WECHAT_BUILD=""
if [[ -f /Applications/WeChat.app/Contents/Info.plist ]]; then
  DETECTED_WECHAT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    /Applications/WeChat.app/Contents/Info.plist 2>/dev/null || echo "")
  DETECTED_WECHAT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    /Applications/WeChat.app/Contents/Info.plist 2>/dev/null || echo "")
fi
WECHAT_DETECTED_LINE=""
if [[ -n "${DETECTED_WECHAT_VERSION}" && -n "${DETECTED_WECHAT_BUILD}" ]]; then
  if echo "${SUPPORTED_WECHAT_BUILDS}" | grep -qw "${DETECTED_WECHAT_BUILD}" \
     && echo "${SUPPORTED_WECHAT_VERSIONS}" | grep -qw "${DETECTED_WECHAT_VERSION}"; then
    WECHAT_DETECTED_LINE="${C_GREEN}✓${C_RESET} 检测到 ${DETECTED_WECHAT_VERSION} (build ${DETECTED_WECHAT_BUILD})，在已验证清单内"
  else
    WECHAT_DETECTED_LINE="${C_YELLOW}!${C_RESET} 检测到 ${DETECTED_WECHAT_VERSION} (build ${DETECTED_WECHAT_BUILD})，${C_YELLOW}不在已验证清单${C_RESET}"
  fi
fi

printf '%s版本信息%s\n' "${C_BOLD}" "${C_RESET}"
printf '  %s%-22s%s %s\n' "${C_DIM}" "wechat (CLI)" "${C_RESET}" "${INSTALLED_VER}"
printf '  %s%-22s%s %s\n' "${C_DIM}" "wechatd (daemon)" "${C_RESET}" "${INSTALLED_DAEMON_VER}"
printf '  %s%-22s%s %s\n' "${C_DIM}" "支持的 WeChat 版本" "${C_RESET}" "${SUPPORTED_WECHAT_VERSIONS}"
printf '  %s%-22s%s %s\n' "${C_DIM}" "支持的 WeChat build" "${C_RESET}" "${SUPPORTED_WECHAT_BUILDS}"
if [[ -n "${WECHAT_DETECTED_LINE}" ]]; then
  printf '  %s%-22s%s %b\n' "${C_DIM}" "本机 WeChat" "${C_RESET}" "${WECHAT_DETECTED_LINE}"
else
  printf '  %s%-22s%s %s未检测到 /Applications/WeChat.app%s\n' "${C_DIM}" "本机 WeChat" "${C_RESET}" "${C_YELLOW}" "${C_RESET}"
fi
printf '  %s%-22s%s %s\n' "${C_DIM}" "WeChat 下载（验证版）" "${C_RESET}" "${WECHAT_DOWNLOAD_URL}"
echo ""

# Auto-add INSTALL_DIR to PATH if missing. Idempotent: only inserts if
# the rc file doesn't already reference the directory.
path_export_line() {
  printf 'export PATH="%s:$PATH"  # added by wechat-skill installer' "${1}"
}

ensure_rc_has_path() {
  local rc_path="$1"
  local install_dir="$2"
  [[ -f "$rc_path" ]] || touch "$rc_path"
  if grep -q "${install_dir}" "$rc_path" 2>/dev/null; then
    return 1  # already present
  fi
  printf '\n%s\n' "$(path_export_line "$install_dir")" >> "$rc_path"
  return 0
}

ensure_fish_has_path() {
  local install_dir="$1"
  local fish_conf="$HOME/.config/fish/config.fish"
  mkdir -p "$(dirname "$fish_conf")"
  [[ -f "$fish_conf" ]] || touch "$fish_conf"
  if grep -q "${install_dir}" "$fish_conf" 2>/dev/null; then
    return 1
  fi
  printf '\n# added by wechat-skill installer\nfish_add_path %s\n' "$install_dir" >> "$fish_conf"
  return 0
}

case ":$PATH:" in
  *":${INSTALL_DIR}:"*)
    # Already on PATH this session.
    ;;
  *)
    # Detect user's shell from $SHELL and auto-append to the matching rc
    # file. Tell them exactly what we changed + how to activate in the
    # current shell without a new terminal.
    current_shell_name="$(basename "${SHELL:-}")"
    added_file=""
    case "$current_shell_name" in
      bash)
        if ensure_rc_has_path "$HOME/.bashrc" "$INSTALL_DIR"; then
          added_file="$HOME/.bashrc"
        fi
        ;;
      zsh)
        if ensure_rc_has_path "$HOME/.zshrc" "$INSTALL_DIR"; then
          added_file="$HOME/.zshrc"
        fi
        ;;
      fish)
        if ensure_fish_has_path "$INSTALL_DIR"; then
          added_file="$HOME/.config/fish/config.fish"
        fi
        ;;
      *)
        # Unknown shell — fall back to old advice.
        ;;
    esac
    if [[ -n "$added_file" ]]; then
      success "已把 ${INSTALL_DIR} 加到 ${added_file}"
      printf '  %s要在当前 shell 立刻生效%s\n' "${C_DIM}" "${C_RESET}"
      if [[ "$current_shell_name" == "fish" ]]; then
        printf '  %s\n\n' "$(cmd "source $added_file")"
      else
        printf '  %s\n\n' "$(cmd "source $added_file")"
      fi
    else
      warn "${INSTALL_DIR} 不在 PATH 中，且自动追加失败（未识别的 shell 或 rc 已含相似内容）。手动加："
      printf '\n'
      printf '  %s# bash / zsh%s\n' "${C_DIM}" "${C_RESET}"
      printf '  %s\n' "$(cmd "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc")"
      printf '\n'
      printf '  %s# fish%s\n' "${C_DIM}" "${C_RESET}"
      printf '  %s\n' "$(cmd "fish_add_path $INSTALL_DIR")"
      printf '\n'
    fi
    ;;
esac

printf '%s下一步 —— 按顺序执行：%s\n\n' "${C_BOLD}" "${C_RESET}"

step "$(cmd 'wechat auth activate <激活码>')"
printf '    %sv1.9.1 起需先激活订阅。无激活码？跟 Telegram 机器人申请：%s\n' "${C_DIM}" "${C_RESET}"
printf '    %s频道公告：https://t.me/+4PuAO3lB9R82ZTVh%s\n' "${C_DIM}" "${C_RESET}"
printf '    %s申请机器人：https://t.me/WechatCliBot （/start 看说明，激活码走人工审核，⚠️ 仅个人/非商业用途）%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd '授权 wechat-bridge 进「辅助功能」（首次必做，不做 send 静默失败）')"
printf '    %smacOS Sonoma+ 下跨进程合成键盘事件需要 TCC Accessibility 授权。一条龙：%s\n' "${C_DIM}" "${C_RESET}"
printf '    %s  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"%s\n' "${C_DIM}" "${C_RESET}"
printf '    %s  open "%s"%s   # Finder 打开，把 wechat-bridge 拖进设置窗\n' "${C_DIM}" "${INSTALL_DIR}" "${C_RESET}"
printf '    %s路径就是：%s%s/wechat-bridge%s\n' "${C_DIM}" "${C_CYAN}" "${INSTALL_DIR}" "${C_RESET}"
printf '    %s勾选 ✓ 后，已运行的 bridge 要重启才继承授权：pkill wechat-bridge（下次 send 自动重拉）%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd 'wechat doctor')"
printf '    %s体检：lldb / WeChat / 签名 / key / daemon / dylib 指纹 / ax_trusted 一行看完。%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd 'wechat init')"
printf '    %s重启 WeChat 一次，从登录瞬间抓取数据库解密 key。WeChat 重启后请立刻点「进入 WeChat」或扫码登录，否则断点不会触发。每次 WeChat 重启后需要重新跑一次。%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd 'wechat send "来自 CLI 的消息" filehelper')"
printf '    %s发消息。daemon 自动起，热路径约 700ms。%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd 'wechat auth status')"
printf '    %s查订阅 tier + 剩余天数。到期后 `wechat auth renew` 看如何重新提交审核。%s\n\n' "${C_DIM}" "${C_RESET}"

step "$(cmd 'wechat doctor')  ${C_DIM}（任何时候出问题先跑这个）${C_RESET}"
