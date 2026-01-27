param(
    [string]$RepoName = "NYC-Taxi-Data-Engineering-Project",
    [string]$Description = "NYC Taxi Data Engineering Project - infra, ingestion, analytics",
    [bool]$Private = $false,
    [string]$Org = $null
)

if (-not $env:GITHUB_TOKEN) {
    Write-Error "GITHUB_TOKEN environment variable is required."
    exit 1
}

$headers = @{ Authorization = "token $($env:GITHUB_TOKEN)"; Accept = 'application/vnd.github+json' }

if (-not $env:GITHUB_USER) {
    $user = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers -Method Get
    if (-not $user.login) { Write-Error "Could not determine GitHub user. Set GITHUB_USER or provide a valid token."; exit 1 }
    $env:GITHUB_USER = $user.login
}

$body = @{ name = $RepoName; description = $Description; private = $Private } | ConvertTo-Json

if ($Org) { $url = "https://api.github.com/orgs/$Org/repos" } else { $url = 'https://api.github.com/user/repos' }

Write-Host "Creating repository $RepoName at $url as $($env:GITHUB_USER)"

try {
    $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ErrorAction Stop
} catch {
    Write-Error "GitHub API error: $_"
    exit 1
}

if (-not $resp.clone_url) { Write-Error "Failed to get clone_url from response"; exit 1 }

$cloneUrl = $resp.clone_url
Write-Host "Repository created: $cloneUrl"

# Add remote and push
if (git remote get-url origin -ErrorAction SilentlyContinue) { git remote remove origin }
git remote add origin $cloneUrl

Write-Host "Pushing current branch to origin..."
git push -u origin HEAD:master

Write-Host "Done. Repository available at: $cloneUrl"