# 🐩 Mood Poodle - Manual Setup Guide

## 📋 Manual Steps Required

### Step 1: Enable GitHub Actions Permissions

**This MUST be done first or the workflows won't work!**

1. Go to your profile repository on GitHub (`https://github.com/<your-username>/<your-username>`)
2. Click **Settings** tab
3. Navigate to **Actions** → **General** (left sidebar)
4. Under **Workflow permissions**, select:
   - ✅ **"Read and write permissions"**
   - ✅ **"Allow GitHub Actions to create and approve pull requests"**
5. Click **Save**

### Step 2: Add Poodle Section to README.md

Add this section to your `README.md` where you want the poodle to appear:

```markdown
## 🐩 Mood Poodle 🐩

<div align="center">

<img src="Assets/poodle-content.png" alt="content poodle" width="200">

### 🙂 **CONTENT** 🙂
**Mood Score:** 50/100

*Waiting for first contribution*

---

📊 **Interaction Stats**
| Type | Count |
|------|-------|
| Pets received | 0 |
| Treats received | 0 |

**Recent visitors:** No one yet!

---

### Want to make the poodle happier?

Comment on the [🐩 Poodle Interaction issue](../../issues?q=is%3Aissue+is%3Aopen+Poodle+in%3Atitle) with:
- `!pet` - Give the poodle some pets 🐾
- `!feed` - Give the poodle a treat 🍖

---

📊 **Contribution Stats**
| Metric | Value |
|--------|-------|
| Last Contribution | Never |
| Contributions (7 days) | 0 |
| Contributions (30 days) | 0 |
| Repositories | 0 |

</div>
<!--END_SECTION:poodle-->
```

⚠️ **Critical:** The `<!--END_SECTION:poodle-->` comment is required! The script uses this marker to know where to update content.

### Step 3: Create the Poodle Interaction Issue

This is a **required manual step** - you must create this issue for interactions to work!

1. Go to your profile repository on GitHub
2. Click the **Issues** tab
3. Click **New Issue**
4. **Title:** `🐩 Poodle Interaction` 
   - ⚠️ Must contain the word "Poodle" (case-sensitive)
5. **Body:** Paste this template:
```markdown
# 🐩 Welcome to the Poodle Interaction Zone! 🐩

Want to make the poodle happier? Leave a comment with one of these commands:

- `!pet` - Give the poodle some pets 🐾 (+3 mood points)
- `!feed` - Give the poodle a treat 🍖 (+3 mood points)

## Rules:
- You can interact up to **5 times per 24-hour period**
- The poodle's mood is also influenced by the repository owner's GitHub activity
- Mood decays slowly over time, so keep coming back!

## Current Status:
Check the [README](../README.md) to see the poodle's current mood!
```

6. Click **Submit new issue**
7. **Pin this issue:** Click the pin icon (📌) in the right sidebar
   - This keeps it visible at the top of your issues list

### Step 4: Manually Test the Workflows

After pushing your code to GitHub, test that everything works:

#### Test the Mood Update

1. Go to **Actions** tab in your repository
2. Click **Update Poodle Mood** workflow (left sidebar)
3. Click **Run workflow** dropdown (right side)
4. Click **Run workflow** button
5. Wait 20-30 seconds for completion
6. Go to your README.md - it should be updated!

#### Test the Interaction Handler

1. Go to your **🐩 Poodle Interaction** issue
2. Leave a comment: `!pet`
3. Wait 10-20 seconds
4. You should receive a thank-you comment from `github-actions[bot]`
5. Check your README - the interaction stats should update

---

## 🎨 Optional Customization

### Adjust Mood Calculation Parameters

Edit [Update-PoodleMood.ps1](Update-PoodleMood.ps1):

**Line 11 - Decay rate:**
```powershell
$DecayPerCycle = 1  # Change to 0.5 for slower decay, 2 for faster
```

**Lines 14-20 - Mood thresholds:**
```powershell
$MoodConfig = @{
    sad      = @{ min = 0;  max = 20;  ... }  # Adjust ranges
    bored    = @{ min = 21; max = 40;  ... }
    content  = @{ min = 41; max = 60;  ... }
    happy    = @{ min = 61; max = 80;  ... }
    ecstatic = @{ min = 81; max = 100; ... }
}
```

### Adjust Interaction Limits

Edit [Handle-PoodleInteraction.ps1](Handle-PoodleInteraction.ps1):

**Line 77 - Interactions per day:**
```powershell
$script:MaxInteractionsPerDay = 5  # Change to 10 for more lenient
```

**Line 78 - Rolling window:**
```powershell
$script:RollingWindowHours = 24  # Change to 12 for 12-hour window
```

**Line 79 - Points per interaction:**
```powershell
$script:BonusPerInteraction = 3  # Change to 5 for bigger mood boost
```

### Adjust Update Frequency

Edit [.github/workflows/update-poodle-mood.yml](.github/workflows/update-poodle-mood.yml):

**Line 5-6 - Schedule:**
```yaml
- cron: '0 */6 * * *'  # Every 6 hours (default)
```

Change to:
```yaml
- cron: '0 */3 * * *'  # Every 3 hours
# or
- cron: '0 0 * * *'    # Once daily at midnight UTC
# or
- cron: '0 */12 * * *' # Every 12 hours
```

### Customize Response Messages

Edit [Handle-PoodleInteraction.ps1](Handle-PoodleInteraction.ps1) around **lines 268-288** to change bot responses:

```powershell
# Pet response (around line 273)
$responses = @(
    "🐾 Thank you for the pets! The poodle is wagging its tail! 🐩",
    "Your custom message here!",
    # Add more variations
)

# Feed response (around line 283)
$responses = @(
    "🍖 Yum! The poodle enjoyed that treat! 🐩",
    "Your custom message here!",
    # Add more variations
)
```

---

## 🐛 Troubleshooting

### ❌ Workflow Not Running

**Check GitHub Actions is enabled:**
1. Go to repository **Settings** → **Actions** → **General**
2. Under **Actions permissions**, ensure **"Allow all actions and reusable workflows"** is selected
3. Click **Save**

**Check workflow permissions:**
1. Settings → Actions → General → **Workflow permissions**
2. Select **"Read and write permissions"**
3. Enable **"Allow GitHub Actions to create and approve pull requests"**
4. Click **Save**

### ❌ Poodle Not Updating in README

**Verify the marker comment exists:**
- Ensure `<!--END_SECTION:poodle-->` is present in your README.md
- Everything between `## 🐩 Mood Poodle` and this marker will be replaced
- The marker must be **exactly** as shown (case-sensitive)

**Check workflow execution:**
1. Go to **Actions** tab
2. Click on the failed workflow run
3. Expand the failed step
4. Read error messages for clues

**Common issues:**
- Missing `<!--END_SECTION:poodle-->` marker
- Typo in the marker comment
- README.md not committed to repository

### ❌ Interactions Not Working

**Issue title requirements:**
- Must contain the word **"Poodle"** (case-sensitive)
- Example: `🐩 Poodle Interaction` ✅
- Example: `poodle interaction` ❌ (lowercase won't work)

**Command requirements:**
- Must be **exactly** `!pet` or `!feed` (case-sensitive)
- No extra spaces: `!pet ` won't work
- Must be on its own line or as the only content

**Rate limiting:**
- Users can only interact **5 times per 24 hours**
- Check if the user has hit their limit
- The bot will respond with time remaining if limited

**Check workflow logs:**
1. Actions → Poodle Interaction workflow
2. Click the specific run
3. Check for error messages

### ❌ Bot Not Responding to Comments

**Verify the workflow is triggered:**
1. Actions tab → Check if "Poodle Interaction" workflow ran
2. If it didn't run, check:
   - Issue title contains "Poodle"
   - Comment wasn't from `github-actions[bot]` itself
   - Workflow permissions are set correctly

**Check the comment content:**
- Must contain `!pet` or `!feed` exactly
- Bot ignores comments without these commands

### ❌ Permission Errors

**Error: "Resource not accessible by integration"**

Fix:
1. Settings → Actions → General → Workflow permissions
2. Select **"Read and write permissions"**
3. Enable **"Allow GitHub Actions to create and approve pull requests"**
4. Save changes
5. Re-run the workflow

### ❌ Mood Score Stuck at 50

**First run issue:**
- The first mood update needs to fetch your contribution data
- Wait for the next scheduled update (every 6 hours)
- Or manually trigger: Actions → Update Poodle Mood → Run workflow

**No contributions:**
- If you have no recent GitHub activity, score will be low
- Interact with the poodle to boost the mood!
- Make some commits to your repositories

### 🧪 Testing Locally

Test scripts locally before pushing:

**Test mood update:**
```powershell
# Set environment variables
$env:GITHUB_TOKEN = "ghp_your_token_here"
$env:GITHUB_REPOSITORY_OWNER = "your_username"

# Run with verbose output
./Update-PoodleMood.ps1 -Verbose
```

**Test interaction handler:**
```powershell
# Set environment variables
$env:GITHUB_TOKEN = "ghp_your_token_here"
$env:ISSUE_NUMBER = "1"
$env:INTERACTION_TEXT = "!pet"
$env:INTERACTION_USER = "testuser"
$env:INTERACTION_TYPE = "issue_comment"
$env:GITHUB_REPOSITORY = "your_username/your_username"

# Run with verbose output
./Handle-PoodleInteraction.ps1 -Verbose
```

**Create a GitHub token for testing:**
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token
3. Select scopes: `repo`, `workflow`
4. Copy the token (starts with `ghp_`)

### 📋 Workflow Logs Location

When reporting issues, check these logs:

1. **Actions tab** → Click failed workflow
2. **Update Poodle Mood** logs:
   - Check "Update Poodle Mood" step
   - Look for PowerShell errors
3. **Handle Poodle Interaction** logs:
   - Check "Handle Poodle Interaction" step
   - Look for API errors or rate limit messages

### ⏰ Scheduled Updates Not Running

**Verify cron schedule:**
- Default: Every 6 hours (0:00, 6:00, 12:00, 18:00 UTC)
- GitHub Actions may delay scheduled runs by up to 10 minutes
- First run may take up to 1 hour after workflow creation

**Force a manual run:**
1. Actions → Update Poodle Mood
2. Run workflow → Run workflow
3. Wait for completion

### 🔄 Reset Poodle State

If you need to start fresh:

1. Delete `poodle-state.json` from your repository
2. Push the change
3. Manually run "Update Poodle Mood" workflow
4. A new state file will be created automatically

Or edit `poodle-state.json` directly to reset specific values.

---

## 📚 Additional Notes

**Automatic update schedule:**
- Every 6 hours: 00:00, 06:00, 12:00, 18:00 UTC
- Can be triggered manually anytime from Actions tab

**Mood calculation:**
- Base score (0-50): Based on your GitHub contributions
- Interaction bonus (0-50): Based on pet/feed interactions
- Total mood (0-100): Base + Bonus
- Bonus decays by 1 point every 6 hours

**Rate limiting:**
- 5 interactions per user per 24-hour rolling window
- Window resets 24 hours after each individual interaction
- Not a daily reset at midnight

---

**Questions or issues?** Open an issue in the Ba4bes/Ba4bes repository!
