#!/usr/bin/env bash
#
# Mirror the default branch of upstream git repositories into private GitHub
# repositories, keeping any commit an upstream force-push would orphan.
#
# Reads mirrors.txt, one repository per line:
#
#   <upstream-url> <owner/repo>

set -eu

LIST="$(dirname "$0")/mirrors.txt"

if [ -z "${GH_TOKEN:-}" ]; then
  GH_TOKEN="$(gh auth token)"
fi
export GH_TOKEN

# Answers only for github.com, so a non-GitHub upstream is never handed the
# token, and the token never appears in a URL or in the logs.
HELPER='!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'

mirror_one() {
  upstream="$1"
  repo="$2"
  work="$3"
  target="https://github.com/$repo.git"

  branch="$(git ls-remote --symref "$upstream" HEAD |
    awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }')"
  if [ -z "$branch" ]; then
    echo "    cannot determine the default branch of $upstream" >&2
    return 1
  fi

  git init --bare --quiet "$work"
  git -C "$work" config "credential.https://github.com.helper" "$HELPER"

  # Fetched before the repository is created, so that an unreachable upstream
  # does not leave an empty repository behind.
  git -C "$work" fetch --quiet "$upstream" "+refs/heads/$branch:refs/upstream/head"

  # Both calls go through REST rather than `gh repo view` and `gh repo create`,
  # which use GraphQL and are refused a fine-grained token. The REST endpoints
  # accept one holding "Administration" repository permissions (write).
  if ! gh api "/repos/$repo" >/dev/null 2>&1; then
    echo "    creating $repo"
    gh api --method POST "/orgs/${repo%%/*}/repos" \
      -f "name=${repo##*/}" \
      -F private=true \
      -f "description=Mirror of $upstream" >/dev/null
  fi

  # The mirror's current tip lands under refs/target/head. One object store
  # holding both sides is what lets merge-base below tell a fast-forward apart
  # from a rewrite.
  git -C "$work" fetch --quiet "$target" \
    "+refs/heads/$branch:refs/target/head" 2>/dev/null || true

  # The branch is safe when the new upstream tip descends from the mirror's
  # current tip. Otherwise upstream rewrote it, and the old tip is pinned to a
  # snapshot ref so that git gc can never reclaim those commits.
  old="$(git -C "$work" rev-parse -q --verify refs/target/head || true)"
  snapshot=""
  if [ -n "$old" ] && ! git -C "$work" merge-base --is-ancestor "$old" refs/upstream/head; then
    snapshot="refs/snapshots/$(date -u +%Y%m%d-%H%M%S)/$branch"
    git -C "$work" update-ref "$snapshot" "$old"
    echo "    snapshot $branch -> $snapshot"
  fi

  git -C "$work" push --quiet "$target" "+refs/upstream/head:refs/heads/$branch"

  if [ -n "$snapshot" ]; then
    git -C "$work" push --quiet "$target" "$snapshot:$snapshot"
  fi
}

failed=0

# Read the list on fd 3 so that git and gh cannot swallow it. The order is
# shuffled every run, so one repository that hangs holds up a different set of
# the others each time instead of always the same tail of the list.
while read -r upstream repo <&3; do
  echo "==> $upstream -> $repo"
  work="$(mktemp -d)"

  # One repository must not take the rest of the list down with it. bash
  # suppresses errexit inside a subshell used as a condition, so the subshell
  # runs as a plain statement with errexit turned off around it.
  set +e
  (set -e; mirror_one "$upstream" "$repo" "$work")
  status=$?
  set -e

  rm -rf "$work"

  if [ "$status" -ne 0 ]; then
    echo "    FAILED: $repo"
    failed=$((failed + 1))
  fi
done 3< <(sed 's/#.*//' "$LIST" | grep -v '^[[:space:]]*$' | sort -R)

if [ "$failed" -ne 0 ]; then
  echo "$failed repository(ies) failed" >&2
  exit 1
fi
echo "done"
