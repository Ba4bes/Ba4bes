<#
.SYNOPSIS
    Restores the poodle mood after the ecstatic cooldown period.

.DESCRIPTION
    This script is triggered after the 10-minute cooldown following pet/feed interactions.
    It restores the poodle mood from ecstatic (100) to the pre-interaction score plus
    any stacked bonuses from multiple interactions during the cooldown window.

.PARAMETER GitHubToken
    The GitHub token for API authentication. Defaults to GITHUB_TOKEN environment variable.

.PARAMETER GitHubUser
    The GitHub username. Defaults to GITHUB_REPOSITORY_OWNER environment variable.

.EXAMPLE
    ./Restore-PoodleMood.ps1

    Runs with all parameters from environment variables (typical GitHub Actions usage).

.NOTES
    This script is designed to be run by GitHub Actions after a 10-minute environment wait timer.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter()]
    [string]$GitHubUser = $env:GITHUB_REPOSITORY_OWNER
)

# Load shared configuration
. ./poodle-config.ps1

# No script-specific configuration needed for Restore-PoodleMood

function Get-MoodState {
    <#
    .SYNOPSIS
        Determines the mood state from a score.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Score
    )

    foreach ($mood in $MoodConfig.GetEnumerator()) {
        if ($Score -ge $mood.Value.min -and $Score -le $mood.Value.max) {
            return $mood.Key
        }
    }
    return "content"
}

function Update-ReadmePoodle {
    <#
    .SYNOPSIS
        Updates the README.md file with current poodle mood.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MoodState,

        [Parameter(Mandatory)]
        [int]$MoodScore,

        [Parameter(Mandatory)]
        [string]$MoodReason,

        [Parameter(Mandatory)]
        [hashtable]$ContributionStats,

        [Parameter(Mandatory)]
        [object]$Interactions
    )

    $poodleSection = Get-PoodleMarkdownSection -MoodState $MoodState -MoodScore $MoodScore -MoodReason $MoodReason -ContributionStats $ContributionStats -Interactions $Interactions
    Update-ReadmeWithPoodleSection -PoodleSection $poodleSection
    Write-Verbose "README.md updated with poodle mood: $MoodState ($MoodScore/100)"
}

# Main execution
Write-Verbose '🐩 Starting Poodle Mood Restoration after Cooldown...'
$ErrorActionPreference = 'Stop'

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

# Check if cooldown is active
if (-not $state.cooldown -or -not $state.cooldown.active) {
    Write-Verbose 'No active cooldown found, nothing to restore.'
    exit 0
}

Write-Verbose "Cooldown is active - restoring mood from ecstatic"
Write-Verbose "Pre-interaction score: $($state.cooldown.preInteractionScore)"
Write-Verbose "Stacked bonus: $($state.cooldown.stackedBonus)"

# Calculate new score: pre-interaction score + stacked bonus
$newScore = [int]$state.cooldown.preInteractionScore + [int]$state.cooldown.stackedBonus
$newScore = [Math]::Max(0, [Math]::Min(100, $newScore))  # Clamp to 0-100

Write-Verbose "New mood score: $newScore"

# Determine new mood state
$newMoodState = Get-MoodState -Score $newScore

# Generate mood reason
$moodReason = "Settling down after some love!"
if ($state.cooldown.stackedBonus -gt 5) {
    $moodReason = "Feeling extra loved from all the attention! (+$($state.cooldown.stackedBonus) bonus)"
}
elseif ($state.cooldown.stackedBonus -gt 0) {
    $moodReason = "Feeling appreciated after those pets & treats!"
}

# Update state
$state.mood.score = $newScore
$state.mood.state = $newMoodState
$state.mood.lastCalculated = (Get-Date).ToUniversalTime().ToString('o')

# Clear cooldown
$state.cooldown.active = $false
$state.cooldown.preInteractionScore = $null
$state.cooldown.stackedBonus = 0
$state.cooldown.triggeredAt = $null

# Save state
$state | ConvertTo-Json -Depth 10 | Set-Content -Path $script:StateFile
Write-Verbose "State saved to $script:StateFile"

# Prepare contribution stats for README update
$contributionStats = @{
    lastContributionDate = $state.contributions.lastContributionDate
    count7Days           = $state.contributions.count7Days
    count30Days          = $state.contributions.count30Days
    repoCount            = $state.contributions.repoCount
}

# Update README
Update-ReadmePoodle -MoodState $newMoodState -MoodScore $newScore -MoodReason $moodReason -ContributionStats $contributionStats -Interactions $state.interactions

Write-Verbose "✅ Poodle mood restored to $newMoodState ($newScore/100) after cooldown!"
