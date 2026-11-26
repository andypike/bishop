# Screenshots

When a ticket changes the UI, its PR shows **before and after screenshots** of each screen it touched, so a reviewer can compare them without running the branch. The same images go in the ticket's final Linear comment, where clients with guest access see them. This works in interactive and auto mode, for every stack that has a **Screenshots** section.

What's the same for every stack is here. How a stack captures its screens is in that stack's files:

- `stacks/<stack>/stack.md` → **Screenshots** lists the stack's **UI paths** and **targets**.
- `stacks/<stack>/environment.md` → **Screenshots** gives each target's one-off setup, its readiness check, and how to capture.

A stack without these sections has no screenshots, and its tickets go on as before.

**Screenshots never block a ticket.** A failed or unavailable capture is reported in the PR, never fails the quality gate, and never parks a ticket.

## Targets and views

A **target** is something that can capture screens: for Rails, `browser`; for React Native, `ios` and `android`. A target is set up, checked and opted out of as a whole.

Each target captures one or more **views**: the browser captures `desktop` and `mobile`, at the widths in the stack's file, and each simulator captures one phone. Every captured step produces one image per view.

## When a ticket gets screenshots

A ticket gets screenshots when its plan touches any of the stack's UI paths, and at least one target is ready. None are taken when:

- the diff touches no UI paths;
- the stack's file says the change can't be captured: for React Native, a ticket that needs a new native build, or an app ticket that relies on an endpoint that isn't on staging yet;
- every target is opted out or not ready.

Some targets can be skipped while others still capture. Each one skipped gets a skip line in the PR (see [Skip lines](#skip-lines)).

## The journey, in the plan

A plan that touches UI paths gets a **Screenshots** section. It describes a **journey**: ordered, named steps that start from the app's start screen, with the steps to capture marked. A journey can be replayed, unlike a list of URLs, so later features (a narrated demo video, say) can follow the same path.

```markdown
## Screenshots

Targets: browser (desktop, mobile)
Data: an admin, signed in, with two orders (one exported)

1. `orders` — open Orders from the menu → **capture**
2. `order` — open the first order
3. `export-dialog` — click Export, choose CSV → **capture**
```

- **Step names** are short, lowercase and hyphenated. They name the images and the PR rows.
- **Data** says what the journey needs to exist. The stack's file says where that data comes from: Rails builds it with factories in the test database; React Native uses what's already on staging.
- **Targets** lists the targets that are ready and not opted out.

The developer approves the journey at the plan gate with the rest of the plan. In auto mode, it's part of the plan-for-approval comment.

## When they're taken

- **Before**: at the start of Phase 5, after the ticket branch is settled (in auto mode, after the epic merge) and before the first slice. The images show the PR's base. A step whose screen doesn't exist yet, or that needs data or routes the base doesn't have, is recorded as **new**, with no before image.
- **After**: at the end of Phase 6, once the gate is clean, so the images show the final code. If a later fix loops back through Phase 6, take them again.

Both runs walk the same journey. If the after run can't reach a step it reached before, that's a finding to look at, not a screenshot problem.

## The media folder

Images are saved in the ticket's **media folder**:

- auto mode: `<state dir>/media/`;
- interactive mode: `$TMPDIR/<TICKET-ID>/media/`.

The before images go in `media/before/`, and the after images in `media/after/`. Each is named `<nn>-<step>-<view>.png`, where `<nn>` is the step's number: `03-export-dialog-mobile.png`. Never write the images inside the repo, or `git add` could pick them up.

## Opting out

Every target is on unless the developer opts out. Opt-outs are recorded in `~/.bishop/screenshots.json`, per GitHub repo and target:

```json
{ "acme/shop-web": { "browser": "off" } }
```

A missing file, or a repo or target missing from it, means on. The file is per developer, because whether a target works depends on their machine.

**Readiness.** Each target has a readiness check in the stack's `environment.md`.

- **Interactive mode, Phase 2:** run the readiness check for each target that isn't opted out. For each one that isn't ready, ask once:
  - **Set it up now**: show the steps from the stack's file. Setup that changes the project (a gem, a support file) is added only with the developer's approval, as its own commit.
  - **Skip it for this ticket.**
  - **Opt out for this repo**: write it to the file.
- **Auto mode:** preflight runs the readiness checks and warns about any target that isn't ready, without blocking (see `references/preflight.md`). The worker prompt lists the ready targets. Workers capture only those; the rest get a skip line.

## Uploading

### The PR

The PR body's `## Screenshots` section is a table, with a row for each captured step and view. It links the local files:

```markdown
## Screenshots

| Step | Before | After |
| --- | --- | --- |
| Orders (desktop) | ![Before: orders, desktop](<media>/before/01-orders-desktop.png) | ![After: orders, desktop](<media>/after/01-orders-desktop.png) |
| Export dialog (desktop) | New | ![After: export-dialog, desktop](<media>/after/03-export-dialog-desktop.png) |

Screenshots skipped (android): no emulator found.
```

`<media>` is the media folder's absolute path. Pass every linked file to `gh pr create` with `--attach <file>`, once per file. gh uploads each one and swaps its local path in the body for a GitHub URL, which only people with access to the repo can open. One command takes up to 50 files, each up to 10MB.

**If uploading fails partway**, gh still creates the PR, exits with an error, and prints the PR's URL. **Never create the PR again.** Take its number from the URL and finish with:

```bash
gh pr edit <number> --body-file <body file> --attach <file> --attach <file> …
```

If that fails too, replace the table in the body with a skip line (`Screenshots skipped: upload failed`) and carry on.

### Linear

The final comment on the ticket (Phase 8) carries the same table, with the images uploaded to Linear rather than linked from GitHub. GitHub's image links only work for people with access to the repo, and clients reading Linear may not have that.

Upload each image through the Linear MCP, **one file at a time**, because each signed URL expires after 60 seconds:

1. `prepare_file_upload` with the file's name, content type (`image/png`) and exact size in bytes.
2. Upload the file with `curl -X PUT --data-binary @<file>` to the returned URL, sending every returned header exactly as given. A missing or altered header gets a 403.
3. Use the returned markdown in the comment.

Upload the next file only once the previous one has finished. Uploads are private to the workspace and its guests. If an upload fails, the comment gets a skip line for it, and the PR keeps its images.

## Skip lines

Whatever stops a capture or an upload, it's reported as one line, in the PR and in the final comment:

```
Screenshots skipped (<target>): <reason>
```

Use one line per target, with a reason someone can act on: `no Chromium reachable at CHROME_WS_URL`, `opted out`, `needs a new native build`, `step 3 (export-dialog) not found`. Leave out `(<target>)` when the reason applies to every target, as in `Screenshots skipped: no UI changes`. A ticket whose diff touches no UI paths needs no line at all.
