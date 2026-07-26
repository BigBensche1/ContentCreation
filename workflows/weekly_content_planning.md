# Workflow: Weekly Content Planning (Trend Research & Auto-Scheduling)

## Objective
Keep the Schedule sheet topped up automatically so the user doesn't have to hand-author every topic. Once a week, research what's currently trending for each account's niche and append new `Pending` rows until each account reaches its target standing pool of open posts.

## Trigger
Weekly (target: Sundays) via an Anthropic `/schedule` cloud agent connected to this project's GitHub repo. Until that's wired up, run this manually by asking the agent to "run the weekly content planning."

Uses the same `tools/*.ps1` (PowerShell 7+ required) as `workflows/social_media_post_pipeline.md`.

## Inputs
- Google Sheet (`Schedule` tab) — same sheet and schema as the per-post pipeline.
- `config/accounts.json` — each account's `niche` (what to research) and `weekly_slot_share` (its target number of open slots).

## Definitions
- **Open row**: any row whose `status` is anything before `Published`/`Failed` (i.e. `Pending`, `ImageGenerating`, `ImageRejected-Retry`, `VideoGenerating`, `AwaitingUserReview`, `Approved`, `ReadyToPublish-ManualAction`). `Failed` rows do **not** count as open and are not auto-replaced — they need human attention.
- **Shortfall** for an account = `weekly_slot_share - (count of open rows for that account)`.

By convention, `weekly_slot_share` values across all accounts in `config/accounts.json` should sum to 14 (the user's target total standing pool), but each account's own share is what actually drives its shortfall — there's no cross-account rebalancing.

## Steps

1. **Read the full sheet**: `tools/Read-ScheduleSheet.ps1` (no `-DueOnly` — we need every row to count what's open).
2. **Compute shortfall per account**: group rows by `account`, count open ones, subtract from each account's `weekly_slot_share` in `config/accounts.json`. Skip any account where the shortfall is `<= 0`.
3. **For each account with a shortfall**, spawn a research sub-agent via the `Agent` tool (`subagent_type: general-purpose`, needs `WebSearch`/`WebFetch`, `run_in_background: false` — the plan needs the results before writing to the sheet). Brief it with:
   - The account's `niche` (e.g. "travel & adventure", "tech gadget reviews").
   - The ask: research what's currently trending in this niche right now — most-viewed videos this week, creators gaining traction, recurring formats/concepts/hooks (check YouTube trending, TikTok trending, Instagram Reels trends, general "most viewed this week [niche]" searches).
   - The deliverable: exactly `<shortfall>` distinct, specific, non-generic post topics/concepts suitable for a short-form video in this niche, each with a one-line rationale citing what's trending (not just "post about travel" — something like "Comparing overlooked Greek islands to Santorini — riding the 'hidden gem' travel format trending on Reels this week").
4. **Turn proposals into rows**: for each proposed topic, generate a new `post_id` (next unused `P####`), pick a `scheduled_datetime` spread sensibly across the coming 7 days for that account (avoid clustering everything on one day), and set `status=Pending`, `notes="auto-scheduled from trend research: <one-line rationale>"`.
5. **Append**: batch all new rows (across all topped-up accounts) into one call to `tools/Append-ScheduleSheetRows.ps1 -RowsJson <json array>`.
6. **Report**: summarize what was added — per account, how many rows and the headline topics — so the user can see the plan without opening the sheet.

## Error handling
If a research sub-agent can't find enough distinct trending angles for the requested shortfall, it's fine to return fewer topics with a note — don't pad with generic filler just to hit the count. Report the actual shortfall covered vs. requested.

## Deferred / not built yet
- Wiring the actual `/schedule` cron trigger against the GitHub repo.
- Any weighting/rebalancing logic beyond each account's own `weekly_slot_share`.

## Learnings (update as quirks are discovered — good search queries per niche, timing, etc.)
_(none yet)_
