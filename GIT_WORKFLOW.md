# Git Workflow — ShypQuick

**Rule #1: Every change gets committed and pushed to `origin/main` immediately.**

No exceptions. No batching. No "I'll push it later." The remote on GitHub is the source of truth — if it's not on GitHub, it doesn't exist.

## The standard

After **every** meaningful change — a new file, an edited function, a schema update, a bug fix, a README tweak — run the full cycle:

```bash
cd ~/Desktop/ShypQuick
git add <specific files>
git commit -m "<clear message>"
git push
```

Then verify the push landed: https://github.com/divinedavis/ShypQuick

## What counts as "a change"

- ✅ A new Swift file or feature
- ✅ An edit to an existing file (even one line)
- ✅ A Supabase schema change in `supabase/schema.sql`
- ✅ A fix to the Xcode project file
- ✅ A README or docs update
- ✅ A `.gitignore` tweak

Even if it's "in progress" or "not done yet" — commit it with a WIP message and push. You can always amend or squash later, but you can never recover work that was never pushed and then got lost.

## Commit message format

Short, specific, present tense. No fluff.

**Good:**
- `Add DriverHomeView with online/offline toggle`
- `Fix duplicate file entries in Xcode project`
- `Update Supabase schema: add driver_locations table`
- `WIP: customer delivery request flow`

**Bad:**
- `stuff`
- `changes`
- `updates to app`
- `fix`

First line ≤ 72 chars. If you need more context, add a blank line and a body explaining **why** (not what — the diff shows what).

## Staging rules

- **Prefer `git add <file>`** over `git add .` or `git add -A`. Explicit is safer — it prevents accidentally committing `Secrets.plist`, `.DS_Store`, `DerivedData/`, or half-finished files from another feature.
- **Never commit** `Secrets.plist`, API keys, `.env` files, or anything in `DerivedData/`, `build/`, or `xcuserdata/`. The `.gitignore` should catch these, but verify with `git status` before every commit.
- **Check `git status`** before every commit to know exactly what's going out.

## Branch policy

For now: **work directly on `main`**. Solo dev, small project, fast iteration.

When the app has real users:
- Create feature branches (`git checkout -b feature/driver-ratings`)
- Open PRs to `main`
- Never force-push `main`

## Push failures

If `git push` rejects with "fetch first":

```bash
git pull --rebase origin main
# resolve any conflicts
git push
```

**Never** use `git push --force` on `main`. If you think you need to, stop and ask.

## Remote setup

Repo uses SSH (faster, no password prompts):

```
origin  git@github.com:divinedavis/ShypQuick.git
```

If you ever see `https://` in `git remote -v`, switch it:

```bash
git remote set-url origin git@github.com:divinedavis/ShypQuick.git
```

## The verification habit

After every push, run:

```bash
git log --oneline -5
git status
```

Both should be clean and up to date. If `git status` shows uncommitted files, you're not done yet.

---

**Bottom line**: push early, push often, push everything. A commit that isn't on GitHub is a commit that doesn't exist.
