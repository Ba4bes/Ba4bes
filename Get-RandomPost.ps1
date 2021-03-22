$rssfeed = [xml](Invoke-WebRequest "https://4bes.nl/feed/" -UseBasicParsing)
$RandomPost = ($rssfeed.rss.channel.item) | Get-Random

$NewMarkdown = @"

## [$($RandomPost.title)]($($RandomPost.link))

$($RandomPost.description.'#cdata-section')

"@

$Readme = Get-Content .\README.md -Raw
$Regex = '(?s)<!-- Link -->.*\r\n'
$NewReadme = $Readme -replace $Regex, $NewMarkdown
$NewReadme | Out-File .\README.md
