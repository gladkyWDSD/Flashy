# AI Commit for Omarchy

An [Omarchy](https://omarchy.org) shell plugin that adds one button to the top
bar. Click it, and every git repo with unsaved changes gets committed, each with
a commit message Claude writes from that repo's diff.

- The button shows how many repos have uncommitted changes. Hover to see which.
- **Left click** commits them all. You get a notification with each new commit's subject.
- **Right click** does a dry run in a terminal: it shows the messages Claude would write and commits nothing.
- **Middle click** refreshes the count.

## Install

```bash
omarchy plugin add https://github.com/gladkyWDSD/Flashy.git --enable
```

Omarchy shows the plugin's code before you enable it. To place the button
somewhere else on the bar, drag it, or use `omarchy bar move gladkywdsd.ai-commit --section left`.

The plugin needs Claude, through either of these:

- **Claude Code** (recommended). Install it with `omarchy default agent claude` and log in once. The plugin runs `claude -p` with your existing login.
- **An Anthropic API key.** Put `ANTHROPIC_API_KEY="sk-ant-..."` in `~/.config/omarchy/ai-commit.conf`.

## Keyboard shortcut (optional)

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + G", "AI commit all repos", "omarchy-shell gladkywdsd.ai-commit commit")
```

## What it commits

By default it looks for repos up to 4 folders deep in `~/Code`, `~/Projects`,
`~/Work`, `~/src`, `~/dev`, `~/repos`, `~/git` and `~/Developer`, and commits
only repos with a GitHub remote.

For each repo it stages everything (`git add -A`, which respects `.gitignore`),
asks Claude for a message that follows the style of the repo's recent commits,
and commits. Some things are always left alone:

- `.env` files, `*.pem`, `*.key` and SSH keys are never committed, even when they aren't in `.gitignore`.
- Repos in the middle of a merge, rebase, cherry-pick or revert, and repos on a detached HEAD, are skipped.
- If Claude can't write a message, or the commit fails (a hook, say), the repo is left as it was: nothing gets staged.

Commits stay local. Set `PUSH=true` in the config to push too.

## Settings

Copy [`ai-commit.conf.example`](ai-commit.conf.example) to
`~/.config/omarchy/ai-commit.conf` to change the folders to scan, include
non-GitHub repos, pick the Claude model, turn on pushing, and more.

The bar button has two settings of its own: the refresh interval (5 minutes by
default) and whether to hide it while every repo is clean.

## From the terminal

The script works without the bar too:

```bash
~/.config/omarchy/plugins/gladkywdsd.ai-commit/bin/omarchy-ai-commit --list     # dirty repos
~/.config/omarchy/plugins/gladkywdsd.ai-commit/bin/omarchy-ai-commit --dry-run  # preview messages
~/.config/omarchy/plugins/gladkywdsd.ai-commit/bin/omarchy-ai-commit            # commit all
```
