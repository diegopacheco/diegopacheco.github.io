# GitHub Pages Instructions

## Read First

Before any change in this repository, read:

`/Users/diegopacheco/git/diegopacheco/ai-playground/pages/pages.md`

That file is the registry of every GitHub Pages route under `diegopacheco.github.io`. Do not break any route listed there.

## How This Site Publishes

`diegopacheco/diegopacheco.github.io` has no workflow. It serves `index.html` with classic GitHub Pages from the `master` branch. Pushing `master` publishes `https://diegopacheco.github.io/`.

`diegopacheco/ai-playground` is a separate site published by its own `.github/workflows/agents-pages.yml` workflow under `https://diegopacheco.github.io/ai-playground/`.

## Rules

- Change only files in this repository.
- Never modify, commit, push, or deploy `diegopacheco/ai-playground` from work on this repository.
- Never add a GitHub Actions workflow to this repository.
- Never change the Pages source branch or folder in the repository settings.
- Never create an `ai-playground/` path in this repository, it collides with the `ai-playground` project site routes.
- Keep edits surgical. Do not reformat or restructure `index.html` beyond the requested change.
- Keep existing sections, links, styles, and scripts intact.

## Required Checks Before Push

- `git diff --check` passes.
- `git diff --stat` shows only the intended files and lines.
- Every new external link returns HTTP 200.
- The page renders locally with `./preview.sh`.

## Publish

1. Commit the change on `master`.
2. Push `master` to `origin`.
3. Wait until `gh api repos/diegopacheco/diegopacheco.github.io/pages/builds/latest --jq .status` returns `built`.

## Required Checks After Push

- `https://diegopacheco.github.io/` returns HTTP 200.
- The live page contains the new change.
- `https://diegopacheco.github.io/ai-playground/` returns HTTP 200.
- Every `ai-playground` URL listed in `pages.md` still returns HTTP 200.

## Recovery

If the site build fails or a route breaks, revert the last commit on `master`, push, and verify every URL above before making any further change.
