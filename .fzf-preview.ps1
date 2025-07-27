param([string]$input)
$hash = ($input -split ' ')[0]
git show --color=always --stat $hash | Write-Output
