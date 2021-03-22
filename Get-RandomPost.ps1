$rssfeed = [xml](Invoke-WebRequest "https://4bes.nl/feed/" -UseBasicParsing)
$RandomPost = ($rssfeed.rss.channel.item) | Get-Random

$post = Invoke-WebRequest $RandomPost.link

$Regex = '<meta property="og:image" content="https:\/\/4bes\.nl\/wp-content\/uploads\/.*\/>'
$post.RawContent -match $Regex
$Imagelink = ($Matches[0] -replace '<meta property="og:image" content="') -replace '" />'


$NewMarkdown = @"
<!-- Link -->
## [$($RandomPost.title)]($($RandomPost.link))

<a href="$($RandomPost.link)"><img src="$ImageLink" height="250px"></a>

"@

$Readme = Get-Content .\README.md -Raw
$Regex = '(?s)<!-- Link -->.*\r\n'
$NewReadme = $Readme -replace $Regex, $NewMarkdown
$NewReadme | Out-File .\README.md

