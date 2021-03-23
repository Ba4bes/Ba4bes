# Collect all blogposts through a webrequest
$AllBlogPosts = @()
$IsNotDone = $true
$Regex = 'https:\/\/4bes\.nl\/[0-9]{4}\/[0-9]{2}\/[0-9]{2}\/.*\/'
$i = 1
While ($IsNotDone) {
    try {
        $Blogposts = Invoke-WebRequest "https://4bes.nl/page/$i/"
    }
    Catch {
        $IsNotDone = $False
    }
    $Blogpostlinks = $Blogposts.Links | Where-Object { $_.href -match $Regex -and ![string]::IsNullOrEmpty($_.title) }

    $ALlBlogPosts += $Blogpostlinks | Select-Object -Unique title, href
    $i++
}

$RandomPost = $AllBlogPosts | Get-Random
$Post = Invoke-WebRequest $RandomPost.href

$Regex = '<meta property="og:image" content="https:\/\/4bes\.nl\/wp-content\/uploads\/.*\/>'
$Post.RawContent -match $Regex
$Imagelink = ($Matches[0] -replace '<meta property="og:image" content="') -replace '" />'

Write-Host "New Post: $($RandomPost.title) "

$NewMarkdown = @"
<!-- Link -->
## [$($RandomPost.title)]($($RandomPost.href))

<a href="$($RandomPost.href)"><img src="$ImageLink" height="250px"></a>

"@

$Readme = Get-Content ./README.md -Raw
Write-Host "OldReadMe"
$Readme
$Regex = '(?s)<!-- Link -->.*\r\n'
$NewReadme = $Readme -replace $Regex, $NewMarkdown
Write-Host "exporting new Readme"
Write-Host "New Readme"
$NewReadme
Set-Content -Path ./README.md -Value $NewReadme
