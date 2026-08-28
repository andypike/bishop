# Rails Style Guide

This is the single style guide `bishop` applies across every project it's used on — not one guide per codebase. It's a living document: tune it whenever a code review surfaces something you'd rather see written differently. As it matures, you should need to review less and less by hand.

Seeded from thoughtbot's Rails AI rules (https://github.com/thoughtbot/guides/tree/main/rails/ai-rules/rules), then edited to taste below. Treat everything here as a starting point to argue with, not gospel.

## Working in codebases that don't already follow this

Some projects predate this guide and won't meet it. That's expected — the goal is to raise quality as you go, not to block on a codebase's starting point. Two rules when touching existing code:

- New/changed code follows this guide, even if it's locally inconsistent with the surrounding file.
- Don't copy an existing anti-pattern just to "match the file." Matching formatting/naming conventions that are neutral is fine; propagating a real anti-pattern (fat controllers, N+1s, etc.) is not.

## Code Comments

- Code comments are a smell, not a goal. They should be rare. The code, its names, the tests, and the commit message carry the meaning. A comment is the last resort once none of those can.
- Before writing a comment, prefer these in loose order. There's weight to the order, but it's not absolute. Apply each only where it makes sense, and don't force an earlier one when a later one already tells the story (a manufactured extraction is its own smell):
  1. **Rename** — a clearer method, variable, or class name that states the intent.
  2. **Extract** — pull a confusing expression into a well-named method that names the concept. If a whole concept is missing, extract the right PORO/domain class (see Models rules).
  3. **Test** — let a well-written spec tell the story of the behaviour and its edge cases.
  4. **Commit message** — explain the *why* and the history there, not in the source.
- Only then write a comment. Typically when the rationale matters but a commit message is too far removed from the code for someone to find it when they need it.
- Favour explaining *why* over *what* — the code already shows what it does, so restating it is noise. The rare exception is genuinely dense mechanics, e.g. a non-obvious algorithm, where naming what each step does earns its keep.
- No narration, no TODO/changelog/decision-log comments, no commented-out code.

## Controllers

- Controllers handle HTTP only: receive request, delegate to model or command object, return response.
- Avoid long actions, since they often signal business logic that belongs in a model or command object.
- No business logic, calculations, email sending, or multi-object operations in controllers.

- Prefer RESTful routes. Custom verb actions (e.g., `post "activate"`) usually mean a missing noun/resource (e.g., `resource :trial, only: [:create]`).

## Database & Migrations

- Always use the `rails generate migration` command to create migration files.
- Use `text` over `string` if length varies significantly with empty string defaults.
- Add `null: false` and database-level defaults where appropriate.
- Wrap multi-record operations in transactions. Use `save!` (bang) inside transactions.
- Keep scopes as one-liners. Complex queries belong in search/query objects.
- When querying for a list, prefer pagination to unbound result sets.
- Avoid `.count` in loops, use `counter_cache`.

- Avoid SELECT N+1 querying.
## Models & Domain Objects

- All domain classes live in `app/models/` including ActiveRecord models and POROs.
- Model contain closely related logic not everything to do with that model.
- Commands in `app/commands` contains a single business operation such as `PlaceOrder`
- Commands are simple PORO classes with a `#call` method.
- Encapsulate logic in small private methods within the command so the `#call` method reads as a list of operations
- Name classes after domain nouns, not actions. No `*Service`, `*Manager`, `*Handler` suffixes.
- Use `ActiveModel::Model` for POROs that need validation or form integration.

- Look to identify domain models that can be extracted when an existing model is large.
- Callbacks only for data integrity (normalise fields, set defaults). Never for emails, payments, or external systems.
- Prefer composition over inheritance. Extract behaviour into small, focused objects.
- Avoid feature envy, long parameter lists, case statements on type, and mixin abuse.

## Security

- Never interpolate user input into SQL. Use parameterised queries or `where(key: value)`.
- Always use strong parameters. Never `params.permit!`.
- Scope all queries to the current user or other known root object.
- Every controller must have authentication unless explicitly public.
- Never use `raw`, `html_safe`, or `<%==` with user-supplied data.
- Never skip CSRF verification for browser-facing controllers.
- Filter sensitive params in logs: passwords, tokens, secrets, API keys.
- Use a serializer class to define what is returned when serializing JSON to the client.
- Never redirect to `params[:return_to]` without validation.
- Use array form for system commands: `system("cmd", arg)`, never `system("cmd #{arg}")`.

## Testing

- Must use TDD. Write tests first and follow red, green, refactor.

- Test behaviour, not implementation. Four Phase Test: setup, exercise, verify, teardown.
- Test pyramid: many model/PORO unit specs, some request specs, few system specs.
- Every public method on every model and PORO must have at least one spec.
- Every branch in a conditional must have at least one spec.
- Use `build` / `build_stubbed` over `create` unless persistence is needed.
- Factories: only required attributes with sensible defaults. Start in `spec/factories.rb`.
- Simple explicit model validation testing per attribute
- WebMock blocks all external HTTP in tests — always stub external requests.
- Never test private methods directly. Never stub the system under test.

## Views & Presenters

- Views render data. No calculations, queries, or complex conditionals.
- Use presenters to display logic. Instantiate in controller, use in view.
- Extract repeated markup into partials. Pass data via `locals:`, not instance variables.
- Helpers for simple formatting only (dates, currencies). If longer than 5 lines, use a presenter.
- Turbo: return `status: :unprocessable_entity` on failed forms. Keep Stimulus controllers small

## Quality gate philosophy

There are no fixed numeric thresholds for coverage, RuboCop, or RubyCritic in this guide — see `references/quality-gates.md` for how baseline-vs-after comparison works instead. This file governs *what good code looks like*; that one governs *how we verify it got better*.
