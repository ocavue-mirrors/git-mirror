# git-mirror

Mirrors the default branch of every upstream in `mirrors.txt` (`<upstream-url> <owner/repo>`, any host) into a private GitHub repository, every three days, creating the target on first use.

An upstream force-push never loses history: the orphaned tip is pinned to `refs/snapshots/<timestamp>/<branch>`, which `git gc` cannot reclaim.

Those refs are outside the default refspec, so read them with `git fetch origin 'refs/snapshots/*:refs/snapshots/*'`.

Locally it authenticates through `gh auth token`; in CI through `MIRROR_TOKEN`, a fine-grained token on the destination organization with Contents and Administration write plus Metadata read.
