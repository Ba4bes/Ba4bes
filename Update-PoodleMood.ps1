# Update-PoodleMood.ps1
# Fetches GitHub contribution data and calculates poodle mood
# Updates README.md with current mood and stats

param(
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$GitHubUser = $env:GITHUB_REPOSITORY_OWNER
)

# Configuration
$StateFile = "./poodle-state.json"
$ReadmeFile = "./README.md"
$DecayPerCycle = 1  # Interaction bonus decay per 6-hour cycle

# Mood thresholds and images
$MoodConfig = @{
    sad      = @{ min = 0;  max = 20;  image = "Assets/poodle-sad.svg";      emoji = "😢" }
    bored    = @{ min = 21; max = 40;  image = "Assets/poodle-bored.svg";    emoji = "😐" }
    content  = @{ min = 41; max = 60;  image = "Assets/poodle-content.svg";  emoji = "🙂" }
    happy    = @{ min = 61; max = 80;  image = "Assets/poodle-happy.svg";    emoji = "😊" }
    ecstatic = @{ min = 81; max = 100; image = "Assets/poodle-ecstatic.svg"; emoji = "🎉" }
}

function Get-GitHubContributions {
    param([string]$Token, [string]$Username)
    
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
        $response = Invoke-RestMethod -Uri "https://api.github.com/graphql" -Method Post -Headers $headers -Body $body
        return $response.data.user
    }
    catch {
        Write-Warning "Failed to fetch GitHub contributions: $_"
        return $null
    }
}

function Get-ContributionStats {
    param($ContributionData)
    
    if (-not $ContributionData) {
        return @{
            lastContributionDate = $null
            count7Days           = 0
            count30Days          = 0
            repoCount            = 0
        }
    }
    
    $today = Get-Date
    $allDays = $ContributionData.contributionsCollection.contributionCalendar.weeks | 
        ForEach-Object { $_.contributionDays } | 
        Where-Object { $_.contributionCount -gt 0 }
    
    $lastContribution = $allDays | Sort-Object date -Descending | Select-Object -First 1
    
    $last7Days = $allDays | Where-Object { 
        ([datetime]$_.date) -ge $today.AddDays(-7) 
    } | Measure-Object -Property contributionCount -Sum
    
    $last30Days = $allDays | Where-Object { 
        ([datetime]$_.date) -ge $today.AddDays(-30) 
    } | Measure-Object -Property contributionCount -Sum
    
    return @{
        lastContributionDate = $lastContribution.date
        count7Days           = [int]$last7Days.Sum
        count30Days          = [int]$last30Days.Sum
        repoCount            = $ContributionData.repositories.totalCount
    }
}

function Get-MoodScore {
    param(
        $ContributionStats,
        [int]$InteractionBonus
    )
    
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
    return [Math]::Max(0, [Math]::Min(100, [int]$score))
}

function Get-MoodState {
    param([int]$Score)
    
    foreach ($mood in $MoodConfig.GetEnumerator()) {
        if ($Score -ge $mood.Value.min -and $Score -le $mood.Value.max) {
            return $mood.Key
        }
    }
    return "content"
}

function Get-MoodReason {
    param(
        [string]$MoodState,
        $ContributionStats,
        [int]$InteractionBonus
    )
    
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
    
    return $reasons -join " • "
}

function Update-ReadmePoodle {
    param(
        [string]$MoodState,
        [int]$MoodScore,
        [string]$MoodReason,
        $ContributionStats,
        $Interactions
    )
    
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
    
    Set-Content -Path $ReadmeFile -Value $newReadme -NoNewline
    Write-Host "README.md updated with poodle mood: $MoodState ($MoodScore/100)"
}

# Main execution
Write-Host "🐩 Updating Poodle Mood..."

# Load state
$state = Get-Content $StateFile -Raw | ConvertFrom-Json

# Apply decay to interaction bonus
$currentBonus = [int]$state.decay.interactionBonus
$newBonus = [Math]::Max(0, $currentBonus - $DecayPerCycle)
Write-Host "Interaction bonus: $currentBonus -> $newBonus (decay: -$DecayPerCycle)"

# Fetch contribution data
Write-Host "Fetching GitHub contributions for $GitHubUser..."
$contributionData = Get-GitHubContributions -Token $GitHubToken -Username $GitHubUser
$contributionStats = Get-ContributionStats -ContributionData $contributionData

# Calculate mood
$moodScore = Get-MoodScore -ContributionStats $contributionStats -InteractionBonus $newBonus
$moodState = Get-MoodState -Score $moodScore
$moodReason = Get-MoodReason -MoodState $moodState -ContributionStats $contributionStats -InteractionBonus $newBonus

Write-Host "Mood calculated: $moodState (Score: $moodScore)"
Write-Host "Reason: $moodReason"

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
$state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
Write-Host "State saved to $StateFile"

# Update README
Update-ReadmePoodle -MoodState $moodState -MoodScore $moodScore -MoodReason $moodReason -ContributionStats $contributionStats -Interactions $state.interactions

Write-Host "✅ Poodle mood update complete!"
