param([string]$Version = '0.3.0')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$artifactName = "password-manager-$Version-source-$stamp"
$dist = Join-Path $projectRoot 'dist'
$stage = Join-Path $dist $artifactName
if (Test-Path -LiteralPath $stage) { throw 'The output already exists. Retry with a new timestamp.' }
New-Item -ItemType Directory -Path $stage | Out-Null
$top = @('.gitignore', '.metadata', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock', 'LICENSE', 'README.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md')
$files = @($top | ForEach-Object { Get-Item -LiteralPath (Join-Path $projectRoot $_) })
foreach ($folder in @('lib', 'test', 'tool', 'windows', 'docs')) {
  $files += Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/]ephemeral[\\/]|[\\/]\.git[\\/]|[\\/]\.vs[\\/]|[\\/]x64[\\/]|[\\/]x86[\\/]' }
}
$extensions = @('.dart', '.cpp', '.cc', '.h', '.rc', '.manifest', '.ico', '.txt', '.cmake', '.ps1', '.py', '.md', '.yaml', '.lock')
$secretPatterns = @('AIza[0-9A-Za-z_-]{30,}', 'gh[pousr]_[0-9A-Za-z]{20,}', 'github_pat_[0-9A-Za-z_]{20,}', '-----BEGIN [A-Z ]*PRIVATE KEY-----', '(?i)[A-Z]:[\\/]Users[\\/]', '[A-Za-z0-9._%+-]+@gmail\.com')
$manifest = @()
foreach ($file in $files) {
  if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Symlink refused: $($file.Name)" }
  $relative = $file.FullName.Substring($projectRoot.TrimEnd('\').Length + 1)
  if ($relative.StartsWith('..') -or $relative -match '(?i)\.(kdbx|bak|pending|pem|key|pfx|p12|dmp)(\.|$)|\.(exe|dll|pdb|zip)$|(^|[\\/])\.env') {
    throw "Excluded file found in source selection: $relative"
  }
  if ($relative -notin $top -and $file.Name -notin @('.gitignore', 'CMakeLists.txt') -and $file.Extension -notin $extensions) {
    throw "Unexpected file type: $relative"
  }
  if ($file.Extension -ne '.ico') {
    $content = [IO.File]::ReadAllText($file.FullName)
    foreach ($pattern in $secretPatterns) {
      if ($content -match $pattern) { throw "Potential private data in $relative; review before packaging." }
    }
  }
  $target = Join-Path $stage $relative
  New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $target
  $manifest += [PSCustomObject]@{ path = $relative.Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifest | Sort-Object path | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'SOURCE_MANIFEST.json') -Encoding utf8
$zip = Join-Path $dist "$artifactName.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
  if ($archive.Entries.FullName -match '(?i)\.(kdbx|bak|pending|pem|pfx|p12)(\.|$)|\.(exe|dll|pdb)$') { throw 'Archive contains an excluded file.' }
  if ('.gitignore' -notin $archive.Entries.FullName) { throw 'Archive is missing .gitignore.' }
} finally { $archive.Dispose() }
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
Write-Output "Source files selected and scanned: $($files.Count)"
Write-Output "Source folder: $stage"
Write-Output "Source ZIP: $zip"
Write-Output 'No upload performed. Scan is heuristic; inspect the staged source and screenshots before publication.'


