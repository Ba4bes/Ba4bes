<#
.SYNOPSIS
    Processes pet/feed interactions for the Mood Poodle from GitHub issues or comments.

.DESCRIPTION
    This script handles poodle interactions triggered by GitHub issues or comments on a pinned poodle issue.
    Users can comment "!pet" or "!feed" on the poodle issue to interact.
    It implements rate limiting (5 interactions per user per 24-hour rolling window),
    processes pet/feed actions, updates the poodle state, and posts thank-you comments.

.PARAMETER GitHubToken
    The GitHub token for API authentication. Defaults to GITHUB_TOKEN environment variable.

.PARAMETER IssueNumber
    The issue number that triggered the interaction. Defaults to ISSUE_NUMBER environment variable.

.PARAMETER IssueTitle
    The title of the triggering issue. Defaults to ISSUE_TITLE environment variable.

.PARAMETER InteractionText
    The text containing the interaction command (from issue body or comment). Defaults to INTERACTION_TEXT environment variable.

.PARAMETER InteractionUser
    The username who triggered the interaction. Defaults to INTERACTION_USER environment variable.

.PARAMETER InteractionType
    The type of trigger: 'issues' for new issue, 'issue_comment' for comment. Defaults to INTERACTION_TYPE environment variable.

.PARAMETER Repository
    The repository in owner/repo format. Defaults to GITHUB_REPOSITORY environment variable.

.EXAMPLE
    ./Handle-PoodleInteraction.ps1

    Runs with all parameters from environment variables (typical GitHub Actions usage).

.EXAMPLE
    ./Handle-PoodleInteraction.ps1 -InteractionText "!pet" -InteractionUser "octocat" -Verbose

    Runs with explicit parameters for testing.

.NOTES
    This script is designed to be run by GitHub Actions when:
    - An issue with "Poodle" in the title is opened
    - A comment is added to an issue with "Poodle" in the title
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$IssueNumber = $env:ISSUE_NUMBER,

    [Parameter()]
    [string]$IssueTitle = $env:ISSUE_TITLE,

    [Parameter()]
    [string]$InteractionText = $env:INTERACTION_TEXT,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InteractionUser = $env:INTERACTION_USER,

    [Parameter()]
    [ValidateSet('issues', 'issue_comment', '')]
    [string]$InteractionType = $env:INTERACTION_TYPE,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = $env:GITHUB_REPOSITORY
)

# Configuration
$script:StateFile = './poodle-state.json'
$script:ReadmeFile = './README.md'
$script:MaxInteractionsPerDay = 5
$script:RollingWindowHours = 24
$script:BonusPerInteraction = 3  # Points added per pet/feed
$script:CooldownStackBonus = 5   # Points added to base score after cooldown per interaction

# Mood configuration
$script:MoodConfig = @{
    sad      = @{ min = 0; max = 20; image = "Assets/poodle-sad.png"; emoji = "😢" }
    bored    = @{ min = 21; max = 40; image = "Assets/poodle-bored.png"; emoji = "😐" }
    content  = @{ min = 41; max = 60; image = "Assets/poodle-content.png"; emoji = "🙂" }
    happy    = @{ min = 61; max = 80; image = "Assets/poodle-happy.png"; emoji = "😊" }
    ecstatic = @{ min = 81; max = 100; image = "Assets/poodle-ecstatic.png"; emoji = "🎉" }
}

function Update-ReadmePoodleEcstatic {
    <#
    .SYNOPSIS
        Updates the README.md with ecstatic mood immediately after interaction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$InteractingUser
    )

    $moodInfo = $script:MoodConfig['ecstatic']
    $lastContrib = if ($State.contributions.lastContributionDate) { $State.contributions.lastContributionDate } else { "Never" }

    # Get recent interaction usernames (last 5 unique)
    $recentUsers = $State.interactions.log | 
        Sort-Object timestamp -Descending | 
        Select-Object -ExpandProperty username -Unique | 
        Select-Object -First 5
    $recentUsersText = if ($recentUsers) { ($recentUsers | ForEach-Object { "@$_" }) -join ", " } else { "No one yet!" }

    $poodleSection = @"
<!--START_SECTION:poodle-->
<div align="center">

## 🐩 Mood Poodle 🐩

<img src="$($moodInfo.image)" alt="ecstatic poodle" width="200">

### $($moodInfo.emoji) **ECSTATIC** $($moodInfo.emoji)
**Mood Score:** 100/100

*Just received love from @$InteractingUser! 🎉*

---

📊 **Contribution Stats**
| Metric | Value |
|--------|-------|
| Last Contribution | $lastContrib |
| Contributions (7 days) | $($State.contributions.count7Days) |
| Contributions (30 days) | $($State.contributions.count30Days) |
| Repositories | $($State.contributions.repoCount) |

🐾 **Interaction Stats**
| Type | Count |
|------|-------|
| Pets received | $($State.interactions.totalPets) |
| Treats received | $($State.interactions.totalFeeds) |

**Recent visitors:** $recentUsersText

---

### Want to make the poodle happier?

Comment on the [🐩 Poodle Interaction issue](../../issues?q=is%3Aissue+is%3Aopen+Poodle+in%3Atitle) with:
- ``!pet`` - Give the poodle some pets 🐾
- ``!feed`` - Give the poodle a treat 🍖

<sub>*The poodle is ecstatic! Mood will settle in ~10 minutes.*</sub>

</div>
<!--END_SECTION:poodle-->
"@

    $readme = Get-Content $script:ReadmeFile -Raw
    $pattern = '(?s)<!--START_SECTION:poodle-->.*<!--END_SECTION:poodle-->'

    if ($readme -match $pattern) {
        $newReadme = $readme -replace $pattern, $poodleSection
    }
    else {
        $newReadme = $readme + "`n`n" + $poodleSection
    }

    Set-Content -Path $script:ReadmeFile -Value $newReadme -NoNewline
    Write-Verbose "README.md updated with ecstatic mood!"
}

function Add-GitHubIssueComment {
    <#
    .SYNOPSIS
        Posts a comment to a GitHub issue.

    .DESCRIPTION
        Uses the GitHub API to add a comment to the specified issue.

    .PARAMETER Token
        The GitHub authentication token.

    .PARAMETER RepositoryName
        The repository in owner/repo format.

    .PARAMETER IssueNumber
        The issue number to comment on.

    .PARAMETER Comment
        The comment text to post.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IssueNumber,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Comment
    )

    Write-Verbose "Preparing to post comment to issue #$IssueNumber"

    $headers = @{
            'Authorization' = "Bearer $Token"
            'Accept'        = 'application/vnd.github.v3+json'
        }

        $body = @{ body = $Comment } | ConvertTo-Json
        $uri = "https://api.github.com/repos/$RepositoryName/issues/$IssueNumber/comments"

        try {
            $null = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
            Write-Verbose "Comment posted to issue #$IssueNumber"
        }
    catch {
        Write-Warning "Failed to post comment to issue #$IssueNumber`: $_"
    }
}

function Close-GitHubIssue {
    <#
    .SYNOPSIS
        Closes a GitHub issue.

    .DESCRIPTION
        Uses the GitHub API to close the specified issue.

    .PARAMETER Token
        The GitHub authentication token.

    .PARAMETER RepositoryName
        The repository in owner/repo format.

    .PARAMETER IssueNumber
        The issue number to close.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IssueNumber
    )

    Write-Verbose "Preparing to close issue #$IssueNumber"

    $headers = @{
            'Authorization' = "Bearer $Token"
            'Accept'        = 'application/vnd.github.v3+json'
        }

        $body = @{ state = 'closed' } | ConvertTo-Json
        $uri = "https://api.github.com/repos/$RepositoryName/issues/$IssueNumber"

        try {
            $null = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body -ErrorAction Stop
            Write-Verbose "Issue #$IssueNumber closed"
        }
    catch {
        Write-Warning "Failed to close issue #$IssueNumber`: $_"
    }
}

# Main execution
$isComment = $InteractionType -eq 'issue_comment'
Write-Verbose '🐩 Processing Poodle Interaction...'
Write-Verbose "Issue #$IssueNumber - $(if ($isComment) { 'Comment' } else { 'New Issue' }) by @$InteractionUser"
Write-Verbose "Text: $InteractionText"

# Load state
if (-not (Test-Path -Path $script:StateFile)) {
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.IO.FileNotFoundException]::new("State file not found: $script:StateFile"),
        'StateFileNotFound',
        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
        $script:StateFile
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}

$state = Get-Content -Path $script:StateFile -Raw | ConvertFrom-Json

# Ensure rateLimits exists as object
if (-not $state.rateLimits) {
    $state | Add-Member -NotePropertyName 'rateLimits' -NotePropertyValue ([PSCustomObject]@{}) -Force
}

# Determine interaction type from the interaction text
$textToCheck = ($InteractionText ?? '').ToLower()
$interactionAction = $null

if ($textToCheck -match '!pet|pet the poodle|poodle pet') {
    $interactionAction = 'pet'
}
elseif ($textToCheck -match '!feed|feed the poodle|poodle feed|!treat|treat') {
    $interactionAction = 'feed'
}

if (-not $interactionAction) {
    Write-Verbose 'Not a valid poodle interaction, posting help message'
    $helpMessage = @'
🐩 *confused poodle noises*

I don't understand what you want me to do! Try commenting:
- `!pet` - Give the poodle some pets
- `!feed` - Give the poodle a treat

🐾 The poodle is waiting for your love!
'@
    Add-GitHubIssueComment -Token $GitHubToken -RepositoryName $Repository -IssueNumber $IssueNumber -Comment $helpMessage
    # Only close if it's a new issue, not a comment
    if (-not $isComment) {
        Close-GitHubIssue -Token $GitHubToken -RepositoryName $Repository -IssueNumber $IssueNumber
    }
    exit 0
}

Write-Verbose "Interaction action: $interactionAction"

# Check rate limit for user
$now = Get-Date
$windowStart = $now.AddHours(-$script:RollingWindowHours)
$rateLimitAllowed = $true
$rateLimitRemaining = $script:MaxInteractionsPerDay

if ($state.rateLimits.$InteractionUser) {
    $recentInteractions = $state.rateLimits.$InteractionUser | Where-Object {
        [datetime]$_ -gt $windowStart
    }
    $interactionCount = @($recentInteractions).Count
    $rateLimitRemaining = $script:MaxInteractionsPerDay - $interactionCount
    $rateLimitAllowed = $rateLimitRemaining -gt 0
    $rateLimitRemaining = [Math]::Max(0, $rateLimitRemaining)
}

if (-not $rateLimitAllowed) {
    Write-Verbose "Rate limit exceeded for @$InteractionUser"
    $rateLimitMessage = @"
🐩💤 *The poodle is tired from all the attention!*

Thanks for wanting to interact, @$InteractionUser, but you've already interacted **$($script:MaxInteractionsPerDay) times** in the last $($script:RollingWindowHours) hours.

Come back later when the poodle has had some rest! 🐾
"@
    Add-GitHubIssueComment -Token $GitHubToken -RepositoryName $Repository -IssueNumber $IssueNumber -Comment $rateLimitMessage
    exit 0
}

# Process the interaction
$remainingAfterThis = $rateLimitRemaining - 1
Write-Verbose "Processing $interactionAction from @$InteractionUser (remaining: $remainingAfterThis)"

# Update interaction stats
if ($interactionAction -eq 'pet') {
    $state.interactions.totalPets++
    $emoji = '🐾'
    $actionWord = 'pet'
    $response = 'loves the gentle pets'
}
else {
    $state.interactions.totalFeeds++
    $emoji = '🍖'
    $actionWord = 'treat'
    $response = 'happily munches on the treat'
}

# Add to interaction log
$logEntry = [PSCustomObject]@{
    username  = $InteractionUser
    type      = $interactionAction
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    issueNum  = [int]$IssueNumber
}

# Ensure log is an array
if (-not $state.interactions.log) {
    $state.interactions | Add-Member -NotePropertyName 'log' -NotePropertyValue @() -Force
}
$state.interactions.log = @($state.interactions.log) + $logEntry

# Keep only last 100 log entries
if ($state.interactions.log.Count -gt 100) {
    $state.interactions.log = $state.interactions.log | Select-Object -Last 100
}

# Add interaction bonus
$state.decay.interactionBonus = [int]$state.decay.interactionBonus + $script:BonusPerInteraction

# Handle ecstatic cooldown for instant gratification
# Ensure cooldown object exists
if (-not $state.cooldown) {
    $state | Add-Member -NotePropertyName 'cooldown' -NotePropertyValue ([PSCustomObject]@{
        active = $false
        preInteractionScore = $null
        stackedBonus = 0
        triggeredAt = $null
    }) -Force
}

$nowUtcCooldown = (Get-Date).ToUniversalTime().ToString('o')
if (-not $state.cooldown.active) {
    # First interaction - store current score and activate cooldown
    $state.cooldown.preInteractionScore = [int]$state.mood.score
    $state.cooldown.stackedBonus = $script:CooldownStackBonus
    $state.cooldown.active = $true
    $state.cooldown.triggeredAt = $nowUtcCooldown
    Write-Verbose "Cooldown activated - stored pre-interaction score: $($state.cooldown.preInteractionScore)"
}
else {
    # Already in cooldown - stack the bonus
    $state.cooldown.stackedBonus = [int]$state.cooldown.stackedBonus + $script:CooldownStackBonus
    # Reset the cooldown timer for stacked interactions
    $state.cooldown.triggeredAt = $nowUtcCooldown
    Write-Verbose "Cooldown bonus stacked - total bonus: $($state.cooldown.stackedBonus)"
}

# Set poodle to ecstatic immediately
$state.mood.score = 100
$state.mood.state = 'ecstatic'
Write-Verbose 'Poodle mood set to ecstatic (100)!'

# Add rate limit entry for user
$nowUtc = (Get-Date).ToUniversalTime().ToString('o')
if (-not $state.rateLimits.$InteractionUser) {
    $state.rateLimits | Add-Member -NotePropertyName $InteractionUser -NotePropertyValue @($nowUtc) -Force
}
else {
    # Clean old entries and add new one
    $entries = @($state.rateLimits.$InteractionUser | Where-Object { [datetime]$_ -gt $windowStart })
    $entries += $nowUtc
    $state.rateLimits.$InteractionUser = $entries
}

# Save state
$state | ConvertTo-Json -Depth 10 | Set-Content -Path $script:StateFile
Write-Verbose 'State updated'

# Update README immediately to show ecstatic mood
Update-ReadmePoodleEcstatic -State $state -InteractingUser $InteractionUser

# Post thank you comment
$thankYouComment = @"
$emoji **Thank you for the $actionWord, @$InteractionUser!** $emoji

*The poodle $response and is now ECSTATIC!* 🐩🎉✨

**Your interaction has been recorded:**
- Interaction bonus: +$($script:BonusPerInteraction) points
- Remaining interactions today: $remainingAfterThis/$($script:MaxInteractionsPerDay)

The poodle's mood will update in the README momentarily!

---
*Total pets received: $($state.interactions.totalPets) | Total treats received: $($state.interactions.totalFeeds)*
"@

Add-GitHubIssueComment -Token $GitHubToken -RepositoryName $Repository -IssueNumber $IssueNumber -Comment $thankYouComment

# Output for GitHub Actions to know cooldown workflow should be triggered
Write-Output "TRIGGER_COOLDOWN=true"

Write-Verbose '✅ Interaction processed successfully!'
