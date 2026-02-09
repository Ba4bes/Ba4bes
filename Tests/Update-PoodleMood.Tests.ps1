<#
.SYNOPSIS
    Pester tests for Update-PoodleMood.ps1

.DESCRIPTION
    Comprehensive unit, integration, snapshot, and contract tests for the poodle mood updater.
    Covers mood computation, decay, threshold mapping, reason text, README marker replacement,
    and GraphQL response handling.

.NOTES
    Uses Pester 5+ syntax. Functions are extracted from the script AST to enable isolated unit testing.
    All README tests use real temp files with Set-Location to match the function's relative path behavior.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Update-PoodleMood.ps1'
    $script:FixturePath = Join-Path $PSScriptRoot 'Fixtures'

    # Pre-load fixture data
    $script:EmptyStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-empty.json') -Raw
    $script:SeededStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-seeded.json') -Raw
    $script:GraphqlResponseJson = Get-Content (Join-Path $script:FixturePath 'graphql-response.json') -Raw
    $script:ReadmeWithPoodle = Get-Content (Join-Path $script:FixturePath 'readme-with-poodle.md') -Raw
    $script:ReadmeWithoutPoodle = Get-Content (Join-Path $script:FixturePath 'readme-without-poodle.md') -Raw

    # Extract function definitions from the script AST for isolated unit testing
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ScriptPath,
        [ref]$null,
        [ref]$null
    )

    $functionDefinitions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $false)

    $functionsScript = @'
$MoodConfig = @{
    sad      = @{ min = 0;  max = 20;  image = 'Assets/poodle-sad.png';      emoji = '😢' }
    bored    = @{ min = 21; max = 40;  image = 'Assets/poodle-bored.png';    emoji = '😐' }
    content  = @{ min = 41; max = 60;  image = 'Assets/poodle-content.png';  emoji = '🙂' }
    happy    = @{ min = 61; max = 80;  image = 'Assets/poodle-happy.png';    emoji = '😊' }
    ecstatic = @{ min = 81; max = 100; image = 'Assets/poodle-ecstatic.png'; emoji = '🎉' }
}

'@
    foreach ($func in $functionDefinitions) {
        $functionsScript += $func.Extent.Text + "`n`n"
    }

    Invoke-Expression $functionsScript

    function New-TempWorkspace {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PoodleMoodTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        return $tempDir
    }
}

Describe 'Update-PoodleMood.ps1 - Unit Tests' {

    Describe 'Get-ContributionStats' {

        It 'Should return zero stats when contribution data is null' {
            $result = Get-ContributionStats -ContributionData $null
            $result.lastContributionDate | Should -BeNullOrEmpty
            $result.count7Days | Should -Be 0
            $result.count30Days | Should -Be 0
            $result.repoCount | Should -Be 0
        }

        It 'Should calculate 7-day and 30-day contribution counts' {
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            $graphqlData = $script:GraphqlResponseJson | ConvertFrom-Json
            $contributionData = $graphqlData.data.user

            $result = Get-ContributionStats -ContributionData $contributionData

            $result.count7Days | Should -BeGreaterThan 0
            $result.count30Days | Should -BeGreaterOrEqual $result.count7Days
            $result.repoCount | Should -Be 25
        }

        It 'Should identify the most recent contribution date' {
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            $graphqlData = $script:GraphqlResponseJson | ConvertFrom-Json
            $contributionData = $graphqlData.data.user

            $result = Get-ContributionStats -ContributionData $contributionData

            $result.lastContributionDate | Should -Be '2026-02-08'
        }
    }

    Describe 'Get-MoodScore' {

        BeforeEach {
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }
        }

        It 'Should return base score of 50 minus 30 when no contributions exist' {
            $stats = @{
                lastContributionDate = $null
                count7Days           = 0
                count30Days          = 0
                repoCount            = 0
            }
            $result = Get-MoodScore -ContributionStats $stats -InteractionBonus 0
            $result | Should -Be 20
        }

        It 'Should clamp score to minimum of 0' {
            $stats = @{
                lastContributionDate = '2026-01-01'
                count7Days           = 0
                count30Days          = 0
                repoCount            = 0
            }
            $result = Get-MoodScore -ContributionStats $stats -InteractionBonus 0
            $result | Should -BeGreaterOrEqual 0
        }

        It 'Should clamp score to maximum of 100' {
            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 100
                count30Days          = 500
                repoCount            = 200
            }
            $result = Get-MoodScore -ContributionStats $stats -InteractionBonus 50
            $result | Should -BeLessOrEqual 100
        }

        It 'Should add interaction bonus to score' {
            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 5
                count30Days          = 20
                repoCount            = 10
            }
            $withoutBonus = Get-MoodScore -ContributionStats $stats -InteractionBonus 0
            $withBonus = Get-MoodScore -ContributionStats $stats -InteractionBonus 10
            $withBonus | Should -BeGreaterThan $withoutBonus
        }

        It 'Should penalize days since last contribution' {
            $statsRecent = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 5
                count30Days          = 20
                repoCount            = 10
            }
            $statsOld = @{
                lastContributionDate = '2026-01-25'
                count7Days           = 5
                count30Days          = 20
                repoCount            = 10
            }
            $recentScore = Get-MoodScore -ContributionStats $statsRecent -InteractionBonus 0
            $oldScore = Get-MoodScore -ContributionStats $statsOld -InteractionBonus 0
            $recentScore | Should -BeGreaterThan $oldScore
        }

        It 'Should cap days-since-contribution penalty at 40' {
            $stats30Days = @{
                lastContributionDate = '2026-01-09'
                count7Days           = 0
                count30Days          = 0
                repoCount            = 0
            }
            $stats60Days = @{
                lastContributionDate = '2025-12-10'
                count7Days           = 0
                count30Days          = 0
                repoCount            = 0
            }
            $score30 = Get-MoodScore -ContributionStats $stats30Days -InteractionBonus 0
            $score60 = Get-MoodScore -ContributionStats $stats60Days -InteractionBonus 0
            # Both should hit the max penalty cap, so scores should be equal
            $score30 | Should -Be $score60
        }
    }

    Describe 'Get-MoodState' {

        It 'Should return "sad" for score 0-20' {
            Get-MoodState -Score 0  | Should -Be 'sad'
            Get-MoodState -Score 10 | Should -Be 'sad'
            Get-MoodState -Score 20 | Should -Be 'sad'
        }

        It 'Should return "bored" for score 21-40' {
            Get-MoodState -Score 21 | Should -Be 'bored'
            Get-MoodState -Score 30 | Should -Be 'bored'
            Get-MoodState -Score 40 | Should -Be 'bored'
        }

        It 'Should return "content" for score 41-60' {
            Get-MoodState -Score 41 | Should -Be 'content'
            Get-MoodState -Score 50 | Should -Be 'content'
            Get-MoodState -Score 60 | Should -Be 'content'
        }

        It 'Should return "happy" for score 61-80' {
            Get-MoodState -Score 61 | Should -Be 'happy'
            Get-MoodState -Score 70 | Should -Be 'happy'
            Get-MoodState -Score 80 | Should -Be 'happy'
        }

        It 'Should return "ecstatic" for score 81-100' {
            Get-MoodState -Score 81  | Should -Be 'ecstatic'
            Get-MoodState -Score 90  | Should -Be 'ecstatic'
            Get-MoodState -Score 100 | Should -Be 'ecstatic'
        }
    }

    Describe 'Get-MoodReason' {

        BeforeEach {
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }
        }

        It 'Should say "Contributed today!" when last contribution is today' {
            $stats = @{ lastContributionDate = '2026-02-08' }
            $result = Get-MoodReason -MoodState 'happy' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match 'Contributed today!'
        }

        It 'Should say "Contributed yesterday" when 1 day ago' {
            $stats = @{ lastContributionDate = '2026-02-07' }
            $result = Get-MoodReason -MoodState 'content' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match 'Contributed yesterday'
        }

        It 'Should say "Active in the last few days" for 2-3 days' {
            $stats = @{ lastContributionDate = '2026-02-06' }
            $result = Get-MoodReason -MoodState 'content' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match 'Active in the last few days'
        }

        It 'Should say "Missing you a bit..." for 4-7 days' {
            $stats = @{ lastContributionDate = '2026-02-02' }
            $result = Get-MoodReason -MoodState 'bored' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match 'Missing you a bit\.\.\.'
        }

        It 'Should include day count for >7 days' {
            $stats = @{ lastContributionDate = '2026-01-20' }
            $result = Get-MoodReason -MoodState 'sad' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match "It's been \d+ days\.\.\."
        }

        It 'Should say "Waiting for first contribution" when no contributions' {
            $stats = @{ lastContributionDate = $null }
            $result = Get-MoodReason -MoodState 'sad' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Match 'Waiting for first contribution'
        }

        It 'Should mention feeling loved when interaction bonus > 5' {
            $stats = @{ lastContributionDate = '2026-02-08' }
            $result = Get-MoodReason -MoodState 'happy' -ContributionStats $stats -InteractionBonus 10
            $result | Should -Match 'Feeling loved from all the pets & treats!'
        }

        It 'Should mention appreciation when interaction bonus is 1-5' {
            $stats = @{ lastContributionDate = '2026-02-08' }
            $result = Get-MoodReason -MoodState 'happy' -ContributionStats $stats -InteractionBonus 3
            $result | Should -Match 'Appreciates the attention'
        }

        It 'Should not mention interactions when bonus is 0' {
            $stats = @{ lastContributionDate = '2026-02-08' }
            $result = Get-MoodReason -MoodState 'happy' -ContributionStats $stats -InteractionBonus 0
            $result | Should -Not -Match 'Feeling loved'
            $result | Should -Not -Match 'Appreciates'
        }
    }

    Describe 'Decay Behavior' {

        It 'Should decay interaction bonus by 1 per cycle' {
            $tempDir = New-TempWorkspace
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'

            $state = $script:SeededStateJson | ConvertFrom-Json
            $state.decay.interactionBonus = 5
            $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
            Mock Invoke-RestMethod { return $graphqlResponse }
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $updatedState = Get-Content $stateFile -Raw | ConvertFrom-Json
            $updatedState.decay.interactionBonus | Should -Be 4

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should not decay below 0' {
            $tempDir = New-TempWorkspace
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'

            $state = $script:EmptyStateJson | ConvertFrom-Json
            $state.decay.interactionBonus = 0
            $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
            Mock Invoke-RestMethod { return $graphqlResponse }
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $updatedState = Get-Content $stateFile -Raw | ConvertFrom-Json
            $updatedState.decay.interactionBonus | Should -Be 0

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }
    }

    Describe 'Update-ReadmePoodle' {

        It 'Should replace existing poodle section markers' {
            $tempDir = New-TempWorkspace
            $testReadmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $testReadmeFile -Value $script:ReadmeWithPoodle

            # Set $ReadmeFile for the extracted function
            $ReadmeFile = $testReadmeFile

            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 10
                count30Days          = 40
                repoCount            = 25
            }
            $interactions = [PSCustomObject]@{
                totalPets  = 5
                totalFeeds = 3
                log        = @(
                    [PSCustomObject]@{ username = 'user1'; timestamp = '2026-02-08T10:00:00Z' }
                )
            }

            Update-ReadmePoodle -MoodState 'happy' -MoodScore 70 -MoodReason 'Contributed today!' `
                -ContributionStats $stats -Interactions $interactions

            $content = Get-Content $testReadmeFile -Raw
            $content | Should -Match '<!--START_SECTION:poodle-->'
            $content | Should -Match '<!--END_SECTION:poodle-->'
            $content | Should -Match 'HAPPY'
            $content | Should -Match '70/100'

            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should append poodle section when markers are missing' {
            $tempDir = New-TempWorkspace
            $testReadmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $testReadmeFile -Value $script:ReadmeWithoutPoodle

            $ReadmeFile = $testReadmeFile

            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 5
                count30Days          = 15
                repoCount            = 10
            }
            $interactions = [PSCustomObject]@{
                totalPets  = 0
                totalFeeds = 0
                log        = @()
            }

            Update-ReadmePoodle -MoodState 'content' -MoodScore 50 -MoodReason 'Test reason' `
                -ContributionStats $stats -Interactions $interactions

            $content = Get-Content $testReadmeFile -Raw
            $content | Should -Match '<!--START_SECTION:poodle-->'
            $content | Should -Match 'CONTENT'

            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should preserve content outside poodle markers' {
            $tempDir = New-TempWorkspace
            $testReadmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $testReadmeFile -Value $script:ReadmeWithPoodle

            $ReadmeFile = $testReadmeFile

            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 5
                count30Days          = 15
                repoCount            = 10
            }
            $interactions = [PSCustomObject]@{
                totalPets  = 0
                totalFeeds = 0
                log        = @()
            }

            Update-ReadmePoodle -MoodState 'ecstatic' -MoodScore 95 -MoodReason 'So happy!' `
                -ContributionStats $stats -Interactions $interactions

            $content = Get-Content $testReadmeFile -Raw
            $content | Should -Match 'Hi there'
            $content | Should -Match 'Random Blog post'
            $content | Should -Match 'ECSTATIC'

            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should display recent visitors from log' {
            $tempDir = New-TempWorkspace
            $testReadmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $testReadmeFile -Value $script:ReadmeWithPoodle

            $ReadmeFile = $testReadmeFile

            $stats = @{
                lastContributionDate = '2026-02-08'
                count7Days           = 5
                count30Days          = 15
                repoCount            = 10
            }
            $interactions = [PSCustomObject]@{
                totalPets  = 3
                totalFeeds = 2
                log        = @(
                    [PSCustomObject]@{ username = 'alice'; timestamp = '2026-02-08T10:00:00Z' }
                    [PSCustomObject]@{ username = 'bob'; timestamp = '2026-02-08T11:00:00Z' }
                )
            }

            Update-ReadmePoodle -MoodState 'happy' -MoodScore 70 -MoodReason 'Great day!' `
                -ContributionStats $stats -Interactions $interactions

            $content = Get-Content $testReadmeFile -Raw
            $content | Should -Match '@bob'
            $content | Should -Match '@alice'

            Remove-Item $tempDir -Recurse -Force
        }
    }
}

Describe 'Update-PoodleMood.ps1 - Integration Tests' {

    It 'Should update both state file and README with mocked GraphQL' {
        $tempDir = New-TempWorkspace
        $stateFile = Join-Path $tempDir 'poodle-state.json'
        $readmeFile = Join-Path $tempDir 'README.md'

        Set-Content -Path $stateFile -Value $script:SeededStateJson
        Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

        $originalLocation = Get-Location
        Set-Location $tempDir

        $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
        Mock Invoke-RestMethod { return $graphqlResponse }
        Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

        & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

        # Verify state file was updated
        $updatedState = Get-Content $stateFile -Raw | ConvertFrom-Json
        $updatedState.mood.score | Should -BeGreaterOrEqual 0
        $updatedState.mood.score | Should -BeLessOrEqual 100
        $updatedState.mood.state | Should -BeIn @('sad', 'bored', 'content', 'happy', 'ecstatic')
        $updatedState.contributions.repoCount | Should -Be 25

        # Verify README was updated
        $readmeContent = Get-Content $readmeFile -Raw
        $readmeContent | Should -Match '<!--START_SECTION:poodle-->'
        $readmeContent | Should -Match $updatedState.mood.state.ToUpper()

        Set-Location $originalLocation
        Remove-Item $tempDir -Recurse -Force
    }

    It 'Should handle null GraphQL response gracefully' {
        $tempDir = New-TempWorkspace
        $stateFile = Join-Path $tempDir 'poodle-state.json'
        $readmeFile = Join-Path $tempDir 'README.md'

        Set-Content -Path $stateFile -Value $script:EmptyStateJson
        Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

        $originalLocation = Get-Location
        Set-Location $tempDir

        Mock Invoke-RestMethod { return $null }
        Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

        { & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser' } |
            Should -Not -Throw

        $updatedState = Get-Content $stateFile -Raw | ConvertFrom-Json
        $updatedState.mood.score | Should -BeGreaterOrEqual 0

        Set-Location $originalLocation
        Remove-Item $tempDir -Recurse -Force
    }
}

Describe 'Update-PoodleMood.ps1 - Snapshot Tests' {

    It 'Should produce deterministic poodle section for known inputs' {
        $tempDir = New-TempWorkspace
        $testReadmeFile = Join-Path $tempDir 'README.md'
        Set-Content -Path $testReadmeFile -Value $script:ReadmeWithPoodle

        # Set $ReadmeFile for the extracted function
        $ReadmeFile = $testReadmeFile

        $stats = @{
            lastContributionDate = '2026-02-08'
            count7Days           = 10
            count30Days          = 40
            repoCount            = 25
        }
        $interactions = [PSCustomObject]@{
            totalPets  = 5
            totalFeeds = 3
            log        = @(
                [PSCustomObject]@{ username = 'alice'; timestamp = '2026-02-08T10:00:00Z' }
                [PSCustomObject]@{ username = 'bob'; timestamp = '2026-02-08T11:00:00Z' }
            )
        }

        Update-ReadmePoodle -MoodState 'happy' -MoodScore 70 -MoodReason 'Contributed today!' `
            -ContributionStats $stats -Interactions $interactions

        $content = Get-Content $testReadmeFile -Raw

        # Extract the poodle section
        if ($content -match '(?s)(<!--START_SECTION:poodle-->.*<!--END_SECTION:poodle-->)') {
            $poodleSection = $Matches[1]
        }

        # Verify stable content elements
        $poodleSection | Should -Match 'Assets/poodle-happy\.png'
        $poodleSection | Should -Match 'HAPPY'
        $poodleSection | Should -Match '70/100'
        $poodleSection | Should -Match 'Contributed today!'
        $poodleSection | Should -Match 'Pets received \| 5'
        $poodleSection | Should -Match 'Treats received \| 3'
        $poodleSection | Should -Match '@bob'
        $poodleSection | Should -Match '@alice'
        $poodleSection | Should -Match 'Contributions \(7 days\) \| 10'
        $poodleSection | Should -Match 'Contributions \(30 days\) \| 40'

        Remove-Item $tempDir -Recurse -Force
    }
}

Describe 'Update-PoodleMood.ps1 - Contract Tests' {

    Describe 'GraphQL Response Contract' {

        It 'Should use the expected GraphQL response fields' {
            $graphqlData = $script:GraphqlResponseJson | ConvertFrom-Json
            $userData = $graphqlData.data.user

            # Verify the fields the script relies on exist
            $userData.contributionsCollection | Should -Not -BeNullOrEmpty
            $userData.contributionsCollection.contributionCalendar | Should -Not -BeNullOrEmpty
            $userData.contributionsCollection.contributionCalendar.weeks | Should -Not -BeNullOrEmpty

            $firstDay = $userData.contributionsCollection.contributionCalendar.weeks[0].contributionDays[0]
            $firstDay.PSObject.Properties.Name | Should -Contain 'contributionCount'
            $firstDay.PSObject.Properties.Name | Should -Contain 'date'

            $userData.repositories | Should -Not -BeNullOrEmpty
            $userData.repositories.totalCount | Should -BeOfType [System.Int64]
        }
    }

    Describe 'State File Contract' {

        It 'Should produce state with all required top-level sections' {
            $tempDir = New-TempWorkspace
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'

            Set-Content -Path $stateFile -Value $script:EmptyStateJson
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
            Mock Invoke-RestMethod { return $graphqlResponse }
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json

            # Required top-level sections
            $result.PSObject.Properties.Name | Should -Contain 'mood'
            $result.PSObject.Properties.Name | Should -Contain 'decay'
            $result.PSObject.Properties.Name | Should -Contain 'interactions'
            $result.PSObject.Properties.Name | Should -Contain 'contributions'

            # Required mood fields
            $result.mood.PSObject.Properties.Name | Should -Contain 'score'
            $result.mood.PSObject.Properties.Name | Should -Contain 'state'
            $result.mood.PSObject.Properties.Name | Should -Contain 'lastCalculated'

            # Required decay fields
            $result.decay.PSObject.Properties.Name | Should -Contain 'interactionBonus'
            $result.decay.PSObject.Properties.Name | Should -Contain 'lastDecayApplied'

            # Required contribution fields
            $result.contributions.PSObject.Properties.Name | Should -Contain 'lastContributionDate'
            $result.contributions.PSObject.Properties.Name | Should -Contain 'count7Days'
            $result.contributions.PSObject.Properties.Name | Should -Contain 'count30Days'
            $result.contributions.PSObject.Properties.Name | Should -Contain 'repoCount'
            $result.contributions.PSObject.Properties.Name | Should -Contain 'lastFetched'

            # Timestamps should be parseable
            { [datetime]::Parse($result.mood.lastCalculated) } | Should -Not -Throw
            { [datetime]::Parse($result.decay.lastDecayApplied) } | Should -Not -Throw
            { [datetime]::Parse($result.contributions.lastFetched) } | Should -Not -Throw

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should have mood score clamped between 0 and 100' {
            $tempDir = New-TempWorkspace
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'

            Set-Content -Path $stateFile -Value $script:EmptyStateJson
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
            Mock Invoke-RestMethod { return $graphqlResponse }
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.mood.score | Should -BeGreaterOrEqual 0
            $result.mood.score | Should -BeLessOrEqual 100

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should have mood state matching a valid mood name' {
            $tempDir = New-TempWorkspace
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'

            Set-Content -Path $stateFile -Value $script:EmptyStateJson
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $graphqlResponse = $script:GraphqlResponseJson | ConvertFrom-Json
            Mock Invoke-RestMethod { return $graphqlResponse }
            Mock Get-Date { return [datetime]'2026-02-08T12:00:00Z' }

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.mood.state | Should -BeIn @('sad', 'bored', 'content', 'happy', 'ecstatic')

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }
    }
}
