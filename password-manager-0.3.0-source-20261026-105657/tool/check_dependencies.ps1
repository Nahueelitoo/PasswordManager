$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.lock') -Raw
$packages = @()
foreach ($block in [regex]::Matches($lock, '(?ms)^  (?<name>[a-zA-Z0-9_]+):\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_]+:|\z)')) {
  $body = $block.Groups['body'].Value
  if ($body -notmatch '(?m)^    source: hosted\s*$') { continue }
  $version = [regex]::Match($body, '(?m)^    version: "(?<version>[^"]+)"').Groups['version'].Value
  if (!$version) { throw 'Could not parse a hosted dependency version.' }
  $packages += [PSCustomObject]@{ name = $block.Groups['name'].Value; version = $version }
}
if ($packages.Count -eq 0) { throw 'No hosted packages found.' }
$queries = @($packages | ForEach-Object { @{ package = @{ name = $_.name; ecosystem = 'Pub' }; version = $_.version } })
$result = Invoke-RestMethod -Uri 'https://api.osv.dev/v1/querybatch' -Method Post -ContentType 'application/json' -Body (@{ queries = $queries } | ConvertTo-Json -Depth 8) -TimeoutSec 45
if ($result.results.Count -ne $packages.Count) { throw 'Incomplete OSV response.' }
$report = for ($i = 0; $i -lt $packages.Count; $i++) {
  $item = $result.results[$i]
  if ($item.next_page_token) { throw 'OSV response needs pagination; do not treat the scan as complete.' }
  [PSCustomObject]@{ name = $packages[$i].name; version = $packages[$i].version; vulnerabilities = @($item.vulns | ForEach-Object { $_.id } | Where-Object { $_ }) }
}
$output = Join-Path $projectRoot 'build/security-checks'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'osv-dependencies.json') -Encoding utf8
$findings = @($report | Where-Object { $_.vulnerabilities.Count -gt 0 })
Write-Output "Hosted packages checked against OSV: $($packages.Count)"
Write-Output "Packages with reported advisories: $($findings.Count)"
$findings | Format-Table name,version,@{Name='advisories';Expression={$_.vulnerabilities -join ', '}}
Write-Output 'This checks known advisories only, not the absence of vulnerabilities or the security of Flutter/Windows.'
