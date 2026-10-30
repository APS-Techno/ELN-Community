param(
  [Parameter(Mandatory)][string]$Executable,
  [string[]]$Library = @(),
  [string[]]$Arguments = @(),
  [hashtable]$Environment = @{},
  [hashtable]$PathEnvironment = @{},
  [string]$Distro = 'Ubuntu-22.04',
  [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$executablePath = [IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw "Executable missing: $executablePath" }
$header = [byte[]]::new(20)
$stream = [IO.File]::OpenRead($executablePath)
try { $read = $stream.Read($header, 0, $header.Length) } finally { $stream.Dispose() }
if ($read -lt 20 -or $header[0] -ne 0x7F -or $header[1] -ne 0x45 -or $header[2] -ne 0x4C -or $header[3] -ne 0x46 -or
    $header[4] -ne 2 -or [BitConverter]::ToUInt16($header, 18) -ne 0x3E) {
  throw "Not a Linux x86-64 ELF executable: $executablePath"
}

$env:WSL_UTF8 = '1'
$installed = @(& wsl.exe --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Distro -notin $installed) { throw "WSL distribution $Distro is not installed. README section 'Linux64' lists the setup." }

function Invoke-Wsl([string[]]$Command) {
  & wsl.exe --distribution $Distro --exec @Command
  if ($LASTEXITCODE -ne 0) { throw "WSL command failed with exit code ${LASTEXITCODE}: $($Command -join ' ')" }
}

function ConvertTo-WslPath([string]$Path) {
  $converted = & wsl.exe --distribution $Distro --exec wslpath -a -u $Path
  if ($LASTEXITCODE -ne 0 -or -not $converted) { throw "wslpath cannot convert $Path" }
  return ([string]$converted).Trim()
}

$sources = @($executablePath)
foreach ($entry in $Library) {
  $path = [IO.Path]::GetFullPath($entry)
  if (Test-Path -LiteralPath $path -PathType Container) {
    $sources += @(Get-ChildItem -LiteralPath $path -File |
      Where-Object { $_.Name -match '\.so(\.\d+)*$' } | ForEach-Object { $_.FullName })
  }
  elseif (Test-Path -LiteralPath $path -PathType Leaf) { $sources += $path }
  else { throw "Library missing: $path" }
}

$runDirectory = "/tmp/eln-linux-tests/$([guid]::NewGuid().ToString('N'))"
$program = Split-Path $executablePath -Leaf
Invoke-Wsl @('mkdir', '-p', $runDirectory)
$runError = $null
try {
  Invoke-Wsl (@('cp', '--') + @($sources | ForEach-Object { ConvertTo-WslPath $_ }) + @($runDirectory))
  Invoke-Wsl @('chmod', '+x', "$runDirectory/$program")
  $variables = @("LD_LIBRARY_PATH=$runDirectory") + @($Environment.GetEnumerator() |
    Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) + @($PathEnvironment.GetEnumerator() |
    Sort-Object Key | ForEach-Object { "$($_.Key)=$(ConvertTo-WslPath ([IO.Path]::GetFullPath($_.Value)))" })
  Write-Host "run $program in ${Distro}:$runDirectory"
  & wsl.exe --distribution $Distro --cd $runDirectory --exec env @variables "./$program" @Arguments
  $exitCode = $LASTEXITCODE
  Write-Host "$program exit code $exitCode"
}
catch { $runError = $_ }
if ($Keep) { Write-Host "kept ${Distro}:$runDirectory" }
else {
  try { Invoke-Wsl @('rm', '-rf', '--', $runDirectory) }
  catch {
    if ($runError) { Write-Warning "Cleanup of ${Distro}:$runDirectory also failed: $($_.Exception.Message)" }
    else { throw "Cleanup of ${Distro}:$runDirectory failed after $program exited with code ${exitCode}: $($_.Exception.Message)" }
  }
}
if ($runError) { throw $runError }
exit $exitCode
