# Workflow: Social Media Post Pipeline

## Objective
For every due post in the Schedule sheet, generate an on-brand image and video via Higgsfield, gate the image through an authenticity review agent before spending credits on video, attach an appealing title and the account's steady hashtag set, and email the result to the user for manual approval before anything goes live.

## Trigger
Invoked periodically (target cadence: every 30-60 minutes) via an Anthropic `/schedule` cloud agent connected to this project's GitHub repo. Until that's wired up, run this manually by asking the agent to "process due posts."

## Requirements
All `tools/*.ps1` scripts require **PowerShell 7+** (`pwsh`), not Windows PowerShell 5.1 — Google service-account JWT signing depends on `RSA.ImportFromPem`, which only exists on modern PowerShell. This also matches whatever the `/schedule` cloud agent's sandbox needs, since Windows PowerShell 5.1 doesn't exist outside Windows.

## Inputs
- Google Sheet (`Schedule` tab) — see schema below. Sheet ID comes from `GOOGLE_SHEET_ID` in `.env`.
- `config/accounts.json` — per-account `platform`, `niche`, `hashtags` (steady set), `weekly_slot_share`, `credentials_note`.
- `.env` — `GOOGLE_SHEET_ID`; `RESEND_API_KEY`/`RESEND_FROM`/`REVIEW_EMAIL_TO` for the review email (Resend, not SMTP — Microsoft has hard-disabled basic SMTP AUTH for personal Outlook accounts); (future) `IG_ACCESS_TOKEN` / `IG_BUSINESS_ACCOUNT_ID`.
- `service-account.json` at the project root — Google service account key (see `tools/Common.ps1`'s `Get-ServiceAccountKeyPath`). No browser consent flow: the Sheet is simply shared with the key's `client_email` as an Editor.

## Sheet schema (`Schedule` tab, columns A:J)

| Column | Meaning |
|---|---|
| post_id | unique id, e.g. `P0001` |
| account | key into `config/accounts.json` |
| topic | what the post should be about |
| scheduled_datetime | when it should post, format `YYYY-MM-DD HH:mm` |
| status | see status flow below |
| title | filled by this pipeline |
| hashtags | filled by this pipeline (copied from the account's steady set) |
| image_path | local path to the approved image |
| video_path | local path to the generated video |
| notes | review reasoning, rejection reasons, errors |

Status flow: `Pending` (or blank) → `ImageGenerating` → (`ImageRejected-Retry`)\* → `VideoGenerating` → `AwaitingUserReview` → `Approved` / `Rejected` → `ReadyToPublish-ManualAction` / `Published`, or `Failed` at any point.

A row is **due** when `status` is blank/`Pending` and `scheduled_datetime <= now`.

## Steps

1. **Read due posts**: run `tools/Read-ScheduleSheet.ps1 -DueOnly`. If empty, stop — nothing to do.
2. For each due post, process one at a time:
   1. **Claim it**: `tools/Update-ScheduleSheetRow.ps1 -PostId <id> -Status ImageGenerating` (prevents double-processing if this workflow is accidentally triggered twice).
   2. **Look up the account**: read `config/accounts.json`. If `account` isn't a key there, `-Status Failed -Notes "Unknown account '<account>'"`, and move to the next post.
   3. **Title** (agent reasoning, not a tool call): write a short, appealing, platform-appropriate title from `topic`.
   4. **Hashtags**: copy the account's `hashtags` field verbatim — this set is intentionally steady across posts for brand consistency, not regenerated per post.
   5. **Generate the image**:
      - Call `mcp__claude_ai_Higgsfield__models_explore` (`action:"recommend"`, `input:"text"`, `type:"image"`) with the topic/niche as context to pick a model. Default to `soul_2` for photorealistic/UGC-style content, `nano_banana_pro` if the topic is text- or diagram-heavy.
      - Call `mcp__claude_ai_Higgsfield__generate_image` with a prompt built from `topic` + `title` + the account's niche.
      - Poll `mcp__claude_ai_Higgsfield__job_status` until terminal (respect `poll_after_seconds`).
      - Download the result to `.tmp/posts/<post_id>/image.png` via `tools/Download-File.ps1`.
   6. **Authenticity review — the "additional agent"**: spawn a sub-agent via the `Agent` tool (`subagent_type: general-purpose`, `run_in_background: false` — the pipeline must block on the verdict). Give it:
      - The local path `.tmp/posts/<post_id>/image.png` to `Read`.
      - The rubric: does it look authentic/photographic (not uncanny-valley or "AI-plastic"), free of anatomical/object/text artifacts, on-topic for "`<topic>`", and suitable for `<platform>`.
      - Instruction to answer strictly `APPROVE` or `REJECT` plus one paragraph of reasoning.
      - Write the verdict + reasoning to the sheet's `notes` column via `Update-ScheduleSheetRow.ps1`.
      - **REJECT** → regenerate with an adjusted prompt (address the specific complaint), up to **3 attempts total**. Still rejected after 3 → `-Status Failed -Notes "<final rejection reason>"`, move to the next post.
      - **APPROVE** → continue.
   7. `Update-ScheduleSheetRow.ps1 -Status VideoGenerating`.
   8. **Generate the video**:
      - `models_explore` to pick a model — default `kling3_0_turbo` for single-start-frame animation.
      - `generate_video` with `medias:[{value:<approved image job_id>, role:"image"}]`, `aspect_ratio:"9:16"` (Reels/Shorts vertical format unless the account's niche calls for landscape).
      - Poll `job_status` until terminal.
      - Download to `.tmp/posts/<post_id>/video.mp4` via `Download-File.ps1`.
   9. `Update-ScheduleSheetRow.ps1 -Status AwaitingUserReview -Title <title> -Hashtags <hashtags> -ImagePath <path> -VideoPath <path>`.
   10. **Send for review**: `tools/Send-ReviewEmail.ps1` with the post details and both attachments. There is no inbound-reply parsing — the user approves by editing the `status` cell in the sheet directly (see "Approval flow" below).
3. **Publish gate** (checked every run, independent of step 2, for any row already `status=Approved`):
   - Credentials for Instagram (`IG_ACCESS_TOKEN`, `IG_BUSINESS_ACCOUNT_ID`) and YouTube (OAuth) are not yet configured.
   - `Update-ScheduleSheetRow.ps1 -Status ReadyToPublish-ManualAction -Notes "<which credentials are missing>"`.
   - Actual `Publish-Instagram.ps1` / `Publish-YouTube.ps1` are out of scope until credentials exist — build them then, not before.

## Approval flow (important)
Email has no inbound listener. "Sending for review" = attaching the assets and waiting. The user reviews the email, then edits the `status` cell for that `post_id` directly in the Google Sheet to `Approved` or `Rejected`. The next run of this workflow (step 3) picks up `Approved` rows.

## Error handling
Any Higgsfield job failure/timeout, unknown account, or exhausted review-retry budget → `status=Failed`, `notes=<reason>`, continue with the next post. Do not retry beyond the documented budget; a `Failed` row needs human attention (re-run manually after investigating, or fix `accounts.json`/topic and reset status to `Pending`).

## Deferred / not built yet
- Wiring the actual `/schedule` cron trigger against the GitHub repo (do this once this pipeline has been run manually at least once).
- `Publish-Instagram.ps1` / `Publish-YouTube.ps1` real implementations (blocked on credentials).
- Any automated parsing of email replies.

## Learnings (update this section as quirks are discovered — rate limits, timing, prompt tuning, etc.)
_(none yet)_
