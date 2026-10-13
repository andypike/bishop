# Architecture

The architecture document is the feature's shared design: the data model, the components, and the names every ticket builds against. `feature-planning` writes it once the tickets are known; every `ticket-workflow` run, interactive or auto, follows it.

Its job is to stop tickets worked in parallel from colliding. Two workers that each invent a model for the same concept, name the same route differently, or both add a column to the same table produce PRs that can't both merge. The document settles those choices once, before any ticket starts.

## What it settles, and what it leaves

It fixes **boundaries and names**: which tables and columns exist, which classes exist and in which layer, what each is responsible for, and which ticket introduces each one. It leaves **internals** to the ticket: method design, query details, and test structure are decided when the ticket is worked, against the style guide.

The test for whether something belongs here: would two tickets need to agree on it? If yes, it goes in. If only one ticket ever touches it, leave it to that ticket.

## Building it from the style guide

The style guide (`style-guide/rails-style-guide.md`) is the starting point for every design choice. Walk its high-level sections against the feature, and record in **Style guide** how each one shapes the design:

- **Controllers** — which resources and RESTful routes the feature adds; a custom verb action is a missing resource.
- **Models & Domain Objects** — the domain nouns; which operations are commands in `app/commands`; which concepts deserve a PORO rather than growing an existing model.
- **Database & Migrations** — tables, columns, constraints, defaults, and which queries need a query object.
- **Security** — authentication, what each query is scoped to, and any public endpoints.
- **Views & Presenters** — which screens need a presenter.
- **User-facing Copy** — the i18n scopes the feature's classes use.

Where the codebase doesn't follow the style guide in an area the feature touches, decide once, here, whether the feature follows the guide or the local pattern (per "Working in codebases that don't already follow this" in the style guide), and record why. Otherwise every ticket re-decides it, and they may decide differently.

## Ownership

Every new component, table, and column is **introduced by** exactly one ticket. A ticket that uses something another ticket introduces must be blocked by that ticket. Check this against the tickets' `blockedBy` links: a missing link is a dependency the breakdown didn't see, and the fix is to add it or move the component into the earlier ticket.

Files every ticket may edit — `config/routes.rb`, locale files, `db/schema.rb`, shared concerns — get a convention instead of an owner: what each ticket adds there and how it's named, so their changes merge without conflict.

## Diagrams

Diagrams are Mermaid code blocks (```` ```mermaid ````), which Linear documents render as diagrams and GitHub renders in PRs and markdown. Include only those that explain something the text doesn't:

- **Data model** — an `erDiagram` of the new and changed tables, with the existing tables they connect to. Include whenever the feature changes the schema.
- **Request flow** — a `flowchart` from route to controller to command, models, jobs, and external services. Include whenever the feature adds more than one component per request.
- **Multi-step process** — a `sequenceDiagram` for flows across requests, jobs, or external systems (an import, a payment, an email round trip).
- **Lifecycle** — a `stateDiagram-v2` for any status a record moves through, with what triggers each transition.

Keep each diagram to the feature: show existing parts only where the feature connects to them. Label every new element with the ticket that introduces it where the diagram type allows it (for example in the node text).

## Document template

A Linear document in the project, titled `<Feature name> — Architecture`, linked from the feature document and every ticket.

```markdown
# <Feature name> — Architecture

Feature: [<Feature document title>](<feature document URL>)

## Overview

The shape of the solution in a few sentences: what's new, what it builds on, and how a request flows through it.

## Style guide

- <section> — how it shapes this feature's design.
- <area where the codebase diverges from the guide> — followed the guide / the local pattern, because <why>.

## Data model

<erDiagram>

| Table | Change | Introduced by |
| --- | --- | --- |
| `orders` | add `exported_at :datetime` | ENG-1234 |

## Components

| Component | Layer | Responsibility | Introduced by |
| --- | --- | --- | --- |
| `ExportsController` | controller | create and download exports | ENG-1234 |
| `ExportOrders` | command (`app/commands`) | builds and stores one export | ENG-1234 |

## Flows

<flowchart / sequenceDiagram / stateDiagram-v2, each with a sentence saying what it shows>

## Shared files

- `config/routes.rb` — <what each ticket adds, and the naming>
- `config/locales/en.yml` — <the i18n scopes in use>
- Migrations — <one migration per ticket that changes the schema; the tables each ticket owns>

## Decisions

- <decision> — <why; the alternatives considered and why they lost>

## Left to tickets

- <design questions deliberately not settled here, and which ticket settles each>
```

Omit a section only if it would genuinely be empty. Ticket identifiers are placeholders until `feature-planning` creates the tickets; it fills in the real ones.

## Changing it

The architecture changes only with a developer's approval. A ticket that can't be built as the document says raises it — in interactive mode by asking, in auto mode as a question in its plan or as an escalation (see `references/escalation.md`). Once a change is approved, the document is updated before the ticket finishes — by the developer, or in interactive mode by the agent once the developer has agreed the wording — and the ticket's final comment and PR record what changed. Auto mode agents leave the document to the developer.
