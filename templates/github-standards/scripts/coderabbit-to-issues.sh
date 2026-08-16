#!/usr/bin/env bash
#
# File CodeRabbit review findings as tracked issues, and close them again when
# their review thread is resolved.
#
# A review comment is the right place to *discuss* a finding and the wrong place
# to *track* one: it is invisible from a board, disappears when the PR closes,
# and is counted by nothing. This lifts the findings worth tracking into issues
# and keeps them in step with the thread they came from.
#
# Two directions, driven separately because their triggers differ:
#   file       a review was submitted -> create an issue per qualifying thread
#   reconcile  the clock, or a closed PR -> close issues whose thread resolved
#
# Resolution has no push signal. `pull_request_review_thread` is a *webhook*
# event, not a workflow trigger — putting it under `on:` does not merely fail to
# fire, it stops the whole workflow file from loading. So reconciliation is a
# sweep, GraphQL `isResolved` is the source of truth, and the cost of having no
# event is latency rather than a missed close.
#
# Usage:
#   coderabbit-to-issues.sh --repo OWNER/REPO --pr 12 --write
#   coderabbit-to-issues.sh --repo OWNER/REPO --all-open --reconcile --write
#
# Without --write nothing is created or closed; the run is a dry run that prints
# what it would do. That makes workflow_dispatch safe to press.

set -euo pipefail

REPO=""
PR=""
ALL_OPEN=0
RECONCILE=0
WRITE=0
MIN_SEVERITY="minor"
REVIEWER="coderabbit"
LABELS="coderabbit,needs-triage"

usage() {
  cat <<'EOF'
coderabbit-to-issues.sh — CodeRabbit findings <-> tracked issues

USAGE
  coderabbit-to-issues.sh --repo OWNER/REPO (--pr N | --all-open) [options]

OPTIONS
  --repo OWNER/REPO   Target repository (default: gh's current repo)
  --pr N              Operate on one pull request
  --all-open          Operate on every open pull request
  --reconcile         Close issues whose review thread is now resolved
  --write             Actually create/close. Omit for a dry run.
  --min-severity S    critical | major | minor | trivial   (default: minor)
  --reviewer LOGIN    Substring identifying the bot (default: coderabbit)
  --labels A,B        Labels applied to created issues
  -h, --help          Show this message

SEVERITY
  Derived from CodeRabbit's own comment markers:
    critical  security / vulnerability wording
    major     "⚠️ Potential issue"
    minor     "🛠️ Refactor suggestion"
    trivial   "🧹 Nitpick"
  Anything unrecognised is treated as minor.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo needs OWNER/REPO}"; shift 2 ;;
    --pr) PR="${2:?--pr needs a number}"; shift 2 ;;
    --all-open) ALL_OPEN=1; shift ;;
    --reconcile) RECONCILE=1; shift ;;
    --write) WRITE=1; shift ;;
    --min-severity) MIN_SEVERITY="${2:?--min-severity needs a value}"; shift 2 ;;
    --reviewer) REVIEWER="${2:?--reviewer needs a login substring}"; shift 2 ;;
    --labels) LABELS="${2:?--labels needs a comma list}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { printf 'gh is required\n' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 1; }

[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
OWNER=${REPO%%/*}
NAME=${REPO##*/}

[ -n "$PR" ] || [ "$ALL_OPEN" -eq 1 ] || { usage >&2; printf '\nneed --pr or --all-open\n' >&2; exit 2; }

sev_rank() {
  case "$1" in
    critical) printf '4\n' ;;
    major)    printf '3\n' ;;
    minor)    printf '2\n' ;;
    trivial)  printf '1\n' ;;
    *)        printf '2\n' ;;
  esac
}
MIN_RANK=$(sev_rank "$MIN_SEVERITY")

classify() {
  # stdin: comment body -> stdout: severity word
  local body; body=$(cat)
  case "$body" in
    *ecurity*|*ulnerab*|*njection*|*CVE-*) printf 'critical\n'; return ;;
  esac
  case "$body" in
    *"Potential issue"*)      printf 'major\n' ;;
    *"Refactor suggestion"*)  printf 'minor\n' ;;
    *Nitpick*|*nitpick*)      printf 'trivial\n' ;;
    *)                        printf 'minor\n' ;;
  esac
}

# Every open PR, or the single one named.
pr_numbers() {
  if [ -n "$PR" ]; then
    printf '%s\n' "$PR"
  else
    gh pr list --repo "$REPO" --state open --json number --jq '.[].number'
  fi
}

# All review threads on a PR, as TSV: threadId, isResolved, path, line, url, body(b64)
# shellcheck disable=SC2016  # $owner/$name/$number are GraphQL variables, not shell
threads() {
  local num="$1"
  gh api graphql \
    -f owner="$OWNER" -f name="$NAME" -F number="$num" \
    -f query='
      query($owner:String!, $name:String!, $number:Int!) {
        repository(owner:$owner, name:$name) {
          pullRequest(number:$number) {
            reviewThreads(first: 100) {
              nodes {
                id
                isResolved
                path
                line
                comments(first: 1) {
                  nodes { body url author { login } }
                }
              }
            }
          }
        }
      }' \
    --jq '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | select(.comments.nodes | length > 0)
      | [ .id,
          (.isResolved | tostring),
          (.path // ""),
          (.line // 0 | tostring),
          .comments.nodes[0].url,
          (.comments.nodes[0].author.login // ""),
          (.comments.nodes[0].body | @base64)
        ] | @tsv'
}

marker_for() { printf '<!-- coderabbit-thread:%s -->' "$1"; }

# Issues this script has created, as "threadId<TAB>issueNumber<TAB>state".
tracked_issues() {
  gh issue list --repo "$REPO" --state all --limit 500 \
    --json number,body,state \
    --jq '.[] | select(.body | test("<!-- coderabbit-thread:"))
          | [ (.body | capture("<!-- coderabbit-thread:(?<t>[^ ]+) -->").t), (.number|tostring), .state ]
          | @tsv' 2>/dev/null || true
}

created=0
closed=0
skipped=0

# ---------------------------------------------------------------------------
# file: one issue per qualifying unresolved thread
# ---------------------------------------------------------------------------

if [ "$RECONCILE" -eq 0 ]; then
  known=$(tracked_issues)
  while IFS= read -r num; do
    [ -n "$num" ] || continue
    printf '\n== PR #%s ==\n' "$num"

    while IFS=$'\t' read -r tid resolved path line url author body64; do
      [ -n "$tid" ] || continue
      case "$author" in
        *"$REVIEWER"*) ;;
        *) continue ;;
      esac
      [ "$resolved" = "false" ] || { printf '  · %s already resolved\n' "$path"; continue; }

      body=$(printf '%s' "$body64" | base64 --decode 2>/dev/null || printf '')
      sev=$(printf '%s' "$body" | classify)
      rank=$(sev_rank "$sev")
      if [ "$rank" -lt "$MIN_RANK" ]; then
        printf '  · %s:%s [%s] below --min-severity\n' "$path" "$line" "$sev"
        skipped=$((skipped + 1))
        continue
      fi

      if printf '%s\n' "$known" | grep -q "^$tid	"; then
        printf '  · %s:%s already tracked\n' "$path" "$line"
        continue
      fi

      # First non-empty, non-heading line makes a usable title.
      summary=$(printf '%s\n' "$body" \
        | sed 's/[*_`]//g' \
        | grep -vE '^[[:space:]]*$|^_|^#|^<!--|^\|' \
        | head -1 | cut -c1-90)
      [ -n "$summary" ] || summary="review finding"
      title="[coderabbit] ${path:-review}: ${summary}"

      # shellcheck disable=SC2016  # backticks below are markdown code spans
      {
        marker_for "$tid"
        printf '\n\n**Severity:** %s  ·  **PR:** #%s  ·  **File:** `%s:%s`\n\n' \
          "$sev" "$num" "${path:-n/a}" "$line"
        printf '[View the review thread](%s)\n\n---\n\n' "$url"
        printf '%s\n' "$body"
        printf '\n---\n<sub>Filed automatically from a CodeRabbit review. '
        printf 'Closes itself when the review thread is resolved.</sub>\n'
      } >/tmp/cr-issue.md

      if [ "$WRITE" -eq 1 ]; then
        issue_url=$(gh issue create --repo "$REPO" \
          --title "$title" --body-file /tmp/cr-issue.md \
          --label "$LABELS" 2>/dev/null) || {
            printf '  ! failed to create issue for %s\n' "$path"; continue; }
        printf '  + %s [%s] -> %s\n' "${path:-review}" "$sev" "$issue_url"
      else
        printf '  + would create [%s] %s\n' "$sev" "$title"
      fi
      created=$((created + 1))
    done < <(threads "$num")
  done < <(pr_numbers)
fi

# ---------------------------------------------------------------------------
# reconcile: close issues whose thread is resolved
# ---------------------------------------------------------------------------

if [ "$RECONCILE" -eq 1 ]; then
  resolved_ids=""
  while IFS= read -r num; do
    [ -n "$num" ] || continue
    while IFS=$'\t' read -r tid resolved _path _line _url _author _body; do
      [ "$resolved" = "true" ] && resolved_ids="${resolved_ids}${tid}"$'\n'
    done < <(threads "$num")
  done < <(pr_numbers)

  while IFS=$'\t' read -r tid issue state; do
    [ -n "$tid" ] || continue
    [ "$state" = "OPEN" ] || continue
    printf '%s\n' "$resolved_ids" | grep -qx "$tid" || continue
    if [ "$WRITE" -eq 1 ]; then
      gh issue close "$issue" --repo "$REPO" --reason completed \
        --comment "Review thread resolved — closing automatically." >/dev/null 2>&1 \
        && printf '  - closed #%s (thread resolved)\n' "$issue" \
        || printf '  ! could not close #%s\n' "$issue"
    else
      printf '  - would close #%s (thread resolved)\n' "$issue"
    fi
    closed=$((closed + 1))
  done < <(tracked_issues)
fi

printf '\n%s: %d created, %d closed, %d below severity\n' \
  "$([ "$WRITE" -eq 1 ] && printf 'done' || printf 'dry run')" \
  "$created" "$closed" "$skipped"
