# Architecture

The architecture document is the feature's shared design: the data model, the components, and the names every ticket builds against. `feature-planning` writes it once the tickets are known; every `ticket-workflow` run, interactive or auto, follows it.

Its job is to stop tickets worked in parallel from colliding. Two workers that each invent a model for the same concept, name the same route differently, or both add a column to the same table produce PRs that can't both merge. The document settles those choices once, before any ticket starts.

## What it settles, and what it leaves

It fixes **boundaries and names**: which tables and columns exist, which classes exist and in which layer, what each is responsible for, and which ticket introduces each one. It leaves **internals** to the ticket: method design, query details, and test structure are decided when the ticket is worked, against the style guide.

The test for whether something belongs here: would two tickets need to agree on it? If yes, it goes in. If only one ticket ever touches it, leave it to that ticket.

## Building it from the style guide

The stack's style guide (`stacks/<stack>/style-guide.md`) is the starting point for every design choice — each stack's own guide, for its own components, when the feature spans stacks. Walk its high-level sections against the feature, and record in **Style guide** how each one shapes the design. The "Architecture" section of the stack's `stack.md` lists those sections and what each one decides, along with the stack's shared files, the diagrams that usually apply, and example components.

Where the codebase doesn't follow the style guide in an area the feature touches, decide once, here, whether the feature follows the guide or the local pattern (per "Working in codebases that don't already follow this" in the style guide), and record why. Otherwise every ticket re-decides it, and they may decide differently.

## Across stacks: the API contract

When the feature spans stacks (a Rails backend and a React Native app, say), the **API contract** is the boundary between them: every endpoint the feature adds or changes, its request, its response, and its errors, exactly as sent over the wire. It's what lets a backend ticket and an app ticket be worked at the same time, in different repos, without either waiting for the other: the backend ticket builds the endpoint to the contract, and the app ticket builds against it, mocking the API in its tests.

- Each endpoint is **introduced by** exactly one backend ticket.
- App tickets that use an endpoint are **not** blocked by the ticket that introduces it — the exception to the rule below. They list it under Technical notes instead, and their deployment tasks say the backend ticket has to be deployed first.
- Payloads use the backend's own field names (usually snake_case); the app maps them to its own types.
- A change to the contract is a change to the architecture (see [Changing it](#changing-it)), and affects both sides: raise it rather than adjust one side.

## Ownership

Every new component, table, column, and endpoint is **introduced by** exactly one ticket. A ticket that uses something another ticket introduces must be blocked by that ticket — except an app ticket using an endpoint from the API contract (see above). Check this against the tickets' `blockedBy` links: a missing link is a dependency the breakdown didn't see, and the fix is to add it or move the component into the earlier ticket.

Files every ticket may edit — routes, locale files, the database schema, shared modules; the stack's `stack.md` lists them — get a convention instead of an owner: what each ticket adds there and how it's named, so their changes merge without conflict.

## Diagrams

Diagrams are Mermaid code blocks (```` ```mermaid ````), which Linear documents render as diagrams and GitHub renders in PRs and markdown. Include only those that explain something the text doesn't:

- **Data model** — an `erDiagram` of the new and changed tables, with the existing tables they connect to. Include whenever the feature changes the schema.
- **Request flow** — a `flowchart` from where a request enters (a route, a screen) through each component it passes, to storage and external services. Include whenever the feature adds more than one component per request.
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

## API contract

Only when the feature spans stacks. One entry per endpoint the feature adds or changes:

### `POST /api/orders/:order_id/exports` — ENG-1234

- **Request**: `{ "format": "csv" }`
- **Response** `201`: `{ "id": 7, "status": "pending", "download_url": null }`
- **Errors**: `404` order not found; `422` `{ "errors": { "format": ["is not supported"] } }`
- **Used by**: ENG-1240 (app)

## Components

| Component | Layer | Responsibility | Introduced by |
| --- | --- | --- | --- |
| `<name>` | <layer, per the style guide> | <what it's responsible for> | ENG-1234 |

## Flows

<flowchart / sequenceDiagram / stateDiagram-v2, each with a sentence saying what it shows>

## Shared files

- <shared file, from the stack's list> — <what each ticket adds there, and the naming>

## Decisions

- <decision> — <why; the alternatives considered and why they lost>

## Left to tickets

- <design questions deliberately not settled here, and which ticket settles each>
```

Omit a section only if it would genuinely be empty. Ticket identifiers are placeholders until `feature-planning` creates the tickets; it fills in the real ones.

## Changing it

The architecture changes only with a developer's approval. A ticket that can't be built as the document says raises it — in interactive mode by asking, in auto mode as a question in its plan or as an escalation (see `references/escalation.md`). Once a change is approved, the document is updated before the ticket finishes — by the developer, or in interactive mode by the agent once the developer has agreed the wording — and the ticket's final comment and PR record what changed. Auto mode agents leave the document to the developer.
