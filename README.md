# git-mirror

Mirrors the default branch of upstream git repositories (on any host) into
private GitHub repositories, daily. An upstream `git push -f` never destroys
history here: the commits it orphans are pinned to snapshot refs in the mirror
first.

## Usage

List the repositories in `mirrors.txt`, one per line:

```
<upstream-url> <owner/repo>
```

The owner is part of each line, so one list can feed several organizations. The
target is created as a private repository on the first run, and the upstream and
target names are independent. Then:

```bash
./mirror.sh
```

Locally it authenticates through `gh auth token`, so `gh auth login` is the only
setup. In CI it reads `GH_TOKEN`.

## Commit SHAs

They match the upstream exactly. A commit's SHA hashes its tree, parents, author,
committer and message, and a push transfers those objects byte for byte, so
mirroring cannot change them.

## What is mirrored

Only the upstream's default branch, whatever it is called. Other branches and
tags are ignored.

## How history is protected

Each run fetches the upstream's default branch and the mirror's current tip into
one temporary bare repository, so the two can be compared.

Nothing is kept when the new upstream tip descends from the mirror's current
tip, the ordinary fast-forward case. Otherwise the upstream rewrote the branch,
and the mirror's current tip is written to

```
refs/snapshots/<YYYYmmdd-HHMMSS>/<branch>
```

before the force-push lands. Because that is a real ref, the commits under it
stay reachable and `git gc` will never reclaim them, unlike reflog entries,
which expire and are off by default in bare repositories.

To browse what an upstream force-push removed:

```bash
git clone https://github.com/ocavue-mirrors/foo.git
cd foo
git fetch origin 'refs/snapshots/*:refs/snapshots/*'
git for-each-ref refs/snapshots
git log refs/snapshots/20260918-031702/main
```

The extra fetch is needed because refs outside `refs/heads/` and `refs/tags/`
are not transferred by the default refspec.

## Failures

A repository that fails is reported and skipped, and the rest of the list still
runs. The script exits non-zero if any of them failed, so a broken entry turns
the scheduled run red without stopping the others.

## CI credentials

The workflow reads a `MIRROR_TOKEN` secret holding a fine-grained personal
access token scoped to the destination organization and nothing else. Create it
under Settings > Developer settings > Personal access tokens > Fine-grained
tokens:

- Resource owner: the destination organization, for example **ocavue-mirrors**
  (as an organization owner, the token is approved automatically)
- Repository access: **All repositories**
- Repository permissions: **Contents: Read and write**,
  **Administration: Read and write** (needed to create repositories),
  **Metadata: Read-only**

Add it to this repository as the secret `MIRROR_TOKEN`. The maximum lifetime is
366 days, so it has to be regenerated once a year.

A fine-grained token has a single resource owner. Mirroring into a second
organization means a second token, and a second `env:` entry in the workflow is
not enough, since the script reads one `GH_TOKEN`. The simplest option then is
one list and one workflow step per organization.

`GITHUB_TOKEN` cannot be used instead: it is scoped to the repository the
workflow runs in and cannot reach another organization.

The workflow also runs on every push to `main`, so a change to `mirrors.txt`
takes effect immediately instead of waiting for the next scheduled run.

This repository is public, but secrets are not exposed to workflows triggered by
pull requests from forks, and this workflow runs only on `push` to `main`,
`schedule` and `workflow_dispatch`. A fork's push runs in the fork, against the
fork's own (absent) secrets.

GitHub disables scheduled workflows in public repositories after 60 days with no
repository activity, and emails you first. Run the workflow manually or push a
commit to re-enable it.
