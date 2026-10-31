---
name: ruby-plainspoken
description: Use when writing, changing, refactoring or reviewing Ruby or Rails code — implementing a feature or bug fix in a .rb file, adding a model, controller, job, service, concern or migration, deciding whether a change needs a new class or wrapper, choosing a method signature or a return shape, or judging whether a Ruby diff is over-built. Makes the agent read the real execution path and follow the application's existing pattern before it designs anything, and keeps validation, authorization, database integrity and tests intact. Not for other languages, and not for non-coding work.
---

# Ruby Plainspoken

Aim for the smallest change that fits this application, chosen after reading it. That is not the same as the smallest diff. A short change in the wrong place is a second bug.

Fewer concepts, not fewer objects. An object that owns a contract, a behaviour, an invariant or an external boundary earns its place. An object that only moves one operation behind another name does not.

## 1. Read before you design

Before proposing any code:

1. Read what the change is supposed to do, all of it.
2. Find the entry point and trace the path the change actually runs on, across files.
3. Read the objects next to the change and the tests that cover them.
4. Say what the existing pattern is before choosing a design.

If the request names one file, the flow usually does not end there. Find the other callers.

Fixing a bug means fixing the cause. A report names a symptom. Find every caller of the method you are about to touch and fix the shared method once, rather than guarding each caller.

## 2. Stop at the first rung that holds

For each part of the change, in this order:

1. Does it need to be built at all?
2. Does this application already do it? Reuse that object, method or pattern.
3. Does the Ruby standard library do it?
4. Does Rails do it? (In a Rails application — see section 9.)
5. Does a gem already in the Gemfile do it?
6. Only then write new code. Sketch two shapes before writing one, say in one sentence why you chose it, and write the least of it that works.

Never add a gem when a rung above it covers the request. Check the Gemfile and the lock file before claiming a gem is available.

## 3. Follow the application's own pattern

When the application already has objects doing the same kind of work — service objects, query objects, form objects, jobs, whatever it uses — read two or three of them and match all of it: how they are constructed, what their public methods are called, what they return, how they report failure, how they are named, and how they are tested.

Depart from the pattern only when following it would break a stated requirement or would repeat the very defect you are fixing. When you depart, say in one sentence why the existing pattern does not fit here.

If there is no relevant pattern, apply the rules below. Do not invent an architecture for the whole application on the way past.

## 4. Does this need a new object?

| The behaviour | Then |
|---|---|
| An existing object naturally owns it | Put it there. Create nothing. |
| No existing owner, and it has its own named contract, invariant or external boundary, so callers know less once it exists | Create one object, with the smallest interface its callers need. |
| No existing owner, and no separate contract, invariant or boundary | Keep it inline. Create nothing. |
| Still unclear after tracing the flow | Ask what the responsibility would be called. Do not create the object while the answer is unclear. |

A wrapper with one caller that forwards one call is not a boundary; it is a rename. Objects split by step (parse, then validate, then save) that all know the same format are one object in three files; split by what each one knows, not by when it runs.

Keep the object when it translates a real external system, isolates a failure, or holds an invariant.

## 5. What shape should it return?

| Result | Then |
|---|---|
| Several fields, consumed immediately by one caller, meaning already obvious | Return the plain hash. |
| Several fields, callers depend on the names, values do not change after construction, Ruby 3.2 or newer | Return a `Data.define` value. |
| Several fields, but identity survives while fields change | Return the entity, or an object that protects its own state. |
| A collection callers iterate once and ask nothing of | Return the array or the existing Active Record relation. |
| A collection callers keep asking the same named questions about | Return one object exposing iteration and those questions. |
| A collection whose mutation is part of the contract | Return the object that owns the collection, with the mutation methods it needs. |

Check the Ruby version before using `Data`. On Ruby 3.1 and older `Data.define` does not exist — use whatever the application already uses for values, and do not add a gem to backport it.

Do not use `Data` for an entity, for mutable state, or for a bag of fields with no meaningful name.

## 6. Methods and signatures

Use required keyword arguments for a public call with several inputs of the same kind, or inputs a caller could easily swap, or a boolean that reads as nothing at the call site.

Keep a positional argument when there is one obvious input, or when an existing interface requires it. Do not add keywords to a method that Ruby or Rails calls positionally, and do not convert an interface others already call.

Do not replace clear parameters with an options hash. Do not add a flag parameter or a configuration option so the caller decides something the method can decide itself; one more parameter is complexity at every call site.

Keep a short expression inline when a method around it would only repeat what the expression already says. Keep the method when its name states a rule callers rely on — a name that carries domain meaning is worth more than the line it saves.

## 7. Comments

Do not write a comment that describes readable code. Do not write a comment that repeats the method name, the types or the test.

Do write a short comment when the reason cannot be recovered from the code, the names, the types or the tests: a hidden constraint, a compatibility requirement, a deliberate limit, a workaround for a specific defect.

## 8. Errors

Before adding a `rescue` or a `raise`, ask whether the operation can simply succeed. Deleting a record that is already gone, enqueuing a job twice, or finding nothing are usually normal results, not errors.

When an error is real, handle it in one place (`rescue_from`, `retry_on`, `discard_on`, one boundary object) rather than at every caller. Keep the raise when silent success would lose data or money.

## 9. Rails

In a Rails application, before adding an application layer, a persistence wrapper, a queue wrapper, a validation mechanism, a callback or a gem, check two things: what Rails already provides, and what this application already does.

Use the Rails facility when it meets the requirement — a model validation, a scope, a database constraint with a migration, `has_many`, Active Job, Active Support's own helpers.

A separate plain Ruby object is right when the work has its own inputs, its own failures and no natural model owner. Do not put unrelated multi-step work on a model to avoid creating an object.

## 10. Never removed to make a change smaller

Keep every one of these, even when removing it would shorten the change:

- Validation and authorization
- Database integrity: constraints, uniqueness, foreign keys, not-null
- Transaction boundaries
- Security behaviour, including anything guarding untrusted input
- Accessibility behaviour
- Error handling that prevents data loss
- Existing tests

A shorter change that drops one of these is not simpler. It is broken.

## 11. Leave one check

When the change adds a branch, a loop, a parser or a safety path, leave one focused test behind: the smallest test that fails if that logic breaks.

Write it in the test framework the repository already uses — Minitest or RSpec, whichever is there. Never add a second test framework for one check. Follow the layout of the tests already next to it.

A one-line change with no branch needs no new test.

## Detail

`references/ruby-and-rails.md` holds each rule with a case where it applies and a case where it does not, plus the Sorbet rules. Read the section you need when a decision above is close.

## When the user's instructions disagree

Repository instructions (`CLAUDE.md`, `AGENTS.md`, contributing guides) and the user's explicit request outrank everything here.
