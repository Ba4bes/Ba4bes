<#
.SYNOPSIS
    Pester tests for Restore-PoodleMood.ps1

.DESCRIPTION
    Tests for the cooldown restoration script that returns the poodle from ecstatic
    to its pre-interaction score plus stacked bonuses.

.NOTES
    Uses Pester 5+ syntax.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Restore-PoodleMood.ps1'
    $script:FixturePath = Join-Path $PSScriptRoot 'Fixtures'

    # Pre-load fixture data
    $script:EmptyStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-empty.json') -Raw
    $script:CooldownActiveStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-cooldown-active.json') -Raw
    $script:ReadmeWithPoodle = Get-Content (Join-Path $script:FixturePath 'readme-with-poodle.md') -Raw

    function New-TempWorkspace {
        param([string]$StateJson)
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PoodleRestoreTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        if ($StateJson) {
            Set-Content -Path (Join-Path $tempDir 'poodle-state.json') -Value $StateJson
        }
        return $tempDir
    }
}

Describe 'Restore-PoodleMood.ps1 - Unit Tests' {

    Describe 'Cooldown Restoration' {

        It 'Should restore mood to preInteractionScore plus stackedBonus' {
            $tempDir = New-TempWorkspace -StateJson $script:CooldownActiveStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            # preInteractionScore (65) + stackedBonus (5) = 70
            $result.mood.score | Should -Be 70
            $result.mood.state | Should -Be 'happy'

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should clear cooldown state after restoration' {
            $tempDir = New-TempWorkspace -StateJson $script:CooldownActiveStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.cooldown.active | Should -Be $false
            $result.cooldown.preInteractionScore | Should -BeNullOrEmpty
            $result.cooldown.stackedBonus | Should -Be 0
            $result.cooldown.triggeredAt | Should -BeNullOrEmpty

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should exit gracefully when no active cooldown' {
            $tempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            { & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser' } | Should -Not -Throw

            # State should remain unchanged
            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.mood.score | Should -Be 50

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should clamp restored score to maximum of 100' {
            $state = $script:CooldownActiveStateJson | ConvertFrom-Json
            $state.cooldown.preInteractionScore = 95
            $state.cooldown.stackedBonus = 20
            $highBonusStateJson = $state | ConvertTo-Json -Depth 10

            $tempDir = New-TempWorkspace -StateJson $highBonusStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.mood.score | Should -Be 100
            $result.mood.state | Should -Be 'ecstatic'

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }

        It 'Should update lastCalculated timestamp' {
            $tempDir = New-TempWorkspace -StateJson $script:CooldownActiveStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            $stateBefore = $script:CooldownActiveStateJson | ConvertFrom-Json
            $lastCalcBefore = $stateBefore.mood.lastCalculated

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $result = Get-Content $stateFile -Raw | ConvertFrom-Json
            $result.mood.lastCalculated | Should -Not -Be $lastCalcBefore

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }
    }

    Describe 'Mood State Mapping' {

        It 'Should set correct mood state for each score range' {
            $testCases = @(
                @{ preScore = 15; bonus = 10; expectedState = 'bored' }   # 25 -> bored (21-40)
                @{ preScore = 35; bonus = 10; expectedState = 'content' } # 45 -> content
                @{ preScore = 55; bonus = 10; expectedState = 'happy' }   # 65 -> happy
                @{ preScore = 80; bonus = 5; expectedState = 'ecstatic' } # 85 -> ecstatic
            )

            foreach ($case in $testCases) {
                $state = $script:CooldownActiveStateJson | ConvertFrom-Json
                $state.cooldown.preInteractionScore = $case.preScore
                $state.cooldown.stackedBonus = $case.bonus
                $testStateJson = $state | ConvertTo-Json -Depth 10

                $tempDir = New-TempWorkspace -StateJson $testStateJson
                $stateFile = Join-Path $tempDir 'poodle-state.json'
                $readmeFile = Join-Path $tempDir 'README.md'
                Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

                $originalLocation = Get-Location
                Set-Location $tempDir

                & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

                $result = Get-Content $stateFile -Raw | ConvertFrom-Json
                $result.mood.state | Should -Be $case.expectedState -Because "Score $($case.preScore + $case.bonus) should be $($case.expectedState)"

                Set-Location $originalLocation
                Remove-Item $tempDir -Recurse -Force
            }
        }
    }

    Describe 'README Update' {

        It 'Should update README with restored mood' {
            $tempDir = New-TempWorkspace -StateJson $script:CooldownActiveStateJson
            $stateFile = Join-Path $tempDir 'poodle-state.json'
            $readmeFile = Join-Path $tempDir 'README.md'
            Set-Content -Path $readmeFile -Value $script:ReadmeWithPoodle

            $originalLocation = Get-Location
            Set-Location $tempDir

            & $script:ScriptPath -GitHubToken 'fake-token' -GitHubUser 'testuser'

            $readme = Get-Content $readmeFile -Raw
            $readme | Should -Match 'HAPPY'
            $readme | Should -Match '70/100'

            Set-Location $originalLocation
            Remove-Item $tempDir -Recurse -Force
        }
    }
}
