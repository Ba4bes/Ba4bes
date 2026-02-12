<#
.SYNOPSIS
    Updates the poodle mood based on GitHub contributions and interaction history.

.DESCRIPTION
    This script fetches GitHub contribution data using the GraphQL API, applies decay to interaction bonuses,
    calculates a mood score (0-100), determines the poodle's emotional state, and updates the README.md
    with the current mood, contribution stats, and interaction history.
    
    The mood is calculated based on:
    - Days since last contribution (negative impact)
    - 7-day and 30-day contribution counts (positive impact)
    - Repository count (positive impact)
    - Interaction bonus from pets/feeds (positive impact, decays over time)
    
    Runs every 6 hours via GitHub Actions scheduled workflow.

.PARAMETER GitHubToken
    The GitHub token for API authentication. Defaults to GITHUB_TOKEN environment variable.

.PARAMETER GitHubUser
    The GitHub username to fetch contributions for. Defaults to GITHUB_REPOSITORY_OWNER environment variable.

.EXAMPLE
    ./Update-PoodleMood.ps1
    
    Runs with all parameters from environment variables (typical GitHub Actions usage).

.EXAMPLE
    ./Update-PoodleMood.ps1 -GitHubToken 'ghp_xxx' -GitHubUser 'Ba4bes' -Verbose
    
    Runs with explicit parameters and verbose output for testing.

.NOTES
    This script is designed to be run by GitHub Actions on a schedule.
    It requires a GitHub token with read permissions for user data and contributions.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    
    [Parameter()]
    [string]$GitHubUser = $env:GITHUB_REPOSITORY_OWNER
)

# Configuration
$StateFile = "./poodle-state.json"
$ReadmeFile = "./README.md"
$DecayPerCycle = 1  # Interaction bonus decay per 6-hour cycle

# Mood thresholds and images
$MoodConfig = @{
    sad      = @{ min = 0; max = 20; image = "Assets/poodle-sad.png"; emoji = "😢" }
    bored    = @{ min = 21; max = 40; image = "Assets/poodle-bored.png"; emoji = "😐" }
    content  = @{ min = 41; max = 60; image = "Assets/poodle-content.png"; emoji = "🙂" }
    happy    = @{ min = 61; max = 80; image = "Assets/poodle-happy.png"; emoji = "😊" }
    ecstatic = @{ min = 81; max = 100; image = "Assets/poodle-ecstatic.png"; emoji = "🎉" }
}

function Get-GitHubContributions {
    <#
    .SYNOPSIS
        Fetches GitHub contribution data via GraphQL API.
    
    .DESCRIPTION
        Queries the GitHub GraphQL API to retrieve contribution calendar data and repository count
        for a specified user.
    
    .PARAMETER Token
        The GitHub authentication token.
    
    .PARAMETER Username
        The GitHub username to fetch contributions for.
    
    .OUTPUTS
        PSCustomObject containing contribution data, or $null if the request fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token,
        
        [Parameter(Mandatory)]
        [string]$Username
    )

    Write-Verbose "Fetching GitHub contributions for user: $Username"
    
    $query = @"
{
  user(login: "$Username") {
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks {
          contributionDays {
            contributionCount
            date
          }
        }
      }
    }
    repositories(first: 100, ownerAffiliations: OWNER) {
      totalCount
    }
  }
}
"@
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }
    
    $body = @{ query = $query } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/graphql" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Verbose "Successfully fetched contribution data"
        return $response.data.user
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'GitHubApiError',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $Username
        )
        $PSCmdlet.WriteError($errorRecord)
        return $null
    }
}


function Get-ContributionStats {
    <#
    .SYNOPSIS
        Calculates contribution statistics from GitHub contribution data.
    
    .DESCRIPTION
        Processes contribution calendar data to determine last contribution date,
        7-day contribution count, 30-day contribution count, and repository count.
    
    .PARAMETER ContributionData
        The contribution data object returned from Get-GitHubContributions.
    
    .OUTPUTS
        Hashtable containing lastContributionDate, count7Days, count30Days, and repoCount.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$ContributionData
    )
    
    Write-Verbose "Calculating contribution statistics"
    
    if (-not $ContributionData) {
        return @{
            lastContributionDate = $null
            count7Days           = 0
            count30Days          = 0
            repoCount            = 0
        }
    }
    
    $today = (Get-Date).Date
    $allDays = $ContributionData.contributionsCollection.contributionCalendar.weeks | 
    ForEach-Object { $_.contributionDays } | 
    Where-Object { $_.contributionCount -gt 0 }
    
    $lastContribution = $allDays | Sort-Object date -Descending | Select-Object -First 1
    
    $last7Days = $allDays | Where-Object { 
        ([datetime]$_.date).Date -ge $today.AddDays(-6) 
    } | Measure-Object -Property contributionCount -Sum
    
    $last30Days = $allDays | Where-Object { 
        ([datetime]$_.date).Date -ge $today.AddDays(-29) 
    } | Measure-Object -Property contributionCount -Sum
    
    $stats = @{
        lastContributionDate = $lastContribution.date
        count7Days           = [int]$last7Days.Sum
        count30Days          = [int]$last30Days.Sum
        repoCount            = $ContributionData.repositories.totalCount
    }
        
    Write-Verbose "Stats calculated - Last: $($stats.lastContributionDate), 7d: $($stats.count7Days), 30d: $($stats.count30Days), Repos: $($stats.repoCount)"
    return $stats
}


function Get-MoodScore {
    <#
    .SYNOPSIS
        Calculates the poodle mood score (0-100).
    
    .DESCRIPTION
        Computes a mood score based on contribution activity and interaction bonuses.
        Base score is 50, adjusted by:
        - Days since last contribution (negative)
        - 7-day and 30-day contribution counts (positive)
        - Repository count (positive)
        - Interaction bonus from pets/feeds (positive)
    
    .PARAMETER ContributionStats
        Hashtable containing contribution statistics.
    
    .PARAMETER InteractionBonus
        The current interaction bonus points.
    
    .OUTPUTS
        Integer mood score clamped to 0-100.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ContributionStats,
        
        [Parameter()]
        [ValidateRange(0, 1000)]
        [int]$InteractionBonus = 0
    )
    
    Write-Verbose "Calculating mood score with interaction bonus: $InteractionBonus"
    
    $score = 50  # Base score
    
    # Days since last contribution impact (-5 per day, max -40)
    if ($ContributionStats.lastContributionDate) {
        $daysSinceContribution = ((Get-Date) - [datetime]$ContributionStats.lastContributionDate).Days
        $score -= [Math]::Min($daysSinceContribution * 5, 40)
    }
    else {
        $score -= 30  # No contributions found
    }
    
    # Contribution count bonuses
    $score += [Math]::Min($ContributionStats.count7Days * 2, 20)   # Up to +20 for weekly activity
    $score += [Math]::Min($ContributionStats.count30Days / 5, 15) # Up to +15 for monthly activity
    
    # Repo count bonus (up to +10)
    $score += [Math]::Min($ContributionStats.repoCount / 5, 10)
    
    # Add interaction bonus
    $score += $InteractionBonus
    
    # Clamp to 0-100
    $finalScore = [Math]::Max(0, [Math]::Min(100, [int]$score))
    Write-Verbose "Mood score calculated: $finalScore"
    return $finalScore
}


function Get-MoodState {
    <#
    .SYNOPSIS
        Determines the mood state from a score.
    
    .DESCRIPTION
        Maps a numerical mood score (0-100) to a mood state name
        (sad, bored, content, happy, ecstatic).
    
    .PARAMETER Score
        The mood score (0-100).
    
    .OUTPUTS
        String representing the mood state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Score
    )
    
    Write-Verbose "Determining mood state for score: $Score"
    
    foreach ($mood in $MoodConfig.GetEnumerator()) {
        if ($Score -ge $mood.Value.min -and $Score -le $mood.Value.max) {
            Write-Verbose "Mood state determined: $($mood.Key)"
            return $mood.Key
        }
    }
    Write-Verbose "Mood state determined (default): content"
    return "content"
}

function Get-MoodReason {
    <#
    .SYNOPSIS
        Generates a human-readable reason for the current mood.
    
    .DESCRIPTION
        Creates descriptive text explaining why the poodle is in its current mood state,
        based on contribution activity and interaction bonuses.
    
    .PARAMETER MoodState
        The current mood state name.
    
    .PARAMETER ContributionStats
        Hashtable containing contribution statistics.
    
    .PARAMETER InteractionBonus
        The current interaction bonus points.
    
    .OUTPUTS
        String describing the reason for the current mood.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MoodState,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ContributionStats,
        
        [Parameter()]
        [ValidateRange(0, 1000)]
        [int]$InteractionBonus = 0
    )
    
    Write-Verbose "Generating mood reason for state: $MoodState"
    
    $reasons = @()
    
    if ($ContributionStats.lastContributionDate) {
        $daysSince = ((Get-Date) - [datetime]$ContributionStats.lastContributionDate).Days
        if ($daysSince -eq 0) {
            $reasons += "Contributed today!"
        }
        elseif ($daysSince -eq 1) {
            $reasons += "Contributed yesterday"
        }
        elseif ($daysSince -le 3) {
            $reasons += "Active in the last few days"
        }
        elseif ($daysSince -le 7) {
            $reasons += "Missing you a bit..."
        }
        else {
            $reasons += "It's been $daysSince days..."
        }
    }
    else {
        $reasons += "Waiting for first contribution"
    }
    
    if ($InteractionBonus -gt 5) {
        $reasons += "Feeling loved from all the pets & treats!"
    }
    elseif ($InteractionBonus -gt 0) {
        $reasons += "Appreciates the attention"
    }
    
    $reasonText = $reasons -join " • "
    Write-Verbose "Mood reason: $reasonText"
    return $reasonText
}

function Update-ReadmePoodle {
    <#
    .SYNOPSIS
        Updates the README.md file with current poodle mood and statistics.
    
    .DESCRIPTION
        Generates a formatted poodle section with mood image, score, statistics,
        and interaction history, then replaces the existing section in README.md
        between the <!--START_SECTION:poodle--> and <!--END_SECTION:poodle--> markers.
    
    .PARAMETER MoodState
        The current mood state name.
    
    .PARAMETER MoodScore
        The numerical mood score (0-100).
    
    .PARAMETER MoodReason
        The human-readable reason for the current mood.
    
    .PARAMETER ContributionStats
        Hashtable containing contribution statistics.
    
    .PARAMETER Interactions
        Object containing interaction history (totalPets, totalFeeds, log).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MoodState,
        
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$MoodScore,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MoodReason,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ContributionStats,
        
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Interactions
    )
    
    Write-Verbose "Updating README.md with poodle mood: $MoodState ($MoodScore/100)"
    
    $moodInfo = $MoodConfig[$MoodState]
    $lastContrib = if ($ContributionStats.lastContributionDate) { $ContributionStats.lastContributionDate } else { "Never" }
    
    # Get recent interaction usernames (last 5 unique)
    $recentUsers = $Interactions.log | 
    Sort-Object timestamp -Descending | 
    Select-Object -ExpandProperty username -Unique | 
    Select-Object -First 5
    $recentUsersText = if ($recentUsers) { ($recentUsers | ForEach-Object { "@$_" }) -join ", " } else { "No one yet!" }
    
    $poodleSection = @"
<!--START_SECTION:poodle-->
<div align="center">

## 🐩 Mood Poodle 🐩

<img src="$($moodInfo.image)" alt="$MoodState poodle" width="200">

### $($moodInfo.emoji) **$($MoodState.ToUpper())** $($moodInfo.emoji)
**Mood Score:** $MoodScore/100

*$MoodReason*

---

📊 **Contribution Stats**
| Metric | Value |
|--------|-------|
| Last Contribution | $lastContrib |
| Contributions (7 days) | $($ContributionStats.count7Days) |
| Contributions (30 days) | $($ContributionStats.count30Days) |
| Repositories | $($ContributionStats.repoCount) |

🐾 **Interaction Stats**
| Type | Count |
|------|-------|
| Pets received | $($Interactions.totalPets) |
| Treats received | $($Interactions.totalFeeds) |

**Recent visitors:** $recentUsersText

---

### Want to make the poodle happier?

Comment on the [🐩 Poodle Interaction issue](../../issues?q=is%3Aissue+is%3Aopen+Poodle+in%3Atitle) with:
- ``!pet`` - Give the poodle some pets 🐾
- ``!feed`` - Give the poodle a treat 🍖

<sub>*The poodle's mood updates every 6 hours based on GitHub activity and visitor interactions!*</sub>

</div>
<!--END_SECTION:poodle-->
"@
    
    $readme = Get-Content $ReadmeFile -Raw
    $pattern = '(?s)<!--START_SECTION:poodle-->.*<!--END_SECTION:poodle-->'
    
    if ($readme -match $pattern) {
        $newReadme = $readme -replace $pattern, $poodleSection
    }
    else {
        # If markers don't exist, append after the first section
        $newReadme = $readme + "`n`n" + $poodleSection
    }
    
    try {
        Set-Content -Path $ReadmeFile -Value $newReadme -NoNewline -ErrorAction Stop
        Write-Verbose "README.md successfully updated with poodle mood: $MoodState ($MoodScore/100)"
    }
    catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ReadmeUpdateFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $ReadmeFile
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
}

# Main execution
Write-Verbose '🐩 Starting Poodle Mood Update Process...'
$ErrorActionPreference = 'Stop'

# Load state
try {
    if (-not (Test-Path -Path $StateFile)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new("State file not found: $StateFile"),
            'StateFileNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $StateFile
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    
    $state = Get-Content $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
    Write-Verbose "State loaded from $StateFile"

    # Check if cooldown is active - skip mood calculation to preserve ecstatic state
    if ($state.cooldown -and $state.cooldown.active) {
        Write-Verbose "Cooldown is active - skipping mood update to preserve ecstatic state"
        Write-Verbose "Cooldown will be resolved by the poodle-cooldown workflow"
        # Still apply decay to interaction bonus
        $currentBonus = [int]$state.decay.interactionBonus
        $newBonus = [Math]::Max(0, $currentBonus - $DecayPerCycle)
        $state.decay.interactionBonus = $newBonus
        $state.decay.lastDecayApplied = (Get-Date).ToUniversalTime().ToString("o")
        $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile -ErrorAction Stop
        Write-Verbose "Decay applied, but mood preserved. Exiting gracefully."
        exit 0
    }

    # Apply decay to interaction bonus
    $currentBonus = [int]$state.decay.interactionBonus
    $newBonus = [Math]::Max(0, $currentBonus - $DecayPerCycle)
    Write-Verbose "Interaction bonus: $currentBonus -> $newBonus (decay: -$DecayPerCycle)"
    
    # Fetch contribution data
    Write-Verbose "Fetching GitHub contributions for $GitHubUser..."
    $contributionData = Get-GitHubContributions -Token $GitHubToken -Username $GitHubUser
    $contributionStats = Get-ContributionStats -ContributionData $contributionData

    # Calculate mood
    $moodScore = Get-MoodScore -ContributionStats $contributionStats -InteractionBonus $newBonus
    $moodState = Get-MoodState -Score $moodScore
    $moodReason = Get-MoodReason -MoodState $moodState -ContributionStats $contributionStats -InteractionBonus $newBonus
    
    Write-Verbose "Mood calculated: $moodState (Score: $moodScore)"
    Write-Verbose "Reason: $moodReason"

    # Update state
    $state.mood.score = $moodScore
    $state.mood.state = $moodState
    $state.mood.lastCalculated = (Get-Date).ToUniversalTime().ToString("o")
    $state.decay.interactionBonus = $newBonus
    $state.decay.lastDecayApplied = (Get-Date).ToUniversalTime().ToString("o")
    $state.contributions.lastContributionDate = $contributionStats.lastContributionDate
    $state.contributions.count7Days = $contributionStats.count7Days
    $state.contributions.count30Days = $contributionStats.count30Days
    $state.contributions.repoCount = $contributionStats.repoCount
    $state.contributions.lastFetched = (Get-Date).ToUniversalTime().ToString("o")
    
    # Save state
    $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile -ErrorAction Stop
    Write-Verbose "State saved to $StateFile"

    # Update README
    Update-ReadmePoodle -MoodState $moodState -MoodScore $moodScore -MoodReason $moodReason -ContributionStats $contributionStats -Interactions $state.interactions
    
    Write-Verbose '✅ Poodle mood update complete!'
}
catch {
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $_.Exception,
        'PoodleMoodUpdateFailed',
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $null
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
