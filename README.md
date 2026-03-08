# lunar-llint-action

GitHub Action to lint Lunar Linux module files using [llint](https://github.com/lunar-linux/lunar-tools).

Automatically detects changed module directories (containing `DETAILS` or `DEPENDS` files) and runs `llint --path` on each.

## Usage

This action uses a two-workflow design so that lint errors can be posted as PR comments even on fork PRs, without granting write access to untrusted code.

Copy both files from [`examples/`](examples/) into your repo's `.github/workflows/`:

### `.github/workflows/lint.yml` — runs the linter

```yaml
name: Lint Modules

on:
  pull_request:
  push:
    branches: [master]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: lunar-linux/lunar-llint-action@v1
```

### `.github/workflows/lint-comment.yml` — posts PR comments

```yaml
name: Lint Comment

on:
  workflow_run:
    workflows: [Lint Modules]
    types: [completed]

permissions:
  pull-requests: write
  actions: read

jobs:
  comment:
    if: >-
      github.event.workflow_run.event == 'pull_request'
      && github.event.workflow_run.conclusion == 'failure'
    runs-on: ubuntu-latest
    steps:
      - name: Download lint output
        uses: actions/download-artifact@v4
        with:
          name: llint-output
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ github.token }}

      - name: Find PR number
        id: pr
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          head_sha=${{ github.event.workflow_run.head_sha }}
          pr=$(gh pr list --repo "${{ github.repository }}" --state open \
            --json number,headRefOid \
            --jq ".[] | select(.headRefOid == \"$head_sha\") | .number")
          echo "number=$pr" >> "$GITHUB_OUTPUT"

      - name: Post comment
        if: steps.pr.outputs.number != ''
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          errors=$(grep -vE '^::(group|endgroup)::' llint-output.txt | grep -v '^$' || true)

          cat > /tmp/comment.md <<'COMMENT_EOF'
          ## llint found issues

          The following lint errors were found in this PR:

          ```
          COMMENT_EOF

          echo "$errors" >> /tmp/comment.md

          cat >> /tmp/comment.md <<'COMMENT_EOF'
          ```

          Run `llint --path <module-dir> --fix` locally to auto-fix fixable issues.
          COMMENT_EOF

          gh pr comment "${{ steps.pr.outputs.number }}" \
            --repo "${{ github.repository }}" \
            --body-file /tmp/comment.md
```

> **Note:** `fetch-depth: 0` is required so the action can diff against the base commit to find changed files.

### Why two workflows?

PRs from forks get a read-only `GITHUB_TOKEN` — they can't post comments. The `workflow_run` workflow triggers in the base repo's context with write permissions, but never checks out or executes fork code. It only reads the lint output artifact (a text file) and posts it as a comment. This is the [GitHub-recommended pattern](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#workflow_run) for safely commenting on fork PRs.

Contributors can fix issues locally by running `llint --path <module-dir> --fix`.

## Inputs

| Input             | Default  | Description                                    |
|-------------------|----------|------------------------------------------------|
| `version`         | `latest` | llint release tag to use (e.g. `2026.2`)       |
| `max-line-length` | `120`    | Maximum line length for heredoc text in DETAILS |

## How it works

1. Downloads the `llint` binary from the [lunar-tools releases](https://github.com/lunar-linux/lunar-tools/releases)
2. Diffs changed files between base and head commits
3. Deduplicates directories and filters to those containing `DETAILS` or `DEPENDS`
4. Runs `llint --path <dir>` on each, grouping output per module
5. Uploads lint output as an artifact (on failure)
6. A separate `workflow_run` workflow picks up the artifact and posts a PR comment
7. Exits non-zero if any module has lint errors
