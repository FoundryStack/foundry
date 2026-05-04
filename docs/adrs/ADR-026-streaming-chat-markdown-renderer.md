# ADR-026: Streaming Markdown Renderer for Studio Chat

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** Platform team
**Extends:** ADR-001, ADR-004

---

## Context

`FoundryWeb.ChatMarkdown` is a hand-rolled markdown renderer used by the Studio chat UI.
It supports only a narrow subset of markdown and reparses the full assistant response on
every streamed delta. This creates three problems:

1. Studio chat responses from LLM providers arrive token-by-token, so incomplete syntax
   like partial emphasis, links, and code fences can render poorly while streaming.
2. The renderer omits common GitHub Flavored Markdown constructs that show up in agent
   output, including ordered lists, blockquotes, tables, task lists, strikethrough, and
   autolinked URLs.
3. The current implementation emits one pre-rendered HTML blob per message, so LiveView
   re-diffs the whole message each time new assistant text arrives.

This is a dependency addition, so ADR-004 requires an ADR before implementation.

## Decision

**Replace `FoundryWeb.ChatMarkdown` with `phoenix_streamdown` in `foundry_web`.**

`phoenix_streamdown` is a Phoenix LiveView component purpose-built for LLM streaming and
uses `MDEx` underneath for markdown parsing/rendering. It is a better fit than wiring
`MDEx` directly because it preserves valid output for incomplete fragments and reduces
re-render churn by freezing completed blocks.

### Rendering policy

- Assistant messages render through `<PhoenixStreamdown.markdown />`
- `streaming={true}` is passed only while the active assistant message is still receiving
  deltas
- GFM-oriented `MDEx` options are enabled for tables, task lists, autolinks, and
  strikethrough
- Raw HTML remains non-executable; markdown HTML is escaped rather than rendered unsafely

## Consequences

- Studio chat gains materially better markdown fidelity for LLM output
- Incomplete streamed syntax stays readable during generation instead of breaking the DOM
- The custom markdown module can be removed, reducing maintenance burden
- `foundry_web` adds a new UI dependency, which remains acceptable under ADR-004 because
  it is documented here and published on Hex
