# Phase 2: AI Intelligence - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The launch pipeline uses AI to interpret crash logs in plain English and to generate recipes for games that have no bundled recipe. Two AI jobs: (1) when WineErrorParser can't diagnose a failure, call AI for diagnosis and structured fix suggestions, (2) when no bundled recipe exists, generate one from game name + installed file scan. AI is optional — everything works without it, just less intelligently.

Requirements: RECIPE-03, LAUNCH-04

</domain>

<decisions>
## Implementation Decisions

### AI Provider & Key Setup
- Support both Claude and OpenAI — user's choice at config time
- Provider auto-detected from env var name: ANTHROPIC_API_KEY → Claude, OPENAI_API_KEY → OpenAI
- If both set, prefer Claude (no additional config needed)
- Use cheapest model tier that works: Claude Haiku / GPT-4o-mini
- No CELLAR_AI_PROVIDER env var needed — key name determines provider

### Diagnosis UX
- AI diagnosis shown inline during retry loop, before each retry attempt
- 2-3 sentence plain-English explanation: what Wine tried, why it failed, what Cellar will do
- AI only called when WineErrorParser can't diagnose (returns .unknown or no suggestedFix) — saves API calls for common DLL cases
- AI can suggest any WineFix type (installWinetricks, setEnvVar, setDLLOverride) — retry loop auto-applies them
- WineErrorParser remains the first-pass, free, instant diagnosis layer

### Recipe Generation Flow
- Trigger: `cellar add` with no bundled recipe → AI generates one
- Timing: after installer runs and files are installed (not before)
- Context sent to AI: game name (from installer filename) + scan of installed files (DLLs, configs, data formats)
- Generated recipe displayed with full transparency (same as bundled recipes — show registry keys, env vars)
- Auto-applied without asking for approval (consistent with bundled recipe behavior)
- Auto-saved to ~/.cellar/recipes/ for reuse on next launch

### Fallback Behavior
- No API key configured: work without AI, show one-time tip on first run — "Set ANTHROPIC_API_KEY for AI-powered diagnosis and recipe generation"
- API call fails: retry 3 times, then fall back to WineErrorParser (for diagnosis) or defaults (for recipe)
- Retry policy applies to both diagnosis and recipe generation API calls
- No bundled recipe AND AI unavailable: warn user and ask whether to continue with defaults ("No recipe available for this game. Continue with defaults? [y/n]")

### Claude's Discretion
- Exact prompt engineering for diagnosis and recipe generation
- HTTP client choice for API calls (URLSession vs third-party)
- AI response parsing and validation strategy
- ~/.cellar/recipes/ directory structure
- How installed file scan works (which files to include, size limits for context)
- Retry backoff strategy (exponential, fixed, etc.)

</decisions>

<specifics>
## Specific Ideas

- AI diagnosis should feel like a knowledgeable friend explaining what went wrong — not raw error codes, not overly technical Wine internals
- The one-time tip for missing API key should be subtle, not a warning or error — Cellar works fine without AI
- Recipe generation after install (not before) means we have real file data to work with — AI can see actual DLLs and config files present

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WineErrorParser`: Already categorizes errors and maps DLLs to fixes — AI supplements when this returns .unknown
- `WineFix` enum: AI responses should return structured fixes using same enum (installWinetricks, setEnvVar, setDLLOverride)
- `Recipe` struct: AI-generated recipes use identical schema — setupDeps, retryVariants, registry, environment all exist
- `RecipeEngine.findBundledRecipe()`: Returns nil for unknown games — this is the trigger point for AI generation
- `WinetricksRunner`: Available for AI-suggested winetricks installs
- `BottleScanner`: Can scan installed files post-install for AI context

### Established Patterns
- Transparency: Recipe application prints every registry key and env var — AI recipes should do the same
- Informative output: "a few lines per action" — AI diagnosis fits this style
- WineResult structured returns: exit code, stderr, elapsed, timedOut — AI receives this context

### Integration Points
- `LaunchCommand` retry loop: AI diagnosis slots in after WineErrorParser fails (between parse and retry)
- `AddCommand` pipeline: recipe generation slots in after installer runs, before first launch
- `RecipeEngine`: needs a new method for AI-generated recipe loading/saving from ~/.cellar/recipes/
- New `AIService` module: provider abstraction, API calls, response parsing

</code_context>

<deferred>
## Deferred Ideas

- macOS Keychain storage for API keys — more secure than env vars, future phase
- AI-powered game identification from EXE metadata and file hashes (GAME-03, v2)
- Confidence scoring on AI-generated recipes (RECIPE-05, v2)
- Recipe refinement loop — if AI recipe fails, feed error back to AI for improved recipe

</deferred>

---

*Phase: 02-ai-intelligence*
*Context gathered: 2026-03-27*
