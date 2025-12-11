function Invoke-Try {
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

    # Helper to get unique directory name with versioning
    function Get-UniqueDirectoryName {
        param([string]$BasePath, [string]$DatePrefix, [string]$Name)

        $initial = "$DatePrefix-$Name"
        $fullPath = Join-Path $BasePath $initial
        if (!(Test-Path $fullPath)) { return $Name }

        # Check if name ends with digits
        if ($Name -match '^(.*?)(\d+)$') {
            $stem = $Matches[1]
            $num = [int]$Matches[2] + 1
            while ($true) {
                $candidate = "$stem$num"
                $candidateFull = Join-Path $BasePath "$DatePrefix-$candidate"
                if (!(Test-Path $candidateFull)) { return $candidate }
                $num++
            }
        } else {
            # No numeric suffix; use -2 style
            $i = 2
            while ($true) {
                $candidate = "$Name-$i"
                $candidateFull = Join-Path $BasePath "$DatePrefix-$candidate"
                if (!(Test-Path $candidateFull)) { return $candidate }
                $i++
            }
        }
    }

    # Help
    if ($Command -eq "--help" -or $Command -eq "-h") {
        Write-Host "try - A simple temporary workspace manager (PowerShell Version)"
        Write-Host ""
        Write-Host "Usage (Note: use '&' prefix to avoid keyword conflict):"
        Write-Host "  & try                            List up to 10 most recent experiment directories"
        Write-Host "  & try <project-name>             Create and enter a dated directory for a new project"
        Write-Host "  & try . <name>                   Create a dated worktree dir for current repo"
        Write-Host "  & try .\path\to\repo [name]      Use another repo as the worktree source"
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

    # Dot notation: try . [name] or try .\path\to\repo [name]
    if ($Command -eq "." -or $Command.StartsWith(".\") -or $Command.StartsWith("./")) {
        # Determine repo directory
        if ($Command -eq ".") {
            $repoDir = Get-Location
            $customName = $Arg1
            # "try ." requires a name argument (too easy to invoke accidentally)
            if ([string]::IsNullOrWhiteSpace($customName)) {
                Write-Error "'try .' requires a name argument. Usage: & try . <name>"
                return
            }
        } else {
            $repoDir = Resolve-Path $Command -ErrorAction SilentlyContinue
            if (-not $repoDir) {
                Write-Error "Path not found: $Command"
                return
            }
            $customName = $Arg1
        }

        # Determine base name
        if ([string]::IsNullOrWhiteSpace($customName)) {
            $baseName = Split-Path $repoDir -Leaf
        } else {
            $baseName = $customName -replace '\s+', '-'
        }

        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $baseName = Get-UniqueDirectoryName -BasePath $baseDir -DatePrefix $dateStr -Name $baseName
        $targetDir = Join-Path $baseDir "$dateStr-$baseName"

        if (!(Test-Path $baseDir)) { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null }

        # Check if it's a git repo and use worktree
        $gitDir = Join-Path $repoDir ".git"
        if (Test-Path $gitDir) {
            if (!(Test-Path $targetDir)) {
                Write-Host "Creating worktree from '$repoDir'..."
                git -C $repoDir worktree add --detach $targetDir 2>$null
                if ($LASTEXITCODE -ne 0) {
                    # Fallback: just create directory
                    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                }
            }
        } else {
            # Not a git repo, just create directory
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
        }

        Set-Location $targetDir
        Write-Host "Entered: $targetDir"
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

# Alias: use "& try" to call
Set-Alias -Name try -Value Invoke-Try -Scope Global