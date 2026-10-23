# Contributing

Thanks for helping! Open an issue first for big changes, and keep PRs focused.

## Setup

```sh
make hooks   # enable the commit message check
make check   # lint + tests, the same as CI
```

## Commit messages

Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
The `commit-msg` hook checks them locally and CI checks them again on every pull request.

```
type(scope): subject in lowercase, no period, 72 characters max

Optional body explaining why, after a blank line.
```

| Type | For |
|---|---|
| `feat` | a new feature or check |
| `fix` | a bug fix or false positive |
| `perf` | faster, or fewer requests |
| `refactor` | code change with no behavior change |
| `docs` | documentation only |
| `test` | tests or fixtures only |
| `build` | dependencies, Go version, Makefile |
| `ci` | GitHub Actions |
| `chore` | anything else |
| `style` | formatting only |
| `revert` | reverting an earlier commit |

Mark breaking changes with `!`, e.g. `feat(cli)!: rename --list to --targets`, and explain them in a
`BREAKING CHANGE:` footer.

## Checks

A new check is a YAML file plus a `_test.yaml` fixture with positive and negative cases.
See [Writing checks](https://github.com/RhythmShahriar/rhythm/wiki/Tuner-Writing-Checks) in the documentation wiki.
Tuner detects and never exploits: no payloads, and secrets are always masked.
