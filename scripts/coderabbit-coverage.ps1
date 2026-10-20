<#
.SYNOPSIS
  Measures CodeRabbit review coverage, approval rates, and comment density for GitHub repositories.
.PARAMETER Org
  GitHub organization or user (default: mgtba2003mgtba-boop).
.PARAMETER Repo
  GitHub repository name (default: mohadarati-app).
.PARAMETER Days
  Number of days to analyze (default: 30).
#>
param (
    [string]$Org = "mgtba2003mgtba-boop",
    [string]$Repo = "mohadarati-app",
    [int]$Days = 30
)

Write-Host "=== CodeRabbit Review Coverage & Observability ===" -ForegroundColor Cyan
Write-Host "Repository: $Org/$Repo" -ForegroundColor Yellow
Write-Host "Period: Last $Days days" -ForegroundColor Yellow
Write-Host ""

$since = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
    $pullsJson = gh api "repos/$Org/$Repo/pulls?state=all&per_page=50&sort=created&direction=desc" 2>$null
    if (-not $pullsJson) {
        Write-Host "No PRs found or GitHub CLI not authenticated." -ForegroundColor Red
        exit 0
    }

    $pulls = $pullsJson | ConvertFrom-Json
    $targetPulls = $pulls | Where-Object { $_.created_at -ge $since }

    $total = $targetPulls.Count
    $reviewed = 0
    $approved = 0
    $changesRequested = 0

    foreach ($pr in $targetPulls) {
        $reviewsJson = gh api "repos/$Org/$Repo/pulls/$($pr.number)/reviews" 2>$null
        if ($reviewsJson) {
            $reviews = $reviewsJson | ConvertFrom-Json
            $crReview = $reviews | Where-Object { $_.user.login -eq "coderabbitai[bot]" } | Select-Object -Last 1
            if ($crReview) {
                $reviewed++
                if ($crReview.state -eq "APPROVED") { $approved++ }
                if ($crReview.state -eq "CHANGES_REQUESTED") { $changesRequested++ }
            }
        }
    }

    if ($total -gt 0) {
        $coveragePct = [math]::Round(($reviewed / $total) * 100)
        Write-Host "Total PRs Analyzed: $total" -ForegroundColor Green
        Write-Host "Reviewed by CodeRabbit: $reviewed ($coveragePct%)" -ForegroundColor Green
        Write-Host "  - Approved: $approved" -ForegroundColor Green
        Write-Host "  - Changes Requested: $changesRequested" -ForegroundColor Yellow
    } else {
        Write-Host "No PRs created in the last $Days days." -ForegroundColor Gray
    }
} catch {
    Write-Host "Error executing observability probe: $_" -ForegroundColor Red
}
