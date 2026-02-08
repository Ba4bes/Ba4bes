# GitHub Profile Mood Poodle Implementation Plan

Create an interactive poodle that reflects GitHub activity and allows visitors to interact through issues. Uses PowerShell scripts triggered by GitHub Actions, following existing code patterns from Get-RandomPost.ps1.

## Mood Calculation Timing

The scheduled workflow runs **every 6 hours** (0:00, 6:00, 12:00, 18:00 UTC). At each calculation:
- Contribution data is fetched fresh from GitHub API
- Interaction points **decay by 1 point per calculation** (so ~4 points/day fade)
- This means visitors need to keep interacting to maintain high happiness, but contributions are the stable baseline

## Poodle Image Specifications

Create **5 images** for Assets/:

| File Name | Mood | Visual Description | When Shown |
|-----------|------|-------------------|------------|
| `poodle-sad.png` | 😢 Sad | Droopy ears, lying down, maybe a tear or rain cloud | No contributions in 7+ days, low interaction |
| `poodle-bored.png` | 😐 Bored | Sitting, yawning or looking away, neutral posture | Some activity but sparse (3-7 days idle) |
| `poodle-content.png` | 🙂 Content | Standing/sitting alert, slight tail wag, calm expression | Regular activity, baseline happy |
| `poodle-happy.png` | 😊 Happy | Tail wagging, tongue out, playful stance | Active contributions + some interactions |
| `poodle-ecstatic.png` | 🎉 Ecstatic | Jumping/spinning, hearts or sparkles, maximum joy | Very active + lots of recent pets/feeds |

**Recommended specs:**
- **Size:** ~300x300px (or similar square/portrait ratio)
- **Format:** PNG with transparent background (works best on dark/light GitHub themes)
- **Style:** Consistent across all 5 (cartoon, realistic, pixel art — your choice!)

## Rate Limiting

Implement **5 interactions per user per 24-hour rolling window**. The state file will track interactions with timestamps.

Script will check: "Has this user interacted 5+ times in the last 24 hours?" → If yes, close issue with friendly "poodle is tired, come back later!" message.

## Implementation Steps

### Step 1: Create placeholder poodle mood images
Add 5 placeholder images to Assets/:
- `poodle-sad.png`
- `poodle-bored.png`
- `poodle-content.png`
- `poodle-happy.png`
- `poodle-ecstatic.png`

### Step 2: Create poodle-state.json
Create initial state file with structure:
- mood score
- decay tracking
- interaction log with timestamps and usernames
- contribution cache

### Step 3: Create Update-PoodleMood.ps1
PowerShell script that:
- Fetches contribution data via GitHub GraphQL API
- Calculates mood based on: days since last commit, contribution count (7/30 days), repo count
- Applies interaction bonus points with decay (-1 per 6hrs)
- Updates README.md poodle section using marker-based replacement
- Updates poodle-state.json

### Step 4: Create Handle-PoodleInteraction.ps1
PowerShell script that:
- Checks rate limit (5/user/day)
- Processes pet/feed action
- Updates state with interaction
- Posts thank-you comment on issue
- Closes the issue

### Step 5: Create .github/workflows/update-poodle-mood.yml
Scheduled workflow:
- Runs every 6 hours (cron: '0 */6 * * *')
- Also manual trigger (workflow_dispatch)
- Runs Update-PoodleMood.ps1
- Commits changes to README.md and poodle-state.json

### Step 6: Create .github/workflows/poodle-interaction.yml
Issue-triggered workflow:
- Triggers on issues opened with "Poodle" in title
- Runs Handle-PoodleInteraction.ps1
- Commits changes and closes issue

### Step 7: Update README.md
Add poodle section with markers:
- `<!--START_SECTION:poodle-->` and `<!--END_SECTION:poodle-->`
- Mood image (dynamic)
- Status text and reason
- Contribution stats (last contribution date, counts)
- Interaction history (pet/feed counts, recent usernames)
- Pet/Feed links using `../../issues/new?title=...&body=!pet` format
- Short project explanation
