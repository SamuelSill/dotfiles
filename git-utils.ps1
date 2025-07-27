function gst {
    git status
}

# Helper to get the main branch name of the repository
function main-branch-name {
    git symbolic-ref --short refs/remotes/origin/HEAD
}
Set-Alias mbn main-branch-name

# Select a commit from the current branch history
function select-commit-branch {
    $main = main-branch-name
    $current = git branch --show-current
    $mergeBase = git merge-base $current $main
    $commits = git log --pretty=format:"%H %s (%ci)" --abbrev-commit "$mergeBase.."
    $scriptDir = $PSScriptRoot
    $selected = $commits | fzf --height=40% --border --ansi
    if ($selected) {
        return ($selected -split ' ')[0]
    }
}
Set-Alias selcb select-commit-branch

# Select any commit
function select-commit {
    $commits = git log --pretty=format:"%H %s (%ci)" --abbrev-commit
    $scriptDir = $PSScriptRoot
    $selected = $commits | fzf --height=40% --border --ansi
    if ($selected) {
        return ($selected -split ' ')[0]
    }
}
Set-Alias selc select-commit

# Select a file in the repo
function select-file {
    $file = Get-ChildItem -Recurse -File | ForEach-Object { $_.FullName } | fzf --height=40% --border --ansi --preview 'bat --color=always {} || cat {}'
    if ($file) { return $file }
}
Set-Alias self select-file

# Interactive rebase current branch against main
function interactive-rebase {
    $main = main-branch-name
    $current = git branch --show-current
    $mergeBase = git merge-base $current $main
    git rebase -i "$mergeBase"
}
Set-Alias ir interactive-rebase

# Git graph logs
function graph1 {
    git log --graph --abbrev-commit --decorate --format=format:"%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)" --all
}

function graph2 {
    git log --graph --abbrev-commit --decorate --format=format:"%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)`n          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)"
}

Set-Alias graph graph1

# File history
function diff-history {
    $file = select-file
    git log -p -- "$file"
}
Set-Alias dh diff-history

function diff-history-branch {
    $main = main-branch-name
    $current = git branch --show-current
    $mergeBase = git merge-base $current $main
    $file = select-file
    git log -p "$mergeBase.." -- "$file"
}
Set-Alias dhb diff-history-branch

function commit-history {
    $file = select-file
    git log --oneline -- "$file"
}
Set-Alias ch commit-history

function commit-history-branch {
    $main = main-branch-name
    $current = git branch --show-current
    $mergeBase = git merge-base $current $main
    $file = select-file
    git log --oneline "$mergeBase.." -- "$file"
}
Set-Alias chb commit-history-branch

# Temp commit
function temp-commit {
    git commit --no-verify -m 'temp'
}

Set-Alias tc temp-commit

# Grep history (branch)
function grep-history-branch {
    param([string]$Pattern)
    $main = main-branch-name
    $current = git branch --show-current
    $mergeBase = git merge-base $current $main
    git log --oneline -G"$Pattern" "$mergeBase.."
}
Set-Alias grephb grep-history-branch

# Grep history (all)
function grep-history {
    param([string]$Pattern)
    git log --oneline -G"$Pattern"
}
Set-Alias greph grep-history

# Grep selected commit (branch)
function grep-commit-branch {
    param([string]$Pattern)
    $hash = select-commit-branch
    git show $hash | Select-String -Context 5,5 $Pattern
}
Set-Alias grepcb grep-commit-branch

# Grep selected commit
function grep-commit {
    param([string]$Pattern)
    $hash = select-commit
    git show $hash | Select-String -Context 5,5 $Pattern
}
Set-Alias grepc grep-commit

# Fixup staged changes in a selected commit (branch)
function fixup {
    $hash = select-commit-branch
    git commit --fixup=$hash
    git -c core.editor=true rebase -i --autosquash "$($hash)~1"
}

# Check for local changes
function check-no-local-changes {
    $status = git status --porcelain
    if ($status) {
        Write-Host "There are local changes ($(Split-Path -Leaf (Get-Location))). Please stash or commit them." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function diff-origin {
    $branch = git rev-parse --abbrev-ref HEAD
    $remote = "origin/$branch"

    git rev-parse --verify --quiet "$remote" > $null
    if ($LASTEXITCODE -eq 0) {
        git diff $remote
    } else {
        Write-Host "Remote branch '$remote' does not exist (locally). Try 'git fetch' first." -ForegroundColor Yellow
    }
}

# Get closest version tag containing a selected commit
function get-commit-version {
    $commit = select-commit
    $milestone = git branch -r --contains $commit --format='%(refname:short)' | Where-Object { $_ -match '^origin/milestone-' } | Sort-Object | Select-Object -First 1

    $branches = @("origin/main")
    if ($milestone) { $branches += $milestone }

    foreach ($branch in $branches) {
        $tag = git rev-list --ancestry-path "$commit..$branch" --format="%D" --reverse |
               Select-String -Pattern 'tag: [^,)]*' | ForEach-Object { ($_ -split ' ')[1] } | Select-Object -First 1
        if ($tag) {
            Write-Host "${branch}: ${tag}"
        }
    }
}
Set-Alias gcv get-commit-version
