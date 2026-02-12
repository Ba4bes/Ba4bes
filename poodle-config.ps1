<#
.SYNOPSIS
    Centralized configuration for Mood Poodle scripts.

.DESCRIPTION
    Contains shared configuration, mood definitions, constants, and functions used across
    all Mood Poodle scripts (Handle-PoodleInteraction.ps1, Update-PoodleMood.ps1, Restore-PoodleMood.ps1).
    
    This file should be sourced at the beginning of each script:
    . ./poodle-config.ps1

.NOTES
    Do not modify this file directly unless you understand the impact on all dependent scripts.
#>

# File paths
$script:StateFile = './poodle-state.json'
$script:ReadmeFile = './README.md'

# Mood configuration - shared across all scripts
$script:MoodConfig = @{
    sad      = @{ min = 0; max = 20; image = "Assets/poodle-sad.png"; emoji = "😢" }
    bored    = @{ min = 21; max = 40; image = "Assets/poodle-bored.png"; emoji = "😐" }
    content  = @{ min = 41; max = 60; image = "Assets/poodle-content.png"; emoji = "🙂" }
    happy    = @{ min = 61; max = 80; image = "Assets/poodle-happy.png"; emoji = "😊" }
    ecstatic = @{ min = 81; max = 100; image = "Assets/poodle-ecstatic.png"; emoji = "🎉" }
}

function Get-PoodleMarkdownSection {
    <#
    .SYNOPSIS
        Generates the poodle section markdown for README.md.

    .DESCRIPTION
        Creates the formatted poodle status section with mood image, score, statistics,
        and interaction history. Returns the complete poodle section wrapped in comments.

    .PARAMETER MoodState
        The current mood state name (e.g., 'happy', 'ecstatic').

    .PARAMETER MoodScore
        The numerical mood score (0-100).

    .PARAMETER MoodReason
        The human-readable reason for the current mood.

    .PARAMETER ContributionStats
        Hashtable containing: lastContributionDate, count7Days, count30Days, repoCount.

    .PARAMETER Interactions
        Object containing: totalPets, totalFeeds, log (array of interaction entries).

    .OUTPUTS
        String containing the complete poodle markdown section.
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

    $moodInfo = $script:MoodConfig[$MoodState]
    $lastContrib = if ($ContributionStats.lastContributionDate) { $ContributionStats.lastContributionDate } else { "Never" }

    # Get recent interaction usernames (last 5 unique)
    $recentUsers = $Interactions.log | 
        Sort-Object timestamp -Descending | 
        Select-Object -ExpandProperty username -Unique | 
        Select-Object -First 5
    $recentUsersText = if ($recentUsers) { ($recentUsers | ForEach-Object { "[@$_](https://github.com/$_)" }) -join ", " } else { "No one yet!" }

    $poodleSection = @"
<!--START_SECTION:poodle-->
<div align="center">

## 🐩 Mood Poodle 🐩

This is my mood poodle! Its mood changes based on my GitHub activity and your interactions.
The more I contribute and the more you pet or feed it, the happier it gets!

<a href="https://github.com/Ba4bes/Ba4bes/issues/2"><img src="$($moodInfo.image)" alt="$MoodState poodle" width="400"></a>

### $($moodInfo.emoji) **$($MoodState.ToUpper())** $($moodInfo.emoji)
**Mood Score:** $MoodScore/100

*$MoodReason*

---

📊 **Interaction Stats**
| Type | Count |
|------|-------|
| Pets received | $($Interactions.totalPets) |
| Treats received | $($Interactions.totalFeeds) |

**Recent visitors:** $recentUsersText

---

### Want to make the poodle happier?

Comment on the [🐩 Poodle Interaction issue](https://github.com/Ba4bes/Ba4bes/issues/2) with:
- ``!pet`` - Give the poodle some pets 🐾
- ``!feed`` - Give the poodle a treat 🍖

---

📊 **Contribution Stats**
| Metric | Value |
|--------|-------|
| Last Contribution | $lastContrib |
| Contributions (7 days) | $($ContributionStats.count7Days) |
| Contributions (30 days) | $($ContributionStats.count30Days) |
| Repositories | $($ContributionStats.repoCount) |

<sub>*The poodle's mood updates based on GitHub activity and visitor interactions!*</sub>

</div>
<!--END_SECTION:poodle-->
"@

    return $poodleSection
}

function Update-ReadmeWithPoodleSection {
    <#
    .SYNOPSIS
        Updates the README.md file with a poodle section.

    .DESCRIPTION
        Replaces the poodle section in README.md between the marker comments,
        or appends it if the markers don't exist.

    .PARAMETER PoodleSection
        The poodle markdown section to insert into README.

    .PARAMETER ReadmeFile
        Optional path to the README file. Defaults to $script:ReadmeFile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PoodleSection,

        [Parameter()]
        [string]$ReadmeFile = $script:ReadmeFile
    )

    $readme = Get-Content $ReadmeFile -Raw
    $pattern = '(?s)<!--START_SECTION:poodle-->.*<!--END_SECTION:poodle-->'

    if ($readme -match $pattern) {
        $newReadme = $readme -replace $pattern, $PoodleSection
    }
    else {
        $newReadme = $readme + "`n`n" + $PoodleSection
    }

    Set-Content -Path $ReadmeFile -Value $newReadme -NoNewline
    Write-Verbose "README.md updated with poodle section"
}

Write-Verbose "Poodle configuration loaded"
