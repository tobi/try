function try {
    param(
        [string]$Command,
        [string]$Arg1,
        [string]$Arg2
    )

    $baseDir = Join-Path $HOME "src\tries"

    # Helper to check Git repo
    function Is-GitRepo {
        git rev-parse --is-inside-work-tree > $null 2>&1
        return $LASTEXITCODE -eq 0
    }

    # Help
    if ($Command -eq "--help" -or $Command -eq "-h") {
        Write-Host "try - A simple temporary workspace manager (PowerShell Version)"
        Write-Host ""
        Write-Host "Usage (Note: use '&' prefix to avoid keyword conflict):"
        Write-Host "  & try                            List up to 10 most recent experiment directories"
        Write-Host "  & try <project-name>             Create and enter a dated directory for a new project"
        Write-Host "  & try clone <url> [name]         Clone a git repo into a dated directory and enter it"
        Write-Host "  & try worktree <name>            Create a git worktree from current repo and enter it"
        Write-Host "  & try --help (-h)                Show this help message"
        Write-Host ""
        Write-Host "Directories are stored in: $baseDir"
        return
    }

    # List recent tries
    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-Host "Usage: & try <project-name> or & try <git-url>"
        Write-Host "Recent tries in $baseDir"
        if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null }
        Get-ChildItem -Path $baseDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 10 -ExpandProperty Name
        return
    }

    # Clone
    if ($Command -eq "clone") {
        $url = $Arg1
        $customName = $Arg2
        if ([string]::IsNullOrWhiteSpace($url)) {
            Write-Error "Clone command requires a URL. Usage: & try clone <url> [name]"
            return
        }

        $repoName = ($url -split "/")[-1] -replace "\.git$", ""
        $projectName = if ([string]::IsNullOrWhiteSpace($customName)) { $repoName } else { $customName }
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $targetDir = Join-Path $baseDir "$dateStr-$projectName"

        if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null }
        
        if (!(Test-Path $targetDir)) {
            Write-Host "Cloning $url into $targetDir..."
            git clone $url $targetDir
            if ($LASTEXITCODE -ne 0) { return }
        } else {
            Write-Host "Directory $targetDir already exists. Entering it."
        }
        Set-Location $targetDir
        Write-Host "Entered: $targetDir"
        return
    }

    # Worktree
    if ($Command -eq "worktree") {
        $wtName = $Arg1
        if ([string]::IsNullOrWhiteSpace($wtName)) {
            Write-Error "Worktree command requires a name."
            return
        }
        
        if (-not (Is-GitRepo)) {
            Write-Error "You must be inside a Git repository to use 'worktree'."
            return
        }

        $currentRepoRoot = git rev-parse --show-toplevel
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $targetDir = Join-Path $baseDir "$dateStr-$wtName"

        if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null }

        if (!(Test-Path $targetDir)) {
            Write-Host "Creating worktree '$wtName' from '$currentRepoRoot'..."
            git worktree add $targetDir $wtName
            if ($LASTEXITCODE -ne 0) { return }
        } else {
            Write-Host "Worktree directory $targetDir already exists. Entering it."
        }
        Set-Location $targetDir
        Write-Host "Entered: $targetDir"
        return
    }

    # New Project or Direct Git URL
    $projectName = $Command
    if ($projectName -match "^http" -or $projectName -match "^git@") {
        $repoName = ($projectName -split "/")[-1] -replace "\.git$", ""
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $targetDir = Join-Path $baseDir "$dateStr-$repoName"
        
        if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null }
        
        if (!(Test-Path $targetDir)) {
            git clone $projectName $targetDir
        } else {
            Write-Host "Directory $targetDir already exists."
        }
        Set-Location $targetDir
        return
    }

    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $targetDir = Join-Path $baseDir "$dateStr-$projectName"
    
    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    Set-Location $targetDir
    Write-Host "Entered: $targetDir"
}