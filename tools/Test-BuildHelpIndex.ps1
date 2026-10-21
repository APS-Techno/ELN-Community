#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Generator = Join-Path $PSScriptRoot 'Build-HelpIndex.ps1'
$SourceHelp = Join-Path (Split-Path $PSScriptRoot -Parent) 'ELN.Desktop/Assets/Runtime/Help'
$Utf8 = [Text.UTF8Encoding]::new($false)
$Passed = 0
$Failed = 0
function Assert([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Operation, [string]$MessagePart) {
  $failure = $null
  try { & $Operation } catch { $failure = $_ }
  Assert ($null -ne $failure) "Expected rejection: $MessagePart"
  Assert ($failure.Exception.Message.Contains($MessagePart)) "Unexpected rejection: $($failure.Exception.Message)"
}
function Run-TestCase([string]$Name, [scriptblock]$Body) {
  $root = Join-Path ([IO.Path]::GetTempPath()) ('ELN-Help-Index-Test-' + [guid]::NewGuid())
  [void][IO.Directory]::CreateDirectory($root)
  try {
    & $Body $root
    $script:Passed++
    Write-Host "PASS $Name"
  } catch {
    $script:Failed++
    Write-Host "FAIL $Name : $($_.Exception.Message)"
  } finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
function Write-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n").Replace("`n", "`r`n"), $Utf8)
}
function New-HelpPage([string]$Root, [string]$File, [string]$Title, [string]$Body = '', [string]$Head) {
  if (-not $PSBoundParameters.ContainsKey('Head')) {
    $Head = "<link rel=`"stylesheet`" href=`"help.css`">`n<script src=`"help-index.js`" defer></script>`n<script src=`"help-search.js`" defer></script>`n<script src=`"help.js`" defer></script>"
  }
  Write-Text (Join-Path $Root $File) "<!doctype html>`n<html lang=`"en`">`n<head>`n<meta charset=`"utf-8`">`n<title>$Title</title>`n$Head`n</head>`n<body>`n<main>`n<h1>$Title</h1>`n$Body`n</main>`n</body>`n</html>`n"
}
function New-Manifest([string]$Root, [string[]]$Pages, [string[]]$Unlisted = @()) {
  $entries = @($Pages | ForEach-Object { [ordered]@{ file = $_; title = [IO.Path]::GetFileNameWithoutExtension($_) + ' page'; summary = "About $_" } })
  $manifest = [ordered]@{ product = 'Test Help'; home = 'Index.html'; groups = @([ordered]@{ id = 'main'; title = 'Main'; pages = $entries }) }
  if ($Unlisted.Count) { $manifest.unlisted = $Unlisted }
  Write-Text (Join-Path $Root 'help-toc.json') ($manifest | ConvertTo-Json -Depth 6)
}
function New-ValidFolder([string]$Root) {
  New-HelpPage $Root 'Index.html' 'Home' '<p>Start.</p>'
  New-HelpPage $Root 'A.html' 'Alpha' "<p>Intro &amp; more.<script>var hidden = 1;</script></p>`n<h2 id=`"one`">One</h2>`n<p>First <b>bold</b>.</p>`n<h3 id=`"one-a`">One A</h3>`n<p>Nested.</p>`n<h2 id=`"two`">Two</h2>`n<p>See <a href=`"B.html#three`">B</a>.</p>"
  Write-Text (Join-Path $Root 'help.css') 'body {}'
  New-HelpPage $Root 'B.html' 'Beta' "<p>Intro.</p>`n<h2 id=`"three`">Three</h2>`n<p>Back to <a href=`"A.html`">A</a> and <a href=`"#three`">here</a>.</p>"
  New-Manifest $Root @('A.html', 'B.html')
}
function Read-Index([string]$Path) {
  $text = [IO.File]::ReadAllText($Path)
  Assert $text.StartsWith('window.HELP_INDEX = ') 'Missing index prefix'
  $json = $text.Substring('window.HELP_INDEX = '.Length).TrimEnd()
  Assert $json.EndsWith(';') 'Missing final semicolon'
  return $json.Substring(0, $json.Length - 1) | ConvertFrom-Json
}
function Get-Problem([string]$Root) {
  try { & $Generator -HelpRoot $Root | Out-Null } catch { return $_.Exception.Message }
  return ''
}

Run-TestCase 'ValidFolderWritesIndex' {
  param($root)
  New-ValidFolder $root
  & $Generator -HelpRoot $root | Out-Null
  $index = Read-Index (Join-Path $root 'help-index.js')
  Assert ($index.product -eq 'Test Help') 'Wrong product'
  Assert (@($index.sections).Count -eq 6) "Wrong section count: $(@($index.sections).Count)"
  Assert (@($index.pages.'A.html'.sections).Count -eq 3) 'Wrong A page sections'
  Assert ($index.pages.'Index.html'.listed -eq $false) 'Home must not be listed'
  Assert (-not (@($index.sections) | Where-Object page -eq 'Index.html')) 'Home must not be searchable'
  $nested = @($index.sections) | Where-Object anchor -eq 'one-a'
  Assert (($nested.path -join '/') -eq 'A page/One/One A') "Wrong path: $($nested.path -join '/')"
}
Run-TestCase 'OutputIsDeterministic' {
  param($root)
  New-ValidFolder $root
  & $Generator -HelpRoot $root | Out-Null
  $first = (Get-FileHash -LiteralPath (Join-Path $root 'help-index.js')).Hash
  & $Generator -HelpRoot $root | Out-Null
  Assert ((Get-FileHash -LiteralPath (Join-Path $root 'help-index.js')).Hash -eq $first) 'Output changed between runs'
}
Run-TestCase 'SectionTextIsPlain' {
  param($root)
  New-ValidFolder $root
  & $Generator -HelpRoot $root | Out-Null
  $index = Read-Index (Join-Path $root 'help-index.js')
  $intro = @($index.sections) | Where-Object { $_.page -eq 'A.html' -and $_.anchor -eq '' }
  Assert ($intro.text -eq 'Intro & more.') "Wrong intro text: $($intro.text)"
  foreach ($section in @($index.sections)) { Assert (-not $section.text.Contains('<')) 'Tag left in text' }
}
Run-TestCase 'BrokenPageLinkFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p><a href="Missing.html">x</a></p>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Broken link in A.html: Missing.html'
  Assert (-not (Test-Path -LiteralPath (Join-Path $root 'help-index.js'))) 'Output written despite problems'
}
Run-TestCase 'BrokenAnchorFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p><a href="B.html#nope">x</a></p>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Broken anchor in A.html: B.html#nope'
}
Run-TestCase 'BrokenSamePageAnchorFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p><a href="#nope">x</a></p>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Broken anchor in A.html: #nope'
}
Run-TestCase 'ExternalLinksIgnored' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p><a href="https://example.org/x">a</a> <a href="mailto:x@example.org">b</a> <a href="eln://item/1">c</a></p>'
  & $Generator -HelpRoot $root | Out-Null
}
Run-TestCase 'DuplicateIdFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<h2 id="x">One</h2><p id="x">Two</p>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Duplicate id in A.html: x'
}
Run-TestCase 'PageNotInManifestFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'Orphan.html' 'Orphan'
  Assert-Throws { & $Generator -HelpRoot $root } 'Page not in help-toc.json: Orphan.html'
}
Run-TestCase 'ListedPageMissingFails' {
  param($root)
  New-ValidFolder $root
  New-Manifest $root @('A.html', 'B.html', 'Gone.html')
  Assert-Throws { & $Generator -HelpRoot $root } 'Listed page missing: Gone.html'
}
Run-TestCase 'PageListedTwiceFails' {
  param($root)
  New-ValidFolder $root
  New-Manifest $root @('A.html', 'B.html') @('A.html')
  Assert-Throws { & $Generator -HelpRoot $root } 'Page listed twice in help-toc.json: A.html'
}
Run-TestCase 'MissingHeadingIdFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<h2>No id here</h2>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Missing heading id in A.html: No id here (run -FixIds)'
}
Run-TestCase 'NonTemplatePageFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p>x</p>' '<style>body{}</style>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Page does not use the Help template: A.html'
}
Run-TestCase 'MainAndH1CountFails' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<h1>Second</h1>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Expected one <main> and one <h1>: A.html'
}
Run-TestCase 'ReportsAllProblemsAtOnce' {
  param($root)
  New-ValidFolder $root
  New-HelpPage $root 'A.html' 'Alpha' '<p><a href="M1.html">x</a><a href="M2.html">y</a></p>'
  $message = Get-Problem $root
  Assert ($message.Contains('2 problem(s)')) "Wrong count: $message"
  Assert ($message.Contains('Broken link in A.html: M1.html') -and $message.Contains('Broken link in A.html: M2.html')) "Missing lines: $message"
}
Run-TestCase 'UnlistedPageIsCheckedButNotSearchable' {
  param($root)
  New-ValidFolder $root
  New-Manifest $root @('A.html', 'B.html') @('Hidden.html')
  New-HelpPage $root 'Hidden.html' 'Hidden' '<p><a href="Missing.html">x</a></p>'
  Assert-Throws { & $Generator -HelpRoot $root } 'Broken link in Hidden.html: Missing.html'
  New-HelpPage $root 'Hidden.html' 'Hidden' '<h2 id="h">Secret</h2>'
  & $Generator -HelpRoot $root | Out-Null
  $index = Read-Index (Join-Path $root 'help-index.js')
  Assert ($index.pages.'Hidden.html'.listed -eq $false) 'Unlisted page marked listed'
  Assert (@($index.pages.'Hidden.html'.sections).Count -eq 1) 'Unlisted page lost its sections'
  Assert (-not (@($index.sections) | Where-Object page -eq 'Hidden.html')) 'Unlisted page is searchable'
  Assert (-not (@($index.groups.pages) -contains 'Hidden.html')) 'Unlisted page is in a group'
}
Run-TestCase 'FixIdsAddsSlugIds' {
  param($root)
  New-HelpPage $root 'A.html' 'Alpha' "<h2>Derived values &amp; sources</h2>`n<h3>Résumé</h3>`n<h2 class=`"x`">Classed</h2>"
  & $Generator -HelpRoot $root -FixIds | Out-Null
  $text = [IO.File]::ReadAllText((Join-Path $root 'A.html'))
  Assert $text.Contains('<h2 id="derived-values-sources">') 'Missing slug id'
  Assert $text.Contains('<h3 id="resume">') 'Accent not folded'
  Assert $text.Contains('<h2 class="x" id="classed">') 'Attributes not kept'
}
Run-TestCase 'FixIdsSuffixesDuplicateHeadings' {
  param($root)
  New-HelpPage $root 'A.html' 'Alpha' "<h2>See also</h2>`n<h3>See also</h3>"
  & $Generator -HelpRoot $root -FixIds | Out-Null
  $text = [IO.File]::ReadAllText((Join-Path $root 'A.html'))
  Assert ($text.Contains('<h2 id="see-also">') -and $text.Contains('<h3 id="see-also-2">')) 'Duplicate slugs not suffixed'
}
Run-TestCase 'FixIdsKeepsExistingIds' {
  param($root)
  New-HelpPage $root 'A.html' 'Alpha' "<h2 id=`"valuetypes`">Value types</h2>`n<h2>Valuetypes</h2>"
  & $Generator -HelpRoot $root -FixIds | Out-Null
  $text = [IO.File]::ReadAllText((Join-Path $root 'A.html'))
  Assert $text.Contains('<h2 id="valuetypes">Value types</h2>') 'Existing id changed'
  Assert $text.Contains('<h2 id="valuetypes-2">Valuetypes</h2>') 'New id collided with existing id'
}
Run-TestCase 'FixIdsPreservesBytes' {
  param($root)
  New-HelpPage $root 'A.html' 'Alpha' "<h2>One</h2>`n<p>Text — with dash</p>`n<h3 class=`"c`">Two</h3>"
  $before = [IO.File]::ReadAllBytes((Join-Path $root 'A.html'))
  & $Generator -HelpRoot $root -FixIds | Out-Null
  $after = [IO.File]::ReadAllBytes((Join-Path $root 'A.html'))
  Assert ($after[0] -ne 0xEF) 'BOM added'
  $stripped = [regex]::Replace($Utf8.GetString($after), ' id="(one|two)"', '')
  Assert ($stripped -eq $Utf8.GetString($before)) 'Bytes changed outside the inserted ids'
}
Run-TestCase 'FixIdsIsIdempotent' {
  param($root)
  New-HelpPage $root 'A.html' 'Alpha' '<h2>One</h2>'
  & $Generator -HelpRoot $root -FixIds | Out-Null
  $hash = (Get-FileHash -LiteralPath (Join-Path $root 'A.html')).Hash
  $output = & $Generator -HelpRoot $root -FixIds
  Assert (($output -join '') -eq 'Added 0 heading id(s).') "Unexpected output: $output"
  Assert ((Get-FileHash -LiteralPath (Join-Path $root 'A.html')).Hash -eq $hash) 'Second run changed the file'
}
Run-TestCase 'ManifestCaseMismatchFails' {
  param($root)
  New-ValidFolder $root
  New-Manifest $root @('a.html', 'B.html')
  Assert-Throws { & $Generator -HelpRoot $root } 'Listed page name case differs in help-toc.json: a.html (file A.html)'
}
Run-TestCase 'CommunityHelpPasses' {
  param($root)
  $out = Join-Path $root 'help-index.js'
  & $Generator -HelpRoot $SourceHelp -OutFile $out | Out-Null
  $index = Read-Index $out
  $manifest = Get-Content -LiteralPath (Join-Path $SourceHelp 'help-toc.json') -Raw | ConvertFrom-Json
  foreach ($page in @($manifest.groups.pages)) {
    Assert ($null -ne $index.pages.($page.file)) "Manifest page missing from index: $($page.file)"
  }
}
Write-Host "$Passed passed; $Failed failed"
if ($Failed) { exit 1 }
