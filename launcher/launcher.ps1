# Hollow Vein Mine launcher.
# Pulls the latest version of the game from GitHub (fast-forward only, never over
# local changes), prepares the Godot import cache, then starts the game.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:Root = Split-Path -Parent $PSScriptRoot
$script:SettingsDir = Join-Path $env:LOCALAPPDATA 'HollowVeinMine'
$script:SettingsFile = Join-Path $script:SettingsDir 'launcher.json'
$script:Git = $null
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) { $script:Git = $gitCmd.Source }
$script:GitCode = 0
$script:Job = $null
$script:AfterImport = $null

# --- Settings ----------------------------------------------------------------

function Read-Settings {
    $s = @{ godot_path = ''; close_on_play = $true }
    if (Test-Path $script:SettingsFile) {
        try {
            $json = Get-Content -Raw -Path $script:SettingsFile | ConvertFrom-Json
            if ($json.godot_path) { $s.godot_path = [string]$json.godot_path }
            if ($null -ne $json.close_on_play) { $s.close_on_play = [bool]$json.close_on_play }
        } catch {}
    }
    return $s
}

function Save-Settings {
    New-Item -ItemType Directory -Force -Path $script:SettingsDir | Out-Null
    [pscustomobject]$script:Settings | ConvertTo-Json | Set-Content -Encoding UTF8 -Path $script:SettingsFile
}

# --- Godot -------------------------------------------------------------------

function Get-GodotVersion([string]$Path) {
    $name = [System.IO.Path]::GetFileName($Path)
    if ($name -match 'v(\d+)\.(\d+)(?:\.(\d+))?') {
        $patch = 0
        if ($matches[3]) { $patch = $matches[3] }
        return [version]("{0}.{1}.{2}" -f $matches[1], $matches[2], $patch)
    }
    return [version]'0.0.0'
}

function Get-RequiredGodotVersion {
    $project = Join-Path $script:Root 'project.godot'
    if (Test-Path $project) {
        $m = Select-String -Path $project -Pattern 'config/features=PackedStringArray\("(\d+\.\d+)' | Select-Object -First 1
        if ($m) { return [version]($m.Matches[0].Groups[1].Value + '.0') }
    }
    return [version]'4.0.0'
}

function Find-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $candidates = @()
    foreach ($n in 'godot', 'godot4') {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $candidates += $c.Source }
    }
    $dirs = @(
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents",
        "$env:LOCALAPPDATA\Programs", "$env:USERPROFILE\scoop\apps", $env:ProgramFiles,
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Godot Engine"
    )
    foreach ($d in $dirs) {
        if ($d -and (Test-Path $d)) {
            $candidates += Get-ChildItem -Path $d -Filter 'Godot*.exe' -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '_console' } | ForEach-Object { $_.FullName }
        }
    }
    $best = $candidates | Sort-Object -Property @{ Expression = { Get-GodotVersion $_ } } -Descending | Select-Object -First 1
    return $best
}

# --- Git ---------------------------------------------------------------------

function Invoke-GitText {
    $out = & $script:Git -C $script:Root @args 2>$null
    $script:GitCode = $LASTEXITCODE
    return (($out | ForEach-Object { "$_" }) -join "`r`n")
}

function Get-UpstreamRef {
    $u = Invoke-GitText rev-parse --abbrev-ref --symbolic-full-name '@{u}'
    if ($script:GitCode -eq 0 -and $u) { return $u.Trim() }
    $branch = (Invoke-GitText rev-parse --abbrev-ref HEAD).Trim()
    $null = Invoke-GitText rev-parse --verify --quiet "refs/remotes/origin/$branch"
    if ($script:GitCode -eq 0) { return "origin/$branch" }
    return $null
}

# Runs a program without blocking the window; $OnDone gets the exit code (-1 on timeout).
function Start-Background([string]$File, [string]$Arguments, [int]$TimeoutSeconds, [scriptblock]$OnDone) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        & $OnDone -1
        return
    }
    $script:Job = @{ Process = $p; OnDone = $OnDone; Started = Get-Date; Timeout = $TimeoutSeconds }
}

# --- UI ----------------------------------------------------------------------

$colBg = [System.Drawing.Color]::FromArgb(24, 21, 20)
$colPanel = [System.Drawing.Color]::FromArgb(38, 34, 31)
$colGold = [System.Drawing.Color]::FromArgb(255, 214, 89)
$colText = [System.Drawing.Color]::FromArgb(235, 230, 220)
$colDim = [System.Drawing.Color]::FromArgb(150, 140, 128)
$colGood = [System.Drawing.Color]::FromArgb(140, 220, 140)
$colWarn = [System.Drawing.Color]::FromArgb(255, 160, 110)

function New-Control($Type, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $c = New-Object "System.Windows.Forms.$Type"
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size($W, $H)
    $form.Controls.Add($c)
    return $c
}

function New-FlatButton([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $b = New-Control 'Button' $X $Y $W $H
    $b.Text = $Text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(110, 85, 50)
    $b.BackColor = $colPanel
    $b.ForeColor = $colText
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Hollow Vein Mine - Launcher'
$form.ClientSize = New-Object System.Drawing.Size(640, 480)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $colBg
$form.ForeColor = $colText
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Control 'Label' 22 16 596 46
$title.Text = 'HOLLOW VEIN MINE'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $colGold

$versionLabel = New-Control 'Label' 26 64 592 22
$versionLabel.ForeColor = $colDim

$newsTitle = New-Control 'Label' 24 100 592 20
$newsTitle.Text = "WHAT'S NEW"
$newsTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$newsTitle.ForeColor = $colDim

$news = New-Control 'TextBox' 24 122 592 190
$news.Multiline = $true
$news.ReadOnly = $true
$news.ScrollBars = 'Vertical'
$news.BorderStyle = 'FixedSingle'
$news.BackColor = $colPanel
$news.ForeColor = $colText
$news.Font = New-Object System.Drawing.Font('Consolas', 9.5)

$statusLabel = New-Control 'Label' 24 322 592 22

$progress = New-Control 'ProgressBar' 24 348 592 6
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false

$checkButton = New-FlatButton 'Check for updates' 24 372 170 36
$godotButton = New-FlatButton 'Change Godot...' 204 372 150 36

$playButton = New-FlatButton 'PLAY' 436 366 180 54
$playButton.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$playButton.BackColor = $colGold
$playButton.ForeColor = [System.Drawing.Color]::FromArgb(30, 24, 18)
$playButton.FlatAppearance.BorderColor = $colGold

$closeBox = New-Control 'CheckBox' 24 420 400 24
$closeBox.Text = 'Close the launcher when the game starts'
$closeBox.ForeColor = $colDim

$godotLink = New-Control 'LinkLabel' 24 450 592 20
$godotLink.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$godotLink.LinkColor = $colDim
$godotLink.ActiveLinkColor = $colGold
$godotLink.ForeColor = $colDim

function Set-Status([string]$Text, $Color = $colText) {
    $statusLabel.Text = $Text
    $statusLabel.ForeColor = $Color
}

function Set-Busy([bool]$Busy, [string]$Text = '') {
    $progress.Visible = $Busy
    $playButton.Enabled = -not $Busy
    $checkButton.Enabled = -not $Busy
    $godotButton.Enabled = -not $Busy
    if ($Text) { Set-Status $Text $colText }
}

function Update-GodotLabel {
    if ($script:Godot) {
        $godotLink.Text = "Godot: $($script:Godot)"
        $godotLink.LinkArea = New-Object System.Windows.Forms.LinkArea(0, 0)
    } else {
        $godotLink.Text = 'Godot was not found. Click here to download it, then use "Change Godot...".'
        $godotLink.LinkArea = New-Object System.Windows.Forms.LinkArea(0, $godotLink.Text.Length)
    }
}

function Update-LocalInfo {
    if (-not $script:Git) {
        $versionLabel.Text = 'Local copy (install Git to get updates)'
        $news.Text = ''
        return
    }
    $count = Invoke-GitText rev-list --count HEAD
    if ($script:GitCode -ne 0) {
        $versionLabel.Text = 'Local copy (no version history yet)'
        $news.Text = ''
        return
    }
    $hash = Invoke-GitText rev-parse --short HEAD
    $date = Invoke-GitText log -1 --date=short '--pretty=format:%ad'
    $versionLabel.Text = "Build $count   |   $hash   |   $date"
    $news.Text = Invoke-GitText log -25 --date=short '--pretty=format:%ad   %s'
}

function Select-Godot {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select the Godot executable'
    $dialog.Filter = 'Godot (*.exe)|*.exe'
    if ($script:Godot) { $dialog.InitialDirectory = Split-Path -Parent $script:Godot }
    if ($dialog.ShowDialog($form) -ne 'OK') { return $false }
    $script:Godot = $dialog.FileName
    $script:Settings.godot_path = $script:Godot
    Save-Settings
    Update-GodotLabel
    Test-GodotVersion
    return $true
}

function Test-GodotVersion {
    if (-not $script:Godot) { return }
    $have = Get-GodotVersion $script:Godot
    $need = Get-RequiredGodotVersion
    if ($have -gt [version]'0.0.0' -and $have -lt $need) {
        Set-Status "This game needs Godot $($need.Major).$($need.Minor) or newer (you have $have)." $colWarn
    }
}

# --- Update flow ---------------------------------------------------------------

function Start-UpdateCheck {
    if (-not $script:Git) {
        Set-Status 'Git is not installed, so automatic updates are off. You can still play.' $colDim
        return
    }
    if (-not (Test-Path (Join-Path $script:Root '.git'))) {
        Set-Status 'This copy was not downloaded with Git, so it cannot update itself.' $colDim
        return
    }
    Set-Busy $true 'Checking GitHub for updates...'
    Start-Background $script:Git 'fetch --quiet origin' 60 { param($code) Complete-Fetch $code }
}

function Complete-Fetch([int]$Code) {
    if ($Code -ne 0) {
        Set-Busy $false
        Set-Status "Couldn't reach GitHub. You can still play the version you have." $colWarn
        return
    }
    $upstream = Get-UpstreamRef
    if (-not $upstream) {
        Set-Busy $false
        Set-Status 'This version has not been published to GitHub yet, so there is nothing to update.' $colDim
        return
    }
    $behind = [int](Invoke-GitText rev-list --count "HEAD..$upstream")
    $ahead = [int](Invoke-GitText rev-list --count "$upstream..HEAD")
    if ($behind -eq 0) {
        Set-Busy $false
        Update-LocalInfo
        if ($ahead -gt 0) {
            Set-Status "Up to date ($ahead local change(s) not published to GitHub yet)." $colGood
        } else {
            Set-Status 'Up to date.' $colGood
        }
        return
    }
    $dirty = Invoke-GitText status --porcelain --untracked-files=no
    if ($dirty) {
        Set-Busy $false
        Set-Status "$behind update(s) available, but this folder has unsaved changes. Update skipped." $colWarn
        return
    }
    $script:Incoming = $behind
    Set-Busy $true "Downloading $behind update(s)..."
    Start-Background $script:Git "merge --ff-only --quiet $upstream" 120 { param($code) Complete-Merge $code }
}

function Complete-Merge([int]$Code) {
    if ($Code -ne 0) {
        Set-Busy $false
        Set-Status 'Update failed: this copy has changes that conflict with GitHub.' $colWarn
        return
    }
    Update-LocalInfo
    $script:AfterImport = { Set-Status "Updated! $($script:Incoming) new change(s) installed." $colGood }
    Start-Import 'Updated! Preparing game files...'
}

# Godot needs its import cache (.godot/) before the game can run; rebuild it after updates.
function Start-Import([string]$Text) {
    if (-not $script:Godot) {
        Set-Busy $false
        & $script:AfterImport
        return
    }
    Set-Busy $true $Text
    Start-Background $script:Godot "--headless --path `"$($script:Root)`" --import" 300 {
        param($code)
        Set-Busy $false
        if ($code -ne 0) { Set-Status 'Godot could not prepare the game files.' $colWarn; return }
        & $script:AfterImport
    }
}

function Start-Game {
    if (-not $script:Godot -and -not (Select-Godot)) { return }
    if (-not (Test-Path (Join-Path $script:Root '.godot'))) {
        $script:AfterImport = { Start-GameProcess }
        Start-Import 'First launch: preparing game files...'
        return
    }
    Start-GameProcess
}

function Start-GameProcess {
    Start-Process -FilePath $script:Godot -ArgumentList "--path `"$($script:Root)`"" -WorkingDirectory $script:Root
    if ($closeBox.Checked) {
        $form.Close()
    } else {
        Set-Status 'Game started. Have fun down there!' $colGood
    }
}

# --- Wiring ----------------------------------------------------------------------

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
    if ($null -eq $script:Job) { return }
    $p = $script:Job.Process
    $elapsed = ((Get-Date) - $script:Job.Started).TotalSeconds
    if (-not $p.HasExited -and $elapsed -lt $script:Job.Timeout) { return }
    $code = -1
    if ($p.HasExited) { $code = $p.ExitCode } else { try { $p.Kill() } catch {} }
    $done = $script:Job.OnDone
    $script:Job = $null
    & $done $code
})

$playButton.Add_Click({ Start-Game })
$checkButton.Add_Click({ Start-UpdateCheck })
$godotButton.Add_Click({ [void](Select-Godot) })
$godotLink.Add_LinkClicked({ Start-Process 'https://godotengine.org/download/windows/' })
$closeBox.Add_CheckedChanged({
    $script:Settings.close_on_play = $closeBox.Checked
    Save-Settings
})
$form.Add_Shown({
    $timer.Start()
    Update-LocalInfo
    Test-GodotVersion
    Start-UpdateCheck
})
$form.Add_FormClosed({ $timer.Stop() })

$script:Settings = Read-Settings
$script:Godot = $null
if ($script:Settings.godot_path -and (Test-Path $script:Settings.godot_path)) {
    $script:Godot = $script:Settings.godot_path
} else {
    $script:Godot = Find-Godot
    if ($script:Godot) {
        $script:Settings.godot_path = $script:Godot
        Save-Settings
    }
}
$closeBox.Checked = $script:Settings.close_on_play
Update-GodotLabel

# Dot-sourcing (tests) builds the window without showing it.
if ($MyInvocation.InvocationName -ne '.') {
    [void]$form.ShowDialog()
}
