# ox-bootstrap

One command that turns a brand-new machine into a fully configured one by
fetching and running a private dotfiles repo, smicha/ox
(https://github.com/smicha/ox).

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/smicha/ox-bootstrap/main/bootstrap.sh)"
```

Nothing needs to be installed first. On a machine that is already set up the
same command changes nothing and ends with "Everything is already set up.
Nothing to do."

## Why this repo exists

The dotfiles repo is private. A curl one-liner cannot fetch a file from a
private repo without credentials, so this small public repo carries only the
part that has to run before sign-in: install the basics, sign in to GitHub,
clone the private repo, and hand off to its `install.sh`.

It contains nothing personal or sensitive: no names, emails, machine names,
tokens or work details. Every answer is asked on the machine, or preset through
environment variables, and stored only on that machine.

## What it does

1. Detects the platform (macOS, Ubuntu/Debian, Fedora, Arch, Ubuntu on WSL2)
2. Asks where to clone (default `~/.ox`) unless `OX_DIR` is set or a clone
   already exists
3. Installs the basics, asking for your password only right before a step that
   needs it:
   - macOS: Homebrew (non-interactive, which also installs the Xcode Command
     Line Tools) and gh; `brew shellenv` is added to `~/.zprofile` once
   - Linux and WSL: git and curl from the native package manager, and gh from
     GitHub's official package repository (apt, dnf) or `github-cli` (pacman)
4. Signs in to GitHub (see below), skipped when already signed in
5. Clones the private repo over HTTPS through gh, or fast-forwards an existing
   clone
6. Hands off to the repo's `install.sh`, which asks the remaining questions up
   front and finishes the setup

## Progress and logs

The run shows one progress bar for all steps, the bootstrap's and then
install.sh's, with the step number, name and elapsed time. On a terminal it
updates in place; piped or in CI it prints one plain line per step start and
end. Command output goes to the log (`~/Library/Logs/ox-install.log` on
macOS, `~/.local/state/ox/install.log` on Linux and WSL); `OX_VERBOSE=1`
shows it live instead. Prompts, the password and the GitHub device code
pause the bar so they are never hidden. Every run ends with a summary of each
step's status and time, also when it fails or is interrupted.

## Supported platforms

| Platform | Package strategy |
|---|---|
| macOS on Apple silicon | Homebrew |
| Ubuntu, Debian | apt for system basics, Homebrew on Linux for the dev CLI set |
| Fedora | dnf for system basics, Homebrew on Linux for the dev CLI set |
| Arch | pacman for system basics, Homebrew on Linux for the dev CLI set |
| Ubuntu on WSL2 | as Ubuntu, plus the Windows Terminal font and color scheme |

## Signing in to GitHub

```text
How do you want to sign in to GitHub (smicha)?
  1) Browser login (recommended)
  2) Personal access token (PAT)
Choice [1]:
```

**Browser login (recommended).** Opens github.com in the browser and shows a
one-time code. On WSL it opens the Windows browser through `wslview`. On a
machine without a browser it prints the URL (https://github.com/login/device)
and the code to enter on any other device.

**Personal access token.** Create one at https://github.com/settings/tokens:

- Classic token: scopes `repo`, `read:org`, `gist`, `workflow`,
  `admin:public_key`
- Fine-grained token: Contents read access on the private repo, and the
  account permission "Git SSH keys" set to read and write

The token is read without echo, piped straight to `gh auth login --with-token`,
and cleared right after. It is never passed as a command-line argument, kept in
an environment variable, or written to a log. After sign-in the account and
its permissions are checked; if something is missing you are told exactly what
and can enter another token or switch to the browser.

## Environment variables

Every variable below is optional. Anything else starting with `OX_` passes
through to the private repo's `install.sh` untouched (see its README for the
full list, including the questions it asks).

| Variable | Effect |
|---|---|
| `OX_DIR` | Clone location, default `~/.ox` (a leading `~` is expanded) |
| `OX_REF` | Branch or tag to clone, default `main` |
| `OX_DRY_RUN=1` | Print every action without executing it |
| `OX_VERBOSE=1` | Show full command output live instead of the progress bar |
| `OX_GH_AUTH=browser\|token` | Sign-in method, skips the question |
| `OX_GH_TOKEN_FILE=path` | Read the token from a file (token mode) |
| `OX_GH_TOKEN_STDIN=1` | Read the token from stdin (token mode) |
| `OX_SKIP_GITHUB=1` | Skip GitHub sign-in (test runs against a local clone) |
| `OX_REPO_SLUG`, `OX_REPO_URL` | Clone something other than smicha/ox |

A raw token is never accepted as an environment variable or argument.

Fully unattended example:

```bash
OX_GH_AUTH=token OX_GH_TOKEN_FILE=~/gh-token.txt \
OX_SCOPE=personal OX_MACHINE_NAME=build-box \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/smicha/ox-bootstrap/main/bootstrap.sh)"
```

## License

MIT
