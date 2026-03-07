# lunar-llint-action

GitHub Action to lint Lunar Linux module files using [llint](https://github.com/lunar-linux/lunar).

Automatically detects changed module directories (containing `DETAILS` or `DEPENDS` files) and runs `llint --path` on each. On pull requests, lint errors are posted as a PR comment.

## Usage

```yaml
name: Lint Modules
on:
  pull_request:
  push:
    branches: [master]

permissions:
  contents: read
  pull-requests: write

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: lunar-linux/lunar-llint-action@v1
```

> **Note:** `fetch-depth: 0` is required so the action can diff against the base commit to find changed files.
> `pull-requests: write` is needed to post lint errors as PR comments. For PRs from forks, GitHub restricts the token to read-only — the comment step is skipped gracefully and lint errors are still visible in the action logs.

Contributors can fix issues locally by running `llint --path <module-dir> --fix`.

## Inputs

| Input             | Default  | Description                                    |
|-------------------|----------|------------------------------------------------|
| `version`         | `latest` | llint release tag to use (e.g. `v50`)          |
| `max-line-length` | `120`    | Maximum line length for heredoc text in DETAILS |

## How it works

1. Downloads the `llint` binary from the [lunar releases](https://github.com/lunar-linux/lunar/releases)
2. Diffs changed files between base and head commits
3. Deduplicates directories and filters to those containing `DETAILS` or `DEPENDS`
4. Runs `llint --path <dir>` on each, grouping output per module
5. On PRs with errors, posts a comment with the lint output
6. Exits non-zero if any module has lint errors
