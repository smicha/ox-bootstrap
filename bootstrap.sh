#!/usr/bin/env bash
# bootstrap.sh -- public entry point for a private dotfiles repo (smicha/ox):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/smicha/ox-bootstrap/main/bootstrap.sh)"
# Installs what is needed to reach the private repo (Homebrew + Xcode CLT on
# macOS; git, curl, gh on Linux/WSL), signs in to GitHub, clones over HTTPS,
# and hands off to its install.sh, which continues the same progress display.
# Idempotent. Bash 3.2 and 5. Env: OX_DIR, OX_REF, OX_DRY_RUN, OX_VERBOSE,
# OX_SKIP_GITHUB, OX_GH_AUTH, OX_GH_TOKEN_FILE, OX_GH_TOKEN_STDIN,
# OX_REPO_SLUG, OX_REPO_URL; other OX_* pass through to install.sh.
set -euo pipefail

SLUG="${OX_REPO_SLUG:-smicha/ox}"
GH_USER="${OX_PERSONAL_GITHUB_USER:-${SLUG%%/*}}"
REPO_URL="${OX_REPO_URL:-https://github.com/$SLUG.git}"
REF="${OX_REF:-main}"
DRY="${OX_DRY_RUN:-0}"
GHDIR="$HOME/.config/gh-personal"
SCOPES="admin:public_key,read:org,repo,gist,workflow"
NEED_SCOPES="repo read:org gist workflow admin:public_key"
BREW_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
AGENT_VARS="AI_AGENT AGENT CLAUDECODE CLAUDE_CODE CLAUDE_CODE_IS_COWORK CODEX_SANDBOX CODEX_CI CODEX_THREAD_ID GEMINI_CLI COPILOT_CLI OPENCODE ANTIGRAVITY_AGENT AUGMENT_AGENT REPL_ID CURSOR_TRACE_ID CURSOR_AGENT CURSOR_EXTENSION_HOST_ROLE GOOSE_PROVIDER"
# Same step plan as ox scripts/ox-progress.sh (install.sh rewrites it)
PLAN="platform:Detect platform|questions:Questions|pkgmgr:Package manager|core:Core tools|gh-personal:GitHub sign-in (personal)|clone:Clone ox|devtools:Dev tools|terminal:Terminal and fonts|ssh-keys:SSH keys|link:Link dotfiles|tmux:tmux plugins|gh-work:GitHub sign-in (work)|keys:Key upload and remote|health:Health check"
export OX_ROOT_PID=$$
KEEPALIVE=""; STEP=""; WS=""; HANDED=""; START="$(date +%s)"

# -- output: command output goes to the log; fd 7 is the user's display ------
log()  { printf '\n==> %s\n' "$1"; }
ok()   { printf '  ok  %s (%s)\n' "$1" "${2:-already set up}"; w ok "$1"; }
chg()  { printf '  %s  %s\n' "$([ "$DRY" = 1 ] && echo 'would change' || echo changed)" "$1"; w changed "$1"; }
note() { printf '  note  %s\n' "$1"; }
die()  { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
has()  { command -v "$1" >/dev/null 2>&1; }
tty_ok() { { (exec </dev/tty) 2>/dev/null; }; }
fd7()  { { true >&7; } 2>/dev/null; }
say()  { if tty_ok; then printf '%s' "$1" >/dev/tty; elif fd7; then printf '%s' "$1" >&7; else printf '%s' "$1" >&2; fi; }
out()  { if fd7; then printf '%s' "$1" >&7; else printf '%s' "$1" >&2; fi; }
fmt()  { if [ "$1" -ge 60 ]; then printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi; }
w()    { [ -n "${OX_RUN_STATE:-}" ] || return 0; local IFS=$'\t'; printf '%s\n' "$*" >> "$OX_RUN_STATE"; }
# gh without the variables it uses to detect coding agents
xgh() { local v a=(); for v in $AGENT_VARS GH_TOKEN GITHUB_TOKEN; do a+=(-u "$v"); done; env "${a[@]}" GH_CONFIG_DIR="$GHDIR" gh "$@"; }

# -- progress (same state format and display as ox scripts/ox-progress.sh) ----
setup_run() {
  local d i=0 e
  if [ "$(uname -s)" = Darwin ]; then d="$HOME/Library/Logs"; OX_RUN_LOG="$d/ox-install.log"
  else d="${XDG_STATE_HOME:-$HOME/.local/state}/ox"; OX_RUN_LOG="$d/install.log"; fi
  mkdir -p "$d"
  if [ "${OX_VERBOSE:-0}" = 1 ]; then OX_PROGRESS_MODE="verbose"
  elif [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then OX_PROGRESS_MODE="tty"; else OX_PROGRESS_MODE="plain"; fi
  OX_COLOR=0; if [ "${OX_PROGRESS_MODE:-plain}" = tty ] && [ -z "${NO_COLOR:-}" ]; then OX_COLOR=1; fi
  exec 7>&1
  if [ "$OX_PROGRESS_MODE" = verbose ]; then exec > >(tee -a "$OX_RUN_LOG" >&7) 2>&1; else exec >>"$OX_RUN_LOG" 2>&1; fi
  OX_RUN_STATE="$(mktemp "$d/ox-run.XXXXXX")"
  export OX_RUN_STATE OX_RUN_LOG OX_PROGRESS_MODE OX_COLOR
  printf '\n===== ox bootstrap %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  w run "$START"; w plan-reset
  for e in $(echo "$PLAN" | tr ' |' '~ '); do i=$((i + 1)); w plan "$i" "${e%%:*}" "$(echo "${e#*:}" | tr '~' ' ')"; done
}
info() { awk -F'\t' -v id="$1" '$1 == "plan" { n++; if ($3 == id) { i = $2; s = $4 } } END { printf "%d/%d\t%s", i, n, s }' "$OX_RUN_STATE"; }
bar() {
  [ "${OX_PROGRESS_MODE:-plain}" = tty ] && [ -n "$STEP" ] || return 0
  local n d f b="" k=0 inf
  n="$(grep -c '^plan	' "$OX_RUN_STATE")"; d="$(awk -F'\t' '$1 == "end" && !s[$2]++ { c++ } END { print c + 0 }' "$OX_RUN_STATE")"
  f=$((d * 20 / n)); inf="$(info "$STEP")"
  while [ "$k" -lt 20 ]; do if [ "$k" -lt "$f" ]; then b="$b="; elif [ "$k" -eq "$f" ]; then b="$b>"; else b="$b "; fi; k=$((k + 1)); done
  out "$(printf '\r\033[K[%s] %5s  %s ... %s' "$b" "${inf%%	*}" "${inf#*	}" "$(fmt $(( $(date +%s) - ST0 )))")"
}
sb() {
  [ -n "${OX_RUN_STATE:-}" ] || return 0
  STEP="$1"; ST0="$(date +%s)"; w begin "$1" "$ST0" "$(wc -l < "$OX_RUN_LOG" | tr -d ' ')"
  local inf; inf="$(info "$1")"
  if [ "${OX_PROGRESS_MODE:-plain}" = tty ]; then bar; else out "$(printf '[%5s] %s ...' "${inf%%	*}" "${inf#*	}")"$'\n'; fi
}
se() {
  local st="${1:-}" nt="${2:-}" inf d sym
  [ -n "${OX_RUN_STATE:-}" ] && [ -n "$STEP" ] || return 0
  if [ -z "$st" ]; then
    d="$(awk -F'\t' -v id="$STEP" '{ l[NR] = $0 } $1 == "begin" && $2 == id { f = NR } END { for (i = f + 1; i <= NR; i++) { split(l[i], x, "\t"); if (x[1] == "changed") { c++; if (n == "") n = x[2] } } print (c ? "changed" : "ok") "\t" n }' "$OX_RUN_STATE")"
    st="${d%%	*}"; [ -n "$nt" ] || nt="${d#*	}"
  fi
  w end "$STEP" "$(date +%s)" "$st" "$nt"
  inf="$(info "$STEP")"; d="$(fmt $(( $(date +%s) - ST0 )))"
  case "$st" in ok) sym="+"; st="already set up" ;; changed) sym="~" ;; skipped) sym="-" ;; *) sym="x" ;; esac
  if [ "${OX_COLOR:-0}" = 1 ]; then
    case "$sym" in +) sym=$'\033[32m\xe2\x9c\x93\033[0m' ;; "~") sym=$'\033[33m~\033[0m' ;; -) sym=$'\033[2m-\033[0m' ;; x) sym=$'\033[31m\xe2\x9c\x97\033[0m' ;; esac
  fi
  if [ "${OX_PROGRESS_MODE:-plain}" = tty ]; then out "$(printf '\r\033[K  %s %-26s %-15s %7s  %s' "$sym" "${inf#*	}" "$st" "$d" "$nt")"$'\n'
  else out "$(printf '[%5s] %s: %s (%s)%s' "${inf%%	*}" "${inf#*	}" "$st" "$d" "${nt:+ -- $nt}")"$'\n'; fi
  STEP=""
}
pz() { WS="$(date +%s)"; [ "${OX_PROGRESS_MODE:-plain}" = tty ] && out $'\r\033[K'; return 0; }
rz() { [ -n "$WS" ] && w wait $(( $(date +%s) - WS )); WS=""; bar; }
# Summary when the bootstrap itself stops (install.sh prints the full one)
fin() {
  local rc=$? t from res=failed
  [ -z "$HANDED" ] && [ -n "${OX_RUN_STATE:-}" ] || return 0
  [ "$rc" = 130 ] && res=interrupted
  t=$(( $(date +%s) - START ))
  if [ -n "$STEP" ]; then
    from="$(awk -F'\t' -v id="$STEP" '$1 == "begin" && $2 == id { l = $4 } END { print l + 1 }' "$OX_RUN_STATE")"
    se "$res" "exit $rc"
    out "    last 30 lines (full log: $OX_RUN_LOG):"$'\n'"$(tail -n +"$from" "$OX_RUN_LOG" | tail -n 30 | sed 's/^/    | /')"$'\n'
  fi
  out $'\n'"Setup stopped after $(fmt "$t") (bootstrap $res). Re-run the same command; finished steps are skipped."$'\n'"  Log: $OX_RUN_LOG"$'\n'
  mkdir -p "$HOME/.local/state/ox"
  printf '%s  %-28s  total %-8s  bootstrap %s\n' "$(date '+%Y-%m-%d %H:%M')" "${LABEL:-unknown}" "$(fmt "$t")" "$res" >> "$HOME/.local/state/ox/runs.log"
  rm -f "$OX_RUN_STATE"; HANDED=1
}
trap 'fin; [ -n "$KEEPALIVE" ] && kill "$KEEPALIVE" 2>/dev/null; true' EXIT
trap 'exit 130' INT TERM

# -- platform -----------------------------------------------------------------
osr() { [ -r /etc/os-release ] && sed -n "s/^$1=//p" /etc/os-release | head -n 1 | tr -d '"'; }
detect() {
  WSL=0
  if [ "$(uname -s)" = Darwin ]; then OS=macos; PKG=brew; LABEL="macOS $(sw_vers -productVersion) $(uname -m)"
  else
    OS=linux
    case " $(osr ID) $(osr ID_LIKE) " in
      *" debian "*|*" ubuntu "*) PKG=apt ;;
      *" fedora "*|*" rhel "*)   PKG=dnf ;;
      *" arch "*)                PKG=pacman ;;
      *) die "unsupported Linux distribution: $(osr ID)" ;;
    esac
    if grep -qi microsoft /proc/version 2>/dev/null; then WSL=1; fi
    LABEL="$(osr PRETTY_NAME)"; [ "$WSL" = 1 ] && LABEL="$LABEL (WSL2)"; LABEL="$LABEL $(uname -m)"
  fi
}

# sudo only right before a step that needs it; kept alive until exit
need_sudo() {
  [ "$(id -u)" = 0 ] || [ "$DRY" = 1 ] && return 0
  if ! sudo -n true 2>/dev/null; then pz; say "$(printf '\n  Your password is needed for: %s\n' "$1")"; sudo -v || die "sudo authentication failed"; rz; fi
  [ -n "$KEEPALIVE" ] && return 0
  ( while kill -0 "$OX_ROOT_PID" 2>/dev/null; do sudo -n true 2>/dev/null || exit 0; sleep 50; done ) >/dev/null 2>&1 &
  KEEPALIVE=$!
}
root() { if [ "$(id -u)" = 0 ]; then run "$@"; else run sudo "$@"; fi; }

# -- clone location -----------------------------------------------------------
# shellcheck disable=SC2088  # matching a literal ~ typed by the user
expand() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#"~/"}" ;; /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
where() {
  local saved="" ans=""
  [ -f "$HOME/.config/ox/repo-path" ] && saved="$(cat "$HOME/.config/ox/repo-path")"
  if [ -n "${OX_DIR:-}" ]; then OX_DIR="$(expand "$OX_DIR")"
  elif [ -n "$saved" ] && [ -d "$saved/.git" ]; then OX_DIR="$saved"
  elif [ -d "$HOME/.ox/.git" ] || ! tty_ok; then OX_DIR="$HOME/.ox"
  else pz; say "$(printf '  Where should %s live? [~/.ox]: ' "$SLUG")"; IFS= read -r ans </dev/tty || true; rz; OX_DIR="$(expand "${ans:-~/.ox}")"; fi
  OX_DIR="${OX_DIR%/}"
  ok "clone location $OX_DIR"
}

# -- basics -------------------------------------------------------------------
brew_bin() { local p; for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew "$HOME/.linuxbrew"; do [ -x "$p/bin/brew" ] && { echo "$p/bin/brew"; return 0; }; done; return 1; }
pkgmgr_macos() {
  local brew line
  if brew="$(brew_bin)"; then ok "Homebrew"
  elif [ "$DRY" = 1 ]; then chg "Homebrew (NONINTERACTIVE, installs the Xcode CLT)"; return 0
  else need_sudo "installing Homebrew and the Xcode Command Line Tools"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$BREW_URL")" || die "Homebrew install failed"
    brew="$(brew_bin)" || die "brew not found after install"; chg "Homebrew"; fi
  eval "$("$brew" shellenv)"
  line="eval \"\$($brew shellenv)\""
  if grep -qxF "$line" "$HOME/.zprofile" 2>/dev/null; then ok "brew shellenv in ~/.zprofile"
  else [ "$DRY" = 1 ] || echo "$line" >> "$HOME/.zprofile"; chg "brew shellenv in ~/.zprofile"; fi
}
core_macos() {
  if [ "$DRY" != 1 ] || brew_bin >/dev/null; then xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools missing; run xcode-select --install and re-run"; fi
  if has gh; then ok "gh"; else run brew install gh || die "brew install gh failed"; chg "gh"; fi
}
core_linux() {
  local miss="" t
  for t in git curl; do has "$t" || miss="$miss $t"; done
  if [ -n "$miss" ]; then
    need_sudo "installing$miss"
    # shellcheck disable=SC2086  # word list on purpose
    case "$PKG" in
      apt) root env DEBIAN_FRONTEND=noninteractive apt-get update -qq && root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $miss ca-certificates ;;
      dnf) root dnf install -y -q $miss ;;
      pacman) root pacman -Syu --needed --noconfirm $miss ;;
    esac || die "installing$miss failed"
    chg "packages:$miss"
  else ok "git, curl"; fi
  if has gh; then ok "gh"; return 0; fi
  need_sudo "installing gh from GitHub's package repository"
  case "$PKG" in
    apt)
      local key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
      [ -s "$key" ] || { root mkdir -p -m 755 /etc/apt/keyrings; [ "$DRY" = 1 ] || curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | root tee "$key" >/dev/null; root chmod go+r "$key"; }
      [ -s /etc/apt/sources.list.d/github-cli.list ] || { [ "$DRY" = 1 ] || echo "deb [arch=$(dpkg --print-architecture) signed-by=$key] https://cli.github.com/packages stable main" | root tee /etc/apt/sources.list.d/github-cli.list >/dev/null; }
      root env DEBIAN_FRONTEND=noninteractive apt-get update -qq && root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh ;;
    dnf)
      [ -s /etc/yum.repos.d/gh-cli.repo ] || { [ "$DRY" = 1 ] || curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo | root tee /etc/yum.repos.d/gh-cli.repo >/dev/null; }
      root dnf install -y -q gh ;;
    pacman) root pacman -S --needed --noconfirm github-cli ;;
  esac || die "installing gh failed"
  chg "gh"
}

# -- GitHub sign-in (same flow as ox scripts/gh-signin.sh) --------------------
# Token for the expected user only, handed to gh through the environment of a subshell
login_is() { ( GH_TOKEN="$(xgh auth token -h github.com -u "$GH_USER" 2>/dev/null)" || exit 0
  for v in $AGENT_VARS; do unset "$v"; done; export GH_TOKEN; gh api user --jq .login 2>/dev/null ); }
missing_scopes() {
  local hdr have s miss=""
  hdr="$(xgh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: *//p' | head -n 1)"
  if [ -z "$hdr" ]; then xgh api user/keys >/dev/null 2>&1 || miss="Git SSH keys (read and write)"
  else
    have=" $(echo "$hdr" | tr -d ' ' | tr ',' ' ') "
    for s in $NEED_SCOPES; do case "$have" in *" $s "*) ;; *) miss="$miss $s" ;; esac; done
  fi
  xgh api "repos/$SLUG" >/dev/null 2>&1 || miss="$miss read-access-to-$SLUG"
  echo "${miss# }"
}
read_token() {
  TOKEN=""
  if [ -n "${OX_GH_TOKEN_FILE:-}" ]; then TOKEN="$(tr -d '[:space:]' < "$OX_GH_TOKEN_FILE")"
  elif [ "${OX_GH_TOKEN_STDIN:-0}" = 1 ]; then TOKEN="$(tr -d '[:space:]')"
  else
    say "$(printf '\n  Create a token at https://github.com/settings/tokens\n    Classic: scopes repo, read:org, gist, workflow, admin:public_key\n    Fine-grained: Contents read on %s, account permission "Git SSH keys" read and write\n  Paste the token (input hidden): ' "$SLUG")"
    IFS= read -rs TOKEN </dev/tty || true; say $'\n'
  fi
  [ -n "$TOKEN" ] || die "no token provided"
}
signin() {
  local method="${OX_GH_AUTH:-}" c miss
  if [ "${OX_SKIP_GITHUB:-0}" = 1 ]; then se skipped "OX_SKIP_GITHUB=1"; return 0; fi
  if [ "$(login_is)" = "$GH_USER" ]; then ok "GitHub sign-in ($GH_USER)"; se ok "$GH_USER"; return 0; fi
  [ "$DRY" = 1 ] && { chg "GitHub sign-in ($GH_USER)"; se; return 0; }
  mkdir -p "$GHDIR"
  [ -n "${OX_GH_TOKEN_FILE:-}${OX_GH_TOKEN_STDIN:-}" ] && method="${method:-token}"
  pz
  if [ -z "$method" ]; then
    tty_ok || die "no terminal to ask how to sign in -- set OX_GH_AUTH=browser|token"
    say "$(printf '\n  How do you want to sign in to GitHub (%s)?\n    1) Browser login (recommended)\n    2) Personal access token (PAT)\n  Choice [1]: ' "$GH_USER")"
    IFS= read -r c </dev/tty || true
    if [ "$c" = 2 ]; then method=token; else method=browser; fi
  fi
  while true; do
    if [ "$method" = token ]; then
      read_token
      printf '%s\n' "$TOKEN" | xgh auth login -h github.com --git-protocol https --with-token || { TOKEN=""; die "token sign-in failed"; }
      TOKEN=""; unset TOKEN
    else
      if [ "$WSL" = 1 ] && has wslview; then export GH_BROWSER=wslview
      elif [ "$OS" = linux ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        say $'  No browser here: open https://github.com/login/device on any device and enter the code below (option 2 accepts a token instead)\n'
        export GH_BROWSER=true
      fi
      # A throwaway global gitconfig that already names gh keeps gh from
      # offering to edit the real one; the device code goes to the terminal
      c="$(mktemp)"; printf '[credential "https://github.com"]\n\thelper = !gh auth git-credential\n' > "$c"
      if tty_ok; then GIT_CONFIG_GLOBAL="$c" xgh auth login -h github.com --git-protocol https --web --skip-ssh-key --scopes "$SCOPES" </dev/tty >/dev/tty 2>&1 || { rm -f "$c"; die "browser sign-in failed"; }
      else GIT_CONFIG_GLOBAL="$c" xgh auth login -h github.com --git-protocol https --web --skip-ssh-key --scopes "$SCOPES" >&7 2>&1 || { rm -f "$c"; die "browser sign-in failed"; }; fi
      rm -f "$c"
    fi
    c="$(xgh api user --jq .login 2>/dev/null || true)"
    [ "$c" = "$GH_USER" ] || { [ -n "$c" ] && xgh auth logout -h github.com -u "$c" >/dev/null 2>&1; die "signed in as '${c:-unknown}', expected '$GH_USER'"; }
    miss="$(missing_scopes)"
    [ -z "$miss" ] && break
    say "  ! the sign-in is missing: $miss"$'\n'
    { [ -z "${OX_GH_TOKEN_FILE:-}${OX_GH_TOKEN_STDIN:-}" ] && tty_ok; } || die "fix the token permissions ($miss) and re-run"
    say $'  1) Enter a different token\n  2) Use browser login instead\n  Choice [2]: '
    IFS= read -r c </dev/tty || true
    if [ "$c" = 1 ]; then method=token; else method=browser; fi
  done
  rz
  chg "GitHub sign-in ($GH_USER, $method)"; se
}

# -- clone or update ----------------------------------------------------------
xgit() { if [ "${OX_SKIP_GITHUB:-0}" = 1 ] || [ -d "$REPO_URL" ]; then git "$@"; else
  local v a=(); for v in $AGENT_VARS; do a+=(-u "$v"); done
  env "${a[@]}" GH_CONFIG_DIR="$GHDIR" GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; fi; }
fetch_ref() {
  if xgit -C "$OX_DIR" fetch --quiet "$REPO_URL" "+refs/heads/$REF:refs/remotes/origin/$REF" 2>/dev/null; then echo branch
  else xgit -C "$OX_DIR" fetch --quiet "$REPO_URL" "+refs/tags/$REF:refs/tags/$REF" && echo tag; fi
}
clone() {
  local kind before
  if [ -d "$OX_DIR/.git" ] && git -C "$OX_DIR" rev-parse -q --verify HEAD >/dev/null; then
    [ "$DRY" = 1 ] && { ok "$OX_DIR" "existing checkout; dry run skips the pull"; return 0; }
    before="$(git -C "$OX_DIR" rev-parse HEAD)"
    kind="$(fetch_ref)" || { note "fetch failed; continuing with the local checkout"; ok "$OX_DIR" "fetch failed, local checkout"; return 0; }
    if [ "$kind" = branch ] && [ "$(git -C "$OX_DIR" rev-parse --abbrev-ref HEAD)" = "$REF" ]; then
      git -C "$OX_DIR" merge --ff-only --quiet "origin/$REF" 2>/dev/null || note "local changes block a fast-forward; continuing with the local checkout"
    fi
    if [ "$(git -C "$OX_DIR" rev-parse HEAD)" = "$before" ]; then ok "$SLUG up to date ($REF)"; else chg "$SLUG updated ($REF)"; fi
    return 0
  fi
  [ "$DRY" = 1 ] && { chg "clone $REPO_URL ($REF) into $OX_DIR"; return 0; }
  mkdir -p "$OX_DIR"
  git -C "$OX_DIR" init --quiet
  git -C "$OX_DIR" remote get-url origin >/dev/null 2>&1 || git -C "$OX_DIR" remote add origin "$REPO_URL"
  kind="$(fetch_ref)" || die "could not fetch $REPO_URL ($REF)"
  if [ "$kind" = branch ]; then
    git -C "$OX_DIR" checkout --quiet -f -B "$REF" "origin/$REF" && git -C "$OX_DIR" branch --quiet --set-upstream-to="origin/$REF" "$REF"
  else git -C "$OX_DIR" checkout --quiet -f --detach "refs/tags/$REF"; fi
  chg "cloned $SLUG ($REF) into $OX_DIR"
}

main() {
  detect; setup_run
  sb platform; se ok "$LABEL"
  [ "$DRY" = 1 ] && out $'  dry run: nothing will be changed\n'
  sb questions; where; se
  log "Basics"
  sb pkgmgr; if [ "$OS" = macos ]; then pkgmgr_macos; else ok "$PKG"; fi; se
  sb core; if [ "$OS" = macos ]; then core_macos; else core_linux; fi; se
  log "GitHub"; sb gh-personal; signin
  log "Repo"; sb clone; clone; se
  if [ ! -f "$OX_DIR/install.sh" ]; then
    [ "$DRY" = 1 ] && { out $'  dry run stops here: install.sh runs after the clone\n'; HANDED=1; return 0; }
    die "$OX_DIR/install.sh not found"
  fi
  log "Handing off to $OX_DIR/install.sh"
  HANDED=1
  export OX_BOOTSTRAPPED=1 OX_DIR
  exec bash "$OX_DIR/install.sh" "$@"
}

if [ "${OX_BOOTSTRAP_LIB:-0}" != 1 ]; then main "$@"; fi
