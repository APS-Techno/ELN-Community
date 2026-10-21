#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$HelpRoot,
  [string]$OutFile,
  [switch]$FixIds
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$HelpRoot = [IO.Path]::GetFullPath($HelpRoot)
if (-not (Test-Path -LiteralPath $HelpRoot -PathType Container)) { throw "Help folder not found: $HelpRoot" }
if (-not $OutFile) { $OutFile = Join-Path $HelpRoot 'help-index.js' }

$HeadingPattern = [regex]'(?is)<h([1-3])(\s[^>]*)?>(.*?)</h\1\s*>'
$IdPattern = [regex]'(?i)\sid="([^"]*)"'
$HrefPattern = [regex]'(?i)\shref="([^"]*)"'

function ConvertTo-PlainText([string]$Html) {
  $text = [regex]::Replace($Html, '(?is)<(script|style)\b.*?</\1\s*>', ' ')
  $text = [regex]::Replace($text, '(?s)<[^>]*>', ' ')
  $text = [System.Net.WebUtility]::HtmlDecode($text)
  return [regex]::Replace($text, '\s+', ' ').Trim()
}
function ConvertTo-HelpSlug([string]$Text, [Collections.Generic.HashSet[string]]$Used) {
  $folded = (ConvertTo-PlainText $Text).Normalize([Text.NormalizationForm]::FormD)
  $builder = [Text.StringBuilder]::new()
  foreach ($ch in $folded.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($ch) }
  }
  $slug = [regex]::Replace($builder.ToString().ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
  if (-not $slug) { $slug = 'section' }
  $candidate = $slug
  $n = 2
  while ($Used.Contains($candidate)) { $candidate = "$slug-$n"; $n++ }
  [void]$Used.Add($candidate)
  return $candidate
}
function Get-HeadingId($Match) {
  $attributes = $Match.Groups[2].Value
  $id = $IdPattern.Match($attributes)
  if ($id.Success) { return $id.Groups[1].Value }
  return $null
}
function Get-HelpPages {
  return @(Get-ChildItem -LiteralPath $HelpRoot -Filter '*.html' -File | Sort-Object Name)
}

if ($FixIds) {
  $added = 0
  foreach ($file in Get-HelpPages) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $encoding = [Text.UTF8Encoding]::new($hasBom)
    $text = [IO.File]::ReadAllText($file.FullName, $encoding)
    $used = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($m in $IdPattern.Matches($text)) { [void]$used.Add($m.Groups[1].Value) }
    $inserts = [Collections.Generic.List[object]]::new()
    foreach ($m in $HeadingPattern.Matches($text)) {
      if ($m.Groups[1].Value -eq '1' -or $null -ne (Get-HeadingId $m)) { continue }
      $slug = ConvertTo-HelpSlug $m.Groups[3].Value $used
      $position = $m.Index + 3 + $m.Groups[2].Length
      $inserts.Add([pscustomobject]@{ Position = $position; Text = " id=`"$slug`"" })
    }
    if ($inserts.Count -eq 0) { continue }
    for ($i = $inserts.Count - 1; $i -ge 0; $i--) { $text = $text.Insert($inserts[$i].Position, $inserts[$i].Text) }
    [IO.File]::WriteAllText($file.FullName, $text, $encoding)
    $added += $inserts.Count
  }
  Write-Output "Added $added heading id(s)."
  return
}

$problems = [Collections.Generic.List[string]]::new()
$manifestPath = Join-Path $HelpRoot 'help-toc.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Help check failed with 1 problem(s):`nManifest missing: help-toc.json" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable

$entries = [Collections.Generic.List[object]]::new()
$entries.Add([pscustomobject]@{ File = [string]$manifest['home']; Group = ''; Listed = $false; Meta = @{} })
foreach ($group in @($manifest['groups'])) {
  foreach ($page in @($group['pages'])) { $entries.Add([pscustomobject]@{ File = [string]$page['file']; Group = [string]$group['id']; Listed = $true; Meta = $page }) }
}
if ($manifest.ContainsKey('unlisted')) {
  foreach ($file in @($manifest['unlisted'])) { $entries.Add([pscustomobject]@{ File = [string]$file; Group = ''; Listed = $false; Meta = @{} }) }
}
$known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$uniqueEntries = [Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
  if (-not $known.Add($entry.File)) { $problems.Add("Page listed twice in help-toc.json: $($entry.File)"); continue }
  $actual = Get-ChildItem -LiteralPath $HelpRoot -File | Where-Object { $_.Name -ieq $entry.File } | Select-Object -First 1
  if ($null -eq $actual) { $problems.Add("Listed page missing: $($entry.File)"); continue }
  if ($actual.Name -cne $entry.File) { $problems.Add("Listed page name case differs in help-toc.json: $($entry.File) (file $($actual.Name))"); continue }
  $uniqueEntries.Add($entry)
}

$parsed = @{}
foreach ($file in Get-HelpPages) {
  $text = [IO.File]::ReadAllText($file.FullName)
  $ids = @($IdPattern.Matches($text) | ForEach-Object { $_.Groups[1].Value })
  $parsed[$file.Name.ToLowerInvariant()] = [pscustomobject]@{ Name = $file.Name; Text = $text; Ids = [Collections.Generic.HashSet[string]]::new([string[]]$ids, [StringComparer]::Ordinal); IdList = $ids }
}

foreach ($page in $parsed.Values | Sort-Object Name) {
  $name = $page.Name
  $text = $page.Text
  if (-not $known.Contains($name)) { $problems.Add("Page not in help-toc.json: $name") }
  $head = [regex]::Match($text, '(?is)<head\b.*?</head>').Value
  foreach ($required in @('href="help.css"', 'src="help-index.js"', 'src="help-search.js"', 'src="help.js"')) {
    if (-not $head.Contains($required)) { $problems.Add("Page does not use the Help template: $name"); break }
  }
  $mains = [regex]::Matches($text, '(?is)<main\b[^>]*>(.*?)</main\s*>')
  $page | Add-Member -NotePropertyName Main -NotePropertyValue $null
  if ($mains.Count -ne 1 -or [regex]::Matches($text, '(?i)<main\b').Count -ne 1 -or [regex]::Matches($mains[0].Groups[1].Value, '(?i)<h1\b').Count -ne 1 -or [regex]::Matches($text, '(?i)<h1\b').Count -ne 1) {
    $problems.Add("Expected one <main> and one <h1>: $name")
  } else {
    $page.Main = $mains[0].Groups[1].Value
  }
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $reported = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($id in $page.IdList) {
    if (-not $seen.Add($id) -and $reported.Add($id)) { $problems.Add("Duplicate id in ${name}: $id") }
  }
  foreach ($m in $HeadingPattern.Matches($text)) {
    if ($m.Groups[1].Value -ne '1' -and $null -eq (Get-HeadingId $m)) {
      $problems.Add("Missing heading id in ${name}: $(ConvertTo-PlainText $m.Groups[3].Value) (run -FixIds)")
    }
  }
  foreach ($m in $HrefPattern.Matches($text)) {
    $href = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
    if (-not $href -or $href -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { continue }
    $hash = $href.IndexOf('#')
    $target = if ($hash -ge 0) { $href.Substring(0, $hash) } else { $href }
    $anchor = if ($hash -ge 0) { $href.Substring($hash + 1) } else { '' }
    $query = $target.IndexOf('?')
    if ($query -ge 0) { $target = $target.Substring(0, $query) }
    $target = [Uri]::UnescapeDataString($target)
    $targetPage = $page
    if ($target) {
      if (-not (Test-Path -LiteralPath (Join-Path $HelpRoot $target))) { $problems.Add("Broken link in ${name}: $href"); continue }
      $targetPage = $parsed[$target.ToLowerInvariant()]
    }
    if ($anchor -and $null -ne $targetPage -and -not $targetPage.Ids.Contains([Uri]::UnescapeDataString($anchor))) {
      $problems.Add("Broken anchor in ${name}: $href")
    }
  }
}

if ($problems.Count -gt 0) {
  throw "Help check failed with $($problems.Count) problem(s):`n" + ($problems -join "`n")
}

function Get-PageSections($Page, [string]$PageTitle, [string[]]$Keywords) {
  $main = $Page.Main
  $headings = @($HeadingPattern.Matches($main))
  $h1 = $headings | Where-Object { $_.Groups[1].Value -eq '1' } | Select-Object -First 1
  $subs = @($headings | Where-Object { $_.Groups[1].Value -ne '1' })
  $records = [Collections.Generic.List[object]]::new()
  $start = $h1.Index + $h1.Length
  $end = if ($subs.Count) { $subs[0].Index } else { $main.Length }
  $records.Add([ordered]@{ page = $Page.Name; anchor = ''; title = $PageTitle; level = 1; path = @($PageTitle); text = (ConvertTo-PlainText $main.Substring($start, $end - $start)); keywords = @($Keywords) })
  $currentH2 = $null
  for ($i = 0; $i -lt $subs.Count; $i++) {
    $m = $subs[$i]
    $level = [int]$m.Groups[1].Value
    $title = ConvertTo-PlainText $m.Groups[3].Value
    $bodyStart = $m.Index + $m.Length
    $bodyEnd = if ($i + 1 -lt $subs.Count) { $subs[$i + 1].Index } else { $main.Length }
    if ($level -eq 2) { $currentH2 = $title; $path = @($PageTitle, $title) }
    elseif ($currentH2) { $path = @($PageTitle, $currentH2, $title) }
    else { $path = @($PageTitle, $title) }
    $records.Add([ordered]@{ page = $Page.Name; anchor = (Get-HeadingId $m); title = $title; level = $level; path = $path; text = (ConvertTo-PlainText $main.Substring($bodyStart, $bodyEnd - $bodyStart)); keywords = @() })
  }
  return $records
}

$pages = [ordered]@{}
$sections = [Collections.Generic.List[object]]::new()
foreach ($entry in $uniqueEntries) {
  $page = $parsed[$entry.File.ToLowerInvariant()]
  $meta = $entry.Meta
  $h1 = $HeadingPattern.Matches($page.Main) | Where-Object { $_.Groups[1].Value -eq '1' } | Select-Object -First 1
  $title = if ($meta.ContainsKey('title')) { [string]$meta['title'] } else { ConvertTo-PlainText $h1.Groups[3].Value }
  $keywords = if ($meta.ContainsKey('keywords')) { [string[]]@($meta['keywords']) } else { [string[]]@() }
  $records = Get-PageSections $page $title $keywords
  $pages[$page.Name] = [ordered]@{
    title = $title
    summary = if ($meta.ContainsKey('summary')) { [string]$meta['summary'] } else { '' }
    icon = if ($meta.ContainsKey('icon')) { [string]$meta['icon'] } else { '' }
    group = $entry.Group
    listed = $entry.Listed
    sections = @($records | Where-Object { $_.level -gt 1 } | ForEach-Object { [ordered]@{ anchor = $_.anchor; title = $_.title; level = $_.level } })
  }
  if ($entry.Listed) { foreach ($record in $records) { $sections.Add($record) } }
}
$groups = @(foreach ($group in @($manifest['groups'])) {
  [ordered]@{ id = [string]$group['id']; title = [string]$group['title']; pages = @(@($group['pages']) | ForEach-Object { [string]$_['file'] }) }
})
$index = [ordered]@{
  product = [string]$manifest['product']
  home = [string]$manifest['home']
  groups = $groups
  pages = $pages
  sections = $sections.ToArray()
}
$json = ConvertTo-Json -InputObject $index -Depth 10 -Compress
[IO.File]::WriteAllText($OutFile, "window.HELP_INDEX = $json;`r`n", [Text.UTF8Encoding]::new($false))
Write-Output "Help index written: $OutFile ($($sections.Count) sections)"
