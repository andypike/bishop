# Ruby on Rails

- **ID**: `rails` — also its Linear label, `stack:rails`, and its name in a feature document's `Stacks:` line.

## Detection

A repo is Rails when its root has both:

- a `Gemfile` that lists the `rails` gem (or a `Gemfile.lock` with a `rails (` entry);
- `config/application.rb`.

## Sensitive changes

Changes that need a developer's say-so when the approved plan didn't include them (escalation trigger 4 in `references/escalation.md`), on top of the ones every stack shares:

- a migration.

## Deployment tasks

What has to run when merged work is deployed, beyond deploying the code: database migrations, rake tasks, data backfills, and new environment variables or credentials.

- Write each as it runs on the deployed app: `bin/rails db:migrate`, `bin/rails <task>`.
- `bin/rails db:migrate` comes first in the feature's list, since other tasks usually depend on the schema.
- In Phase 8, check the list against the diff: every migration and new rake task in it is listed.

## Architecture

How `references/architecture.md` applies to a Rails feature.

**Style guide sections** — walk these against the feature, and record in the document's **Style guide** section how each one shapes the design:

- **Controllers** — which resources and RESTful routes the feature adds; a custom verb action is a missing resource.
- **Models & Domain Objects** — the domain nouns; which operations are commands in `app/commands`; which concepts deserve a PORO rather than growing an existing model.
- **Database & Migrations** — tables, columns, constraints, defaults, and which queries need a query object.
- **Security** — authentication, what each query is scoped to, and any public endpoints.
- **Views & Presenters** — which screens need a presenter.
- **User-facing Copy** — the i18n scopes the feature's classes use.

**Shared files** — files every ticket may edit, which get a convention instead of an owner: `config/routes.rb`, locale files, `db/schema.rb`, shared concerns, and migrations (one per ticket that changes the schema; the tables each ticket owns).

**Diagrams** — a data model `erDiagram` whenever the feature changes the schema; a request flow `flowchart` from route to controller to command, models, jobs, and external services whenever the feature adds more than one component per request.

**Example components**, as the document's Components table lists them:

| Component | Layer | Responsibility | Introduced by |
| --- | --- | --- | --- |
| `ExportsController` | controller | create and download exports | ENG-1234 |
| `ExportOrders` | command (`app/commands`) | builds and stores one export | ENG-1234 |
