<#
.SYNOPSIS
    Pester tests for Handle-PoodleInteraction.ps1

.DESCRIPTION
    Comprehensive unit, integration, and contract tests for the poodle interaction handler.
    All tests use real temporary state files and global-scope capture lists to avoid
    Pester 5 mock scoping issues.

.NOTES
    Uses Pester 5+ syntax with BeforeAll/BeforeEach discovery and run phases.
    Mock body data is captured via [System.Collections.Generic.List[object]] (reference type)
    stored in $global: scope to survive Pester mock scope boundaries.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Handle-PoodleInteraction.ps1'
    $script:FixturePath = Join-Path $PSScriptRoot 'Fixtures'

    # Pre-load fixture data
    $script:EmptyStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-empty.json') -Raw
    $script:SeededStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-seeded.json') -Raw
    $script:RateLimitedStateJson = Get-Content (Join-Path $script:FixturePath 'poodle-state-rate-limited.json') -Raw

    function New-TempWorkspace {
        param([string]$StateJson)
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PoodleTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content -Path (Join-Path $tempDir 'poodle-state.json') -Value $StateJson
        return $tempDir
    }
}

AfterAll {
    # Clean up any leftover globals
    Remove-Variable -Name 'PesterCapture' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Handle-PoodleInteraction.ps1 - Unit Tests' {

    Describe 'Command Detection' {

        BeforeEach {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            $script:OriginalLocation = Get-Location
            Set-Location $script:TempDir

            $global:PesterCapture = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-RestMethod {
                $global:PesterCapture.Add(@{
                    Uri     = $Uri
                    Method  = $Method
                    Body    = $Body
                    Headers = $Headers
                })
            }
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should detect "!pet" as a pet interaction' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you for the pet' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }

        It 'Should detect "pet the poodle" as a pet interaction' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText 'pet the poodle' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you for the pet' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }

        It 'Should detect "!feed" as a feed interaction' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!feed' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you for the treat' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }

        It 'Should detect "!treat" as a feed interaction' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!treat' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you for the treat' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }

        It 'Should detect "feed the poodle" as a feed interaction' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText 'feed the poodle' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you for the treat' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }

        It 'Should post help message for unrecognized commands' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText 'hello poodle' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentBodies = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'confused poodle noises' }
            $commentBodies | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Help Path - Issue Close Behavior' {

        BeforeEach {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            $script:OriginalLocation = Get-Location
            Set-Location $script:TempDir

            $global:PesterCapture = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-RestMethod {
                $global:PesterCapture.Add(@{
                    Uri     = $Uri
                    Method  = $Method
                    Body    = $Body
                    Headers = $Headers
                })
            }
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should close issue when unrecognized command comes from a new issue' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '99' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText 'hello' `
                -InteractionUser 'testuser' `
                -InteractionType 'issues' `
                -Repository 'Ba4bes/Ba4bes'

            $closeCalls = $global:PesterCapture | Where-Object {
                $_.Method -eq 'Patch' -and $_.Body -and ($_.Body | ConvertFrom-Json).state -eq 'closed'
            }
            $closeCalls | Should -Not -BeNullOrEmpty
        }

        It 'Should NOT close issue when unrecognized command comes from a comment' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText 'hello' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $closeCalls = $global:PesterCapture | Where-Object {
                $_.Method -eq 'Patch' -and $_.Body -and ($_.Body | ConvertFrom-Json).state -eq 'closed'
            }
            $closeCalls | Should -BeNullOrEmpty
        }
    }

    Describe 'Rate Limiting' {

        BeforeEach {
            $script:OriginalLocation = Get-Location
            $global:PesterCapture = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-RestMethod {
                $global:PesterCapture.Add(@{
                    Uri     = $Uri
                    Method  = $Method
                    Body    = $Body
                    Headers = $Headers
                })
            }
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            if ($script:TempDir -and (Test-Path $script:TempDir)) {
                Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should allow interaction when user has no prior interactions' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'newuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you' }
            $thankYou | Should -Not -BeNullOrEmpty
        }

        It 'Should block interaction when user has 5 interactions in last 24 hours' {
            $script:TempDir = New-TempWorkspace -StateJson $script:RateLimitedStateJson
            Set-Location $script:TempDir

            Mock Get-Date { return [datetime]'2026-02-08T06:00:00Z' }

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'spamuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $rateLimitMsg = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'tired from all the attention' }
            $rateLimitMsg | Should -Not -BeNullOrEmpty
        }

        It 'Should allow interaction when prior interactions are older than 24 hours' {
            $state = $script:EmptyStateJson | ConvertFrom-Json
            $state.rateLimits | Add-Member -NotePropertyName 'olduser' -NotePropertyValue @(
                '2026-02-06T01:00:00Z',
                '2026-02-06T02:00:00Z',
                '2026-02-06T03:00:00Z',
                '2026-02-06T04:00:00Z',
                '2026-02-06T05:00:00Z'
            ) -Force
            $oldUserStateJson = $state | ConvertTo-Json -Depth 10

            $script:TempDir = New-TempWorkspace -StateJson $oldUserStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'olduser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you' }
            $thankYou | Should -Not -BeNullOrEmpty
        }

        It 'Should show correct remaining interactions count' {
            $state = $script:EmptyStateJson | ConvertFrom-Json
            $recentTimestamp1 = (Get-Date).ToUniversalTime().AddHours(-2).ToString('o')
            $recentTimestamp2 = (Get-Date).ToUniversalTime().AddHours(-1).ToString('o')
            $state.rateLimits | Add-Member -NotePropertyName 'partialuser' -NotePropertyValue @(
                $recentTimestamp1,
                $recentTimestamp2
            ) -Force
            $partialStateJson = $state | ConvertTo-Json -Depth 10

            $script:TempDir = New-TempWorkspace -StateJson $partialStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'partialuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Remaining interactions today: 2/5' }
            $thankYou | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'State Mutation' {

        BeforeEach {
            $script:OriginalLocation = Get-Location
            Mock Invoke-RestMethod {}
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            if ($script:TempDir -and (Test-Path $script:TempDir)) {
                Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should increment totalPets for !pet command' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $updatedState.interactions.totalPets | Should -Be 1
            $updatedState.interactions.totalFeeds | Should -Be 0
        }

        It 'Should increment totalFeeds for !feed command' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!feed' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $updatedState.interactions.totalFeeds | Should -Be 1
            $updatedState.interactions.totalPets | Should -Be 0
        }

        It 'Should add interaction bonus of 3 points' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $updatedState.decay.interactionBonus | Should -Be 3
        }

        It 'Should accumulate interaction bonus from seeded state' {
            $script:TempDir = New-TempWorkspace -StateJson $script:SeededStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!feed' `
                -InteractionUser 'newuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $updatedState.decay.interactionBonus | Should -Be 12
        }

        It 'Should add a log entry with correct fields' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'loguser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $logEntry = @($updatedState.interactions.log) | Select-Object -Last 1
            $logEntry.username | Should -Be 'loguser'
            $logEntry.type | Should -Be 'pet'
            $logEntry.issueNum | Should -Be 42
            $logEntry.timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should cap log at 100 entries' {
            $state = $script:EmptyStateJson | ConvertFrom-Json
            $state.interactions.log = @(1..100 | ForEach-Object {
                [PSCustomObject]@{
                    username  = "user$_"
                    type      = 'pet'
                    timestamp = '2026-02-07T12:00:00Z'
                    issueNum  = $_
                }
            })
            $overflowStateJson = $state | ConvertTo-Json -Depth 10

            $script:TempDir = New-TempWorkspace -StateJson $overflowStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'overflow' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            @($updatedState.interactions.log).Count | Should -BeLessOrEqual 100
        }

        It 'Should add rate limit entry for user' {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            Set-Location $script:TempDir

            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'rateuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
            $updatedState.rateLimits.rateuser | Should -Not -BeNullOrEmpty
            @($updatedState.rateLimits.rateuser).Count | Should -Be 1
        }
    }

    Describe 'Reply Templates' {

        BeforeEach {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            $script:OriginalLocation = Get-Location
            Set-Location $script:TempDir

            $global:PesterCapture = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-RestMethod {
                $global:PesterCapture.Add(@{
                    Uri     = $Uri
                    Method  = $Method
                    Body    = $Body
                    Headers = $Headers
                })
            }
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should include pet emoji and correct action word in pet response' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you' }
            $thankYou | Should -Match '🐾'
            $thankYou | Should -Match 'pet'
            $thankYou | Should -Match 'loves the gentle pets'
        }

        It 'Should include feed emoji and correct action word in feed response' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!feed' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you' }
            $thankYou | Should -Match '🍖'
            $thankYou | Should -Match 'treat'
            $thankYou | Should -Match 'happily munches on the treat'
        }

        It 'Should include interaction stats in thank-you reply' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $thankYou = $global:PesterCapture |
                Where-Object { $_.Body } |
                ForEach-Object { ($_.Body | ConvertFrom-Json).body } |
                Where-Object { $_ -match 'Thank you' }
            $thankYou | Should -Match 'Interaction bonus: \+3 points'
            $thankYou | Should -Match 'Remaining interactions today:'
            $thankYou | Should -Match 'Total pets received:'
        }
    }

    Describe 'GitHub API Calls' {

        BeforeEach {
            $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
            $script:OriginalLocation = Get-Location
            Set-Location $script:TempDir

            $global:PesterCapture = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-RestMethod {
                $global:PesterCapture.Add(@{
                    Uri     = $Uri
                    Method  = $Method
                    Body    = $Body
                    Headers = $Headers
                })
            }
        }

        AfterEach {
            Set-Location $script:OriginalLocation
            Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Should call the correct comment API endpoint' {
            & $script:ScriptPath `
                -GitHubToken 'fake-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $commentCalls = $global:PesterCapture | Where-Object {
                $_.Uri -match 'issues/42/comments' -and $_.Method -eq 'Post'
            }
            $commentCalls | Should -Not -BeNullOrEmpty
        }

        It 'Should use Bearer token in authorization header' {
            & $script:ScriptPath `
                -GitHubToken 'my-secret-token' `
                -IssueNumber '42' `
                -IssueTitle 'Poodle Issue' `
                -InteractionText '!pet' `
                -InteractionUser 'testuser' `
                -InteractionType 'issue_comment' `
                -Repository 'Ba4bes/Ba4bes'

            $firstCall = $global:PesterCapture | Select-Object -First 1
            $firstCall.Headers['Authorization'] | Should -Be 'Bearer my-secret-token'
        }
    }
}

Describe 'Handle-PoodleInteraction.ps1 - Integration Tests' {

    BeforeEach {
        $script:TempDir = New-TempWorkspace -StateJson $script:EmptyStateJson
        $script:OriginalLocation = Get-Location
        Set-Location $script:TempDir
    }

    AfterEach {
        Set-Location $script:OriginalLocation
        Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should mutate state file correctly for a pet interaction' {
        Mock Invoke-RestMethod {}

        & $script:ScriptPath `
            -GitHubToken 'fake-token' `
            -IssueNumber '42' `
            -IssueTitle 'Poodle Issue' `
            -InteractionText '!pet' `
            -InteractionUser 'integrationuser' `
            -InteractionType 'issue_comment' `
            -Repository 'Ba4bes/Ba4bes'

        $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
        $updatedState.interactions.totalPets | Should -Be 1
        $updatedState.interactions.totalFeeds | Should -Be 0
        $updatedState.decay.interactionBonus | Should -Be 3
        @($updatedState.interactions.log).Count | Should -Be 1
        $updatedState.interactions.log[0].username | Should -Be 'integrationuser'
        $updatedState.interactions.log[0].type | Should -Be 'pet'
        @($updatedState.rateLimits.integrationuser).Count | Should -Be 1
    }

    It 'Should mutate state file correctly for a feed interaction on seeded state' {
        Set-Content -Path './poodle-state.json' -Value $script:SeededStateJson

        Mock Invoke-RestMethod {}

        & $script:ScriptPath `
            -GitHubToken 'fake-token' `
            -IssueNumber '42' `
            -IssueTitle 'Poodle Issue' `
            -InteractionText '!feed' `
            -InteractionUser 'newvisitor' `
            -InteractionType 'issue_comment' `
            -Repository 'Ba4bes/Ba4bes'

        $updatedState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
        $updatedState.interactions.totalPets | Should -Be 5
        $updatedState.interactions.totalFeeds | Should -Be 4
        $updatedState.decay.interactionBonus | Should -Be 12
        @($updatedState.interactions.log).Count | Should -Be 4
    }
}

Describe 'Handle-PoodleInteraction.ps1 - Contract Tests' {

    BeforeAll {
        $contractDir = New-TempWorkspace -StateJson $script:EmptyStateJson
        $contractOrigLocation = Get-Location
        Set-Location $contractDir

        Mock Invoke-RestMethod {}

        & $script:ScriptPath `
            -GitHubToken 'fake-token' `
            -IssueNumber '42' `
            -IssueTitle 'Poodle Issue' `
            -InteractionText '!pet' `
            -InteractionUser 'contractuser' `
            -InteractionType 'issue_comment' `
            -Repository 'Ba4bes/Ba4bes'

        $script:ResultState = Get-Content './poodle-state.json' -Raw | ConvertFrom-Json
        Set-Location $contractOrigLocation
        Remove-Item $contractDir -Recurse -Force
    }

    It 'Should have interactions.log as an array' {
        @($script:ResultState.interactions.log).Count | Should -BeGreaterOrEqual 1
    }

    It 'Should have required fields in each log entry' {
        $logEntry = @($script:ResultState.interactions.log)[0]
        $logEntry.PSObject.Properties.Name | Should -Contain 'username'
        $logEntry.PSObject.Properties.Name | Should -Contain 'type'
        $logEntry.PSObject.Properties.Name | Should -Contain 'timestamp'
        $logEntry.PSObject.Properties.Name | Should -Contain 'issueNum'
    }

    It 'Should have log entry timestamp in ISO 8601 format' {
        $logEntry = @($script:ResultState.interactions.log)[0]
        { [datetime]::Parse($logEntry.timestamp) } | Should -Not -Throw
    }

    It 'Should have rateLimits entries as ISO timestamp arrays' {
        $rateLimitEntries = @($script:ResultState.rateLimits.contractuser)
        $rateLimitEntries.Count | Should -BeGreaterOrEqual 1
        foreach ($entry in $rateLimitEntries) {
            { [datetime]::Parse($entry) } | Should -Not -Throw
        }
    }

    It 'Should have decay.interactionBonus as an integer' {
        $script:ResultState.decay.interactionBonus | Should -BeOfType [System.Int64]
    }

    It 'Should preserve overall JSON structure' {
        $script:ResultState.PSObject.Properties.Name | Should -Contain 'mood'
        $script:ResultState.PSObject.Properties.Name | Should -Contain 'decay'
        $script:ResultState.PSObject.Properties.Name | Should -Contain 'interactions'
        $script:ResultState.PSObject.Properties.Name | Should -Contain 'contributions'
        $script:ResultState.PSObject.Properties.Name | Should -Contain 'rateLimits'
    }
}
