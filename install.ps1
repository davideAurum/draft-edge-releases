[CmdletBinding()]
param(
  [ValidateSet('zip', 'portable', 'git')]
  [string]$Mode = 'zip',
  [string]$Dir = '',
  [string]$Ref = 'master',
  [string]$Repo = 'https://github.com/davideAurum/draft-edge.git',
  [string]$Feed = 'https://raw.githubusercontent.com/davideAurum/draft-edge-releases/main/latest-web.json',
  [switch]$NoPath
)

<#
  Draft Edge installer. Installs Draft Edge, or updates an earlier install, and
  (except in portable mode) puts a `draftedge` command on your user PATH. Run it
  again to update. It never touches data/.

  Modes:
    zip       (default) The latest release from github.com/davideAurum/draft-edge-releases.
              Needs Python 3 on PATH; nothing else. Installs to %LOCALAPPDATA%\DraftEdge\app.
    portable  The latest release with its own Python bundled, so the PC needs nothing
              installed. Installs to a folder you can move or copy, with your league data
              inside it; changes nothing outside that folder (no PATH, no registry).
              Default folder: %USERPROFILE%\DraftEdge.
    git       A clone of the source repository, for development. Needs Git and, while the
              repository is private, a signed-in GitHub CLI.

  From PowerShell:
    irm https://raw.githubusercontent.com/davideAurum/draft-edge-releases/main/install.ps1 | iex

  With options (here the portable build in a chosen folder):
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/davideAurum/draft-edge-releases/main/install.ps1))) -Mode portable -Dir D:\DraftEdge

  From a checkout:
    .\install.ps1 [-Mode zip|portable|git] [-Dir <folder>] [-Ref <branch-or-tag>] [-NoPath]

  Windows only. Downloads come only from the releases repository and are installed
  only when their size and SHA-256 match the release feed.
#>

function Install-DraftEdge {
  param([string]$Mode, [string]$Dir, [string]$Ref, [string]$Repo, [string]$Feed, [switch]$NoPath)

  $ErrorActionPreference = 'Stop'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

  if (-not $env:LOCALAPPDATA) { throw 'Draft Edge installs on Windows only (LOCALAPPDATA is not set).' }
  if (-not $Dir) {
    $Dir = if ($Mode -eq 'portable') { Join-Path $env:USERPROFILE 'DraftEdge' } else { Join-Path $env:LOCALAPPDATA 'DraftEdge\app' }
  }

  if ($Mode -eq 'git') { Install-FromGit -Dir $Dir -Ref $Ref -Repo $Repo } else { Install-FromRelease -Mode $Mode -Dir $Dir -Feed $Feed }

  if ($Mode -ne 'portable') {
    $binDir = Join-Path $env:LOCALAPPDATA 'DraftEdge\bin'
    $null = New-Item -ItemType Directory -Force -Path $binDir
    $shim = Join-Path $binDir 'draftedge.cmd'
    Set-Content -Path $shim -Encoding ascii -Value "@call `"$(Join-Path $Dir 'draftedge.cmd')`" %*"

    if (-not $NoPath) {
      $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
      if (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (@($userPath, $binDir) | Where-Object { $_ }) -join ';', 'User')
        Write-Host "Added $binDir to your user PATH"
      }
      if (($env:Path -split ';') -notcontains $binDir) { $env:Path = "$env:Path;$binDir" }

      $found = (Get-Command draftedge -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
      if ($found -and $found -ne $shim) {
        Write-Warning "'draftedge' resolves to $found first. Remove it, or run $shim directly."
      }
    }
  }

  $version = ''
  $versionMatch = Select-String -Path (Join-Path $Dir 'app-version.js') -Pattern 'version: "([^"]+)"' | Select-Object -First 1
  if ($versionMatch) { $version = " $($versionMatch.Matches[0].Groups[1].Value)" }
  Write-Host ""
  Write-Host "Draft Edge$version is installed in $Dir"
  if ($Mode -eq 'portable') {
    Write-Host "Start it with: $(Join-Path $Dir 'draftedge.cmd')      (double-click works; move or copy the folder whenever you like)"
  } else {
    Write-Host "Start it with: draftedge      (draftedge -Help for the rest)"
  }
}

function Install-FromGit {
  param([string]$Dir, [string]$Ref, [string]$Repo)

  function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)." }
  }

  foreach ($tool in 'git', 'python') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "$tool is not on PATH. -Mode git needs Git and Python 3. (-Mode zip or -Mode portable need neither Git nor a repository login.)"
    }
  }
  Assert-Python3

  if (Test-Path (Join-Path $Dir '.git')) {
    if (Invoke-Git -C $Dir status --porcelain) {
      throw "$Dir has local changes. Commit or discard them, then run the installer again; it leaves a changed checkout alone."
    }
    Write-Host "Updating $Dir to $Ref"
    Invoke-Git -C $Dir fetch --quiet --tags --prune origin
    Invoke-Git -C $Dir checkout --quiet $Ref
    & git -C $Dir show-ref --verify --quiet "refs/remotes/origin/$Ref"
    if ($LASTEXITCODE -eq 0) { Invoke-Git -C $Dir merge --quiet --ff-only "origin/$Ref" }
  } elseif ((Test-Path $Dir) -and (Get-ChildItem -Force $Dir | Select-Object -First 1)) {
    throw "$Dir exists and is not a Draft Edge checkout. Pass -Dir with an empty or new folder."
  } else {
    Write-Host "Cloning $Repo ($Ref) into $Dir"
    Invoke-Git clone --quiet --branch $Ref $Repo $Dir
  }
}

function Assert-Python3 {
  # The Microsoft Store's python.exe stub is on PATH but is not Python.
  $major = try { & python -c "import sys; print(sys.version_info[0])" 2>$null } catch { '' }
  if ("$major".Trim() -ne '3') {
    throw "'python' does not run Python 3. Install it (winget install Python.Python.3.12) and make sure it is on PATH, or use -Mode portable, which brings its own."
  }
}

function Install-FromRelease {
  param([string]$Mode, [string]$Dir, [string]$Feed)

  $releases = 'https://github.com/davideAurum/draft-edge-releases/releases/download/'
  $loopbackFeed = $Feed -match '^http://(127\.0\.0\.1|localhost)[:/]'
  if ($Feed -notlike 'https://raw.githubusercontent.com/davideAurum/draft-edge-releases/*' -and -not $loopbackFeed) {
    throw "Refusing a feed that is not in the davideAurum/draft-edge-releases repository."
  }
  $kind = if ($Mode -eq 'portable') { 'portable' } else { 'app' }

  if (Test-Path (Join-Path $Dir '.git')) {
    throw "$Dir is a git checkout. Update it with 'draftedge -Update', or install with -Mode git."
  }
  $existing = (Test-Path $Dir) -and (Get-ChildItem -Force $Dir | Select-Object -First 1)
  if ($existing -and -not (Test-Path (Join-Path $Dir 'release-manifest.json'))) {
    throw "$Dir exists and is not a Draft Edge release install. Pass -Dir with an empty or new folder."
  }
  if ($kind -eq 'app') { Assert-Python3 }

  Write-Host "Reading the release feed"
  $feedData = Invoke-RestMethod -Uri $Feed -UseBasicParsing
  if ($feedData.format -ne 'draftEdge.web-update-feed' -or $feedData.version -ne 1) { throw 'The release feed is not in a format this installer understands.' }
  $release = $feedData.release
  $package = @($release.packages | Where-Object { $_.kind -eq $kind }) | Select-Object -First 1
  if (-not $package) { throw "Release $($release.version) has no '$kind' package." }
  if (-not ($package.url.StartsWith($releases) -or ($loopbackFeed -and $package.url -match '^http://(127\.0\.0\.1|localhost)[:/]'))) {
    throw "Refusing a download outside the releases repository: $($package.url)"
  }

  $work = Join-Path ([IO.Path]::GetTempPath()) ('draftedge-install-' + [guid]::NewGuid().ToString('N'))
  $null = New-Item -ItemType Directory -Force -Path $work
  try {
    $archive = Join-Path $work $package.file
    Write-Host "Downloading Draft Edge $($release.version) ($kind, $([math]::Round($package.bytes / 1MB, 1)) MB)"
    Invoke-WebRequest -Uri $package.url -OutFile $archive -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ((Get-Item $archive).Length -ne [int64]$package.bytes -or $actual -ne ([string]$package.sha256).ToLowerInvariant()) {
      throw "$($package.file) does not match the size and SHA-256 in the release feed; nothing was installed."
    }

    $staging = Join-Path $work 'staged'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $staging)

    # The staged copy applies itself, so a portable install can replace its own runtime.
    $stagedPython = Join-Path $staging 'runtime\python\python.exe'
    $python = if (Test-Path $stagedPython) { $stagedPython } else { (Get-Command python -ErrorAction Stop).Source }
    $result = & $python (Join-Path $staging 'scripts\release_update.py') apply --staging $staging --target $Dir
    if ($LASTEXITCODE -ne 0) { throw "Installing into $Dir failed; run the installer again." }
    $summary = $result | ConvertFrom-Json
    Write-Host "Installed $($summary.version): $($summary.copied) file(s) written, $($summary.removed) removed"
  } finally {
    if (Test-Path $work) { try { [IO.Directory]::Delete($work, $true) } catch { Write-Warning "Could not remove the temporary folder $work." } }
  }
}

Install-DraftEdge -Mode $Mode -Dir $Dir -Ref $Ref -Repo $Repo -Feed $Feed -NoPath:$NoPath
