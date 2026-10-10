# ELN Community Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execution method requires user selection before implementation.

**Goal:** Build a separate runnable Windows Community installer with an optional full scientific/synthetic CSV set or an empty CSV set.

**Architecture:** Community owns the installer, runtime stage, external runtime configuration, and synthetic demo CSVs. One Inno Setup task selects exactly one complete catalog set for `{app}/CSV`. Existing application catalog import remains unchanged.

**Tech Stack:** PowerShell 7, Inno Setup 6, Delphi 13 VCL, Win32, local SQLite, and the current Community viewer packages.

**Spec:** `../specs/2026-10-08-community-installer-design.md`.

## Global constraints

- Work in standalone `APS-ELN-Community`; preserve current unrelated work and keep `master` selected.
- Do not edit or update Commercial's pinned dependency, import Commercial payloads, commit, push, publish, sign, deploy, or install tools.
- Local installer verification may install and uninstall an owned test instance in a GUID-rooted temporary directory. Do not use the default install directory for tests.
- Product name is `ELN Community`. Keep the existing Community version, normalized to `2.0.0.0`; do not increase it.
- Per-user installer; no required elevation, service, trust change, credential change, settings reset, or association takeover.
- Desktop shortcut and demo data are off on a fresh installation. Retain the previous task choice on an upgrade; explicit user selection wins.
- Full catalogs contain current scientific definitions, four fictional instruments, and four matching action assignments. Neutral Community equipment source files remain empty.
- Empty catalogs contain all seven filenames, their real headers, and an empty logical row. No missing-file or full-data fallback.
- Installation selects CSV seeds for future notebooks. Installation and uninstall never open, migrate, repair, or delete existing notebooks, attachments, user configuration, or retained drafts.
- Keep the six-field build dependency schema. Add a separate ignored four-field installer runtime configuration.
- Generated output belongs under `_OUT/Installer/Win32/<Configuration>`. Source remains under `Installer` and `tools`.
- Preserve existing Delphi BOM and CRLF. Do not commit generated `.res`, binaries, licensed runtime files, or local configurations.
- Use configured external runtimes only. WebView2 Evergreen is a documented installed browser prerequisite; do not download or install it automatically.
- Win32 Debug has an observed missing Aurelius package prerequisite. Do not repeat that failure or weaken checks. Installer verification uses Win32 Release and reports the Debug limit.
- Risk tier is Full: external runtime packaging and data-preservation boundaries require an independent review.

## Review focus

1. Empty catalogs must not import their header as a record. Prove this with the real Community importer and an installed new notebook, not only a PowerShell parser.
2. Full-to-empty and empty-to-full installation transitions must select one complete CSV set. Prove imported data results and preserve a previously created synthetic notebook.
3. A bad runtime path or unsafe stage destination must not destroy an earlier complete stage. Keep deterministic staging failure tests.
4. Installed startup must not depend on Delphi/component directories in developer PATH. Smoke the packaged program with a reduced process-local PATH.
5. Community identity and notices must remain separate from Commercial. Review the stage manifest, installer identity, version metadata, and source-root rules before delivery.

## Task 1: Correct Community resource and version identity

**Files:**
- Modify `ELN.Community.Desktop/ELNCommunity.dpr`.
- Modify `ELN.Community.Desktop/ELNCommunity.dproj`.
- Update `THIRD-PARTY-NOTICES.md` after verification.

**Interfaces:**
- Consumes the current `CommunityDesktop` build target and project version `2.0`.
- Produces a Community EXE with its own generated project resource and consistent `2.0.0.0` version metadata.

- [ ] **Step 1: Record the failing version smoke.** Read the built EXE through `System.Diagnostics.FileVersionInfo`. Require `ProductName = 'ELN Community'`, `FileDescription = 'ELN Community Desktop'`, and equal numeric product/file versions `2.0.0.0`. The observed old EXE reports `ELabNotebook3` and `1.5.2.1548`.
- [ ] **Step 2: Link the generated Community resource.** Replace the legacy shared resource directive with `{$R *.res}`. Keep the existing project icon and per-monitor manifest settings.
- [ ] **Step 3: Set consistent generated version fields.** Set the project major/minor/release/build fields to `2/0/0/0` and matching product/file version strings. Keep the Community product description and original filename. Do not add a second version file.
- [ ] **Step 4: Build and repeat the version smoke.** Run `pwsh -NoProfile -File tools/build-community.ps1 -Target CommunityDesktop -Platform Win32 -Configuration Release`. Require exit zero and matching Community EXE metadata.
- [ ] **Step 5: Smoke the executable with an owned synthetic configuration.** Confirm that the actual Community window opens. Close only the process started for this check. Remove only its synthetic configuration and owned working directory.
- [ ] **Step 6: Update the resource notice.** Explain the Community generated resource and retained source icon without changing third-party grants or claiming redistribution clearance.

## Task 2: Implement Community runtime staging and CSV payloads

**Files:**
- Create `Installer/Stage-Runtime.ps1`.
- Create `Installer/Demo/Equipment.csv`.
- Create `Installer/Demo/ActionTypeEquipment.csv`.
- Create `tools/installer-runtime.example.psd1`.
- Create `Installer/Test-StageRuntime.ps1`.
- Modify `.gitignore` to exclude root `installer-runtime.local.psd1`.

**Interfaces:**
- Stage entry point:
  `Stage-Runtime.ps1 -RepoRoot <absolute directory> -Platform Win32 -Configuration <Debug|Release> -Destination <absolute directory> -DependencyConfig <absolute psd1> -RuntimeConfig <absolute psd1> [-ValidateOnly]`.
- Resolve host input from `_OUT/CommunityDesktop/Win32/<Configuration>` and viewer input from `_OUT/ViewerPackages/Win32/<Configuration>` under `RepoRoot`.
- Build dependencies retain the existing six required fields.
- Runtime configuration has required absolute `IsccPath`, `RuntimeBplRoot`, `SQLiteRuntime`, and `WebView2Runtime` fields.
- Produce `Program/` for application runtime/assets/notices, `Catalogs/Full/` for seven full CSVs, and `Catalogs/Empty/` for seven empty CSVs under the destination.
- `-ValidateOnly` checks source/configuration/runtime prerequisites without copying, replacing a stage, or requiring a completed build.

- [ ] **Step 1: Write deterministic staging safety tests before the stage exists.** Follow the existing plain PowerShell test style, with owned temporary fixtures and exception assertions. Do not require Pester or install a test tool.

  Required tests:
  - `MissingRuntimePreservesPreviousStage`: remove one required runtime input from a valid synthetic fixture, run real staging, require a failure naming that input, and confirm the earlier complete stage and sentinel bytes are unchanged.
  - `UnsafeDestinationPreservesSource`: attempt repository-root, source-tree, and ancestor destinations. Require rejection before mutation and unchanged source sentinel bytes.
  - `ValidateOnlyCreatesNoOutput`: run prerequisite validation against a complete fixture without compiled host/viewer output. Require success and no destination/output creation.
  - `EmptyCatalogTransformRemovesDataRows`: stage source catalogs that contain data. Parse the generated empty CSVs as data and require zero records. Check that all required files exist; the later native import smoke must also prove the Delphi empty-row contract.
  - `DemoReferencesResolve`: parse the actual full catalog set and require every demo type and action assignment to resolve. Require the four distinct approved model/action pairs, not an arbitrary non-empty or length check.

  Fixture files representing compiled inputs are synthetic test files only. Tests must exercise the real stage entry point. Do not add a production test mode or test-only helper to the stage.

  Test helper contracts: `New-StageFixture [-WithoutCompiledInput]` returns an owned fixture with `Arguments`, `RepoRoot`, `Destination`, `SQLiteRuntime`, `StageSentinel`, and `SourceSentinel`. `Run-TestCase` creates and cleans up that fixture around its script block. `Assert` fails for a false condition. `Assert-Throws` requires a real exception that contains the selected path or rejection reason. These helpers belong only in the test script.

  Concrete assertions:

  ```powershell
  Run-TestCase 'MissingRuntimePreservesPreviousStage' {
    param($f)
    $before = (Get-FileHash -LiteralPath $f.StageSentinel).Hash
    Remove-Item -LiteralPath $f.SQLiteRuntime
    $arguments = $f.Arguments
    Assert-Throws { & $StageScript @arguments } $f.SQLiteRuntime
    Assert ((Get-FileHash -LiteralPath $f.StageSentinel).Hash -eq $before) 'Previous stage changed'
  }
  Run-TestCase 'UnsafeDestinationPreservesSource' {
    param($f)
    $before = (Get-FileHash -LiteralPath $f.SourceSentinel).Hash
    foreach ($destination in @($f.RepoRoot, (Join-Path $f.RepoRoot 'ELN.Desktop'), (Split-Path $f.RepoRoot -Parent))) {
      $arguments = $f.Arguments.Clone()
      $arguments.Destination = $destination
      Assert-Throws { & $StageScript @arguments } 'Unsafe staging destination'
      Assert ((Get-FileHash -LiteralPath $f.SourceSentinel).Hash -eq $before) 'Source changed'
    }
  }
  Run-TestCase 'ValidateOnlyCreatesNoOutput' {
    param($f)
    $arguments = $f.Arguments
    & $StageScript @arguments -ValidateOnly
    Assert (-not (Test-Path -LiteralPath $f.Destination)) 'Validation created a stage'
  } -WithoutCompiledInput
  Run-TestCase 'EmptyCatalogTransformRemovesDataRows' {
    param($f)
    $arguments = $f.Arguments
    & $StageScript @arguments
    foreach ($name in $CatalogNames) {
      $path = Join-Path $f.Destination \"Catalogs/Empty/$name\"
      Assert (Test-Path -LiteralPath $path -PathType Leaf) \"Missing catalog: $name\"
      Assert (@(Import-Csv -LiteralPath $path).Count -eq 0) \"Empty catalog contains data: $name\"
    }
  }
  Run-TestCase 'DemoReferencesResolve' {
    param($f)
    $arguments = $f.Arguments
    & $StageScript @arguments
    $full = Join-Path $f.Destination 'Catalogs/Full'
    $equipment = @(Import-Csv -LiteralPath (Join-Path $full 'Equipment.csv'))
    $types = @(Import-Csv -LiteralPath (Join-Path $full 'EquipmentTypes.csv'))
    $actions = @(Import-Csv -LiteralPath (Join-Path $full 'ActionTypes.csv'))
    $links = @(Import-Csv -LiteralPath (Join-Path $full 'ActionTypeEquipment.csv'))
    foreach ($instrument in $equipment) {
      Assert ($types.Type -contains $instrument.EquipmentType) 'Unknown demo equipment type'
    }
    foreach ($link in $links) {
      Assert ($equipment.Model -contains $link.Equipment) 'Unknown assigned demo instrument'
      Assert ($actions.Title -contains $link.ActionType) 'Unknown assigned demo action'
    }
    $pairs = @($links | ForEach-Object { \"$($_.Equipment)/$($_.ActionType)\" })
    $expected = @('Demo Furnace/Annealing', 'Demo Diffractometer/XRD', 'Demo Balance/Mass', 'Demo Deposition System/Deposition')
    Assert (@(Compare-Object $expected $pairs).Count -eq 0) 'Demo assignments differ from the approved set'
  }
  ```

- [ ] **Step 2: Run the tests and observe failure because staging is absent.** Run `pwsh -NoProfile -File Installer/Test-StageRuntime.ps1`. Preserve this failing-before evidence.
- [ ] **Step 3: Define the runtime configuration example.** Document the four absolute fields and filename requirements. Do not copy runtime binaries into source or create a local configuration automatically.
- [ ] **Step 4: Add the approved demo data.** Use these exact model/type/action pairs: `Demo Furnace/Furnace/Annealing`, `Demo Diffractometer/Diffractometer/XRD`, `Demo Balance/Balance/Mass`, and `Demo Deposition System/Deposition System/Deposition`. Use `Fictional Demo Instruments` and `Synthetic demo lab`; leave booking and information URLs empty. Mark every description as synthetic. Keep neutral equipment and assignment source CSVs unchanged.
- [ ] **Step 5: Collect and validate the stage inputs before writes.** Select only the Community EXE, matching Core packages, seven selected viewer BPLs, current assets, notices, and exact external runtime filenames. Reuse the existing Community viewer identities and external runtime conventions. Never copy an entire external BPL directory or read Commercial source/output as a package input.
- [ ] **Step 6: Implement destination safety and stage replacement.** Normalize absolute paths and reject unsafe source/ancestor/repository destinations and reparse-point escapes. Build a complete temporary sibling stage, then replace the generated destination with recoverable directory moves. If validation or copying fails, retain the prior complete stage. Remove only the stage's own temporary and backup paths after success.
- [ ] **Step 7: Generate full and empty catalogs.** Full uses five unchanged scientific catalogs plus the two synthetic demo catalogs. Empty takes each real source header and writes UTF-8 without BOM with `header + CRLF + CRLF`; do not trim the empty logical row. Keep both complete sets outside `Program/CSV` for installer selection.
- [ ] **Step 8: Run staging tests.** Require all tests to pass. Confirm that invalid inputs do not produce a partial published stage.
- [ ] **Step 9: Stage real Win32 Release inputs.** Use the current configured Community host/viewer builds and approved external runtimes. Require the exact manifest to validate. Missing real prerequisites must be reported; do not fill them from private or archived output.

## Task 3: Implement the installer and build entry point

**Files:**
- Create `Installer/ELNCommunitySetup.iss`.
- Create `tools/build-installer.ps1`.
- Update `README.md` after smoke verification.

**Interfaces:**
- Build entry point:
  `build-installer.ps1 [-Platform Win32] [-Configuration <Debug|Release>] [-DependencyConfig <absolute psd1>] [-RuntimeConfig <absolute psd1>] [-ValidateOnly]`.
- Default installer configuration is Release; existing developer helper defaults do not change.
- Default build configuration file remains root `build-dependencies.local.psd1`. Default runtime configuration file is root `installer-runtime.local.psd1`.
- Consume the stage contract from Task 2 and the real EXE metadata from Task 1.
- Invoke Inno Setup with explicit stage and version defines.
- Produce `_OUT/Installer/Win32/<Configuration>/Output/ELNCommunitySetup-<version>.exe` and a captured build log.

- [ ] **Step 1: Define the installer contract smoke before implementation.** The compiler command must fail until the `.iss` and complete stage exist. The eventual real installer must expose task `demodata`, start unchecked, and produce full or empty catalogs based on that task. Do not add permanent source-text assertions for Inno sections.
- [ ] **Step 2: Add stable Community-only identity.** Record one new AppId GUID in source. Use `ELN Community`, a per-user `{localappdata}/Programs/ELN Community` directory, and Community-only shortcuts/uninstall identity. Use the current source icon and Apache license. Require no elevation and no settings reset, service, trust registration, update feed, or file association.
- [ ] **Step 3: Add the task choices.** `desktopicon` and `demodata` are unchecked on first installation. Retain previous task choices on upgrades. Full CSV file entries apply to `demodata`; empty CSV file entries apply to `not demodata`. Both entries target the same seven filenames under `{app}/CSV`. Do not delete unrelated files or import a database in installer code.
- [ ] **Step 4: Add program files and uninstall behavior.** Install only `Program/` contents and the selected catalogs. Uninstall removes only installer-owned program files and shortcuts. Do not add uninstall-delete rules for notebooks, attachment paths, local preferences, or temporary working roots. Interactive launch is optional; silent installation never launches the app.
- [ ] **Step 5: Implement the build entry point.** Resolve paths from its Community root. Check explicit dependencies, runtime configuration, and Win32 prerequisite files before compilation. `-ValidateOnly` returns without generated output or compilation. Otherwise build `CommunityDesktop` and `ViewerPackages` sequentially through the existing helper with one configuration.
- [ ] **Step 6: Enforce Community version identity.** Read the built EXE through `FileVersionInfo`. Reject non-Community product metadata, nonnumeric/missing versions, or unequal product/file versions. Pass this version to Inno Setup; never read Commercial `VERSION.txt`.
- [ ] **Step 7: Stage and compile locally.** Invoke `Installer/Stage-Runtime.ps1` with explicit paths, then the configured Inno compiler. Capture complete output and nonzero exits. Do not deploy, publish, download, or install prerequisites.
- [ ] **Step 8: Run a real installer build.** Run `pwsh -NoProfile -File tools/build-installer.ps1 -Platform Win32 -Configuration Release` with configured local dependencies. Require exit zero and the named installer artifact. Inspect its version metadata.
- [ ] **Step 9: Inspect the actual installer UI.** Launch the produced installer to its task page, observe the unchecked demo task, and cancel this inspection before writes. Capture visual proof. Do not inspect another session's installer or close its processes.

## Task 4: Verify installed full/empty behavior, transitions, and ownership

**Files:**
- Temporary scripts and fixtures under owned generated/temp directories only; remove them after evidence is captured.
- Update `README.md` and `THIRD-PARTY-NOTICES.md` with exercised build and runtime contracts.

**Interfaces:**
- Consume the real installer artifact from Task 3.
- Explicit full installation uses task `demodata`; explicit empty installation deselects `demodata`.
- Test installs use an owned GUID directory, explicit installer logs, no desktop/start-menu shortcuts, no automatic app launch, and no restart.
- GUI smoke uses explicit synthetic `--config`, `--plugins`, notebook, and storage paths. Never load a user's saved configuration or notebook.

- [ ] **Step 1: Test full installation.** Install into the owned test directory with the demo task selected. Require installer exit zero and one complete full catalog set under `CSV`. Launch the installed EXE with a reduced process-local PATH that excludes Delphi and installed component directories. Observe the actual main window.
- [ ] **Step 2: Create a full-mode notebook through the actual UI.** Select a new SQLite path, a separate empty attachment directory, and a synthetic local identity. Require creation without an import error. Close with the application's normal retained-draft notice. Check the owned fixture through the real model or its synthetic SQLite data: four demo instruments, four assignments, and the expected scientific definitions. Reopen the fixture and require normal startup.
- [ ] **Step 3: Test full-to-empty transition and preservation.** Close only the owned test host. Save hashes of its notebook and an owned attachment. Reinstall the same owned test location with demo data explicitly deselected. Require all seven empty catalogs and unchanged prior notebook/attachment hashes. Do not open the old notebook during installation.
- [ ] **Step 4: Create an empty-mode notebook through the actual UI.** Use another owned SQLite path and empty attachment directory. Require no catalog/import error. Verify zero CSV-driven catalog rows, including no imported header records. Built-in identity/link-type initialization is allowed. Reopen the fixture and require normal startup.
- [ ] **Step 5: Test empty-to-full transition.** Reinstall the owned test location with `demodata` selected. Verify the full data choice through a new synthetic notebook. Prior full and empty notebooks and attachments must retain their captured bytes.
- [ ] **Step 6: Test uninstall boundaries.** Uninstall the owned test instance. Require its program files and uninstall entry to be removed. Require the synthetic notebooks, attachment files, external synthetic configuration, and owned retained working directories to survive. Remove those surviving fixtures only as separate test cleanup, after the preservation assertions.
- [ ] **Step 7: Run permanent stage regressions and relevant notebook regressions.** Run `Installer/Test-StageRuntime.ps1` and the Community `NotebookTests` target in Win32 Release through the supported helper. Read complete results and report any failure by name. Do not rerun the earlier successful private full suite for this Community-only change.
- [ ] **Step 8: Request independent review.** Use a fresh reviewer for the final source changes. Require review of source isolation, external runtime selection, unsafe stage destinations, Inno task precedence, version identity, and data-preservation behavior. Fix critical and important findings before delivery; rerun only affected verification after fixes.
- [ ] **Step 9: Update the product documentation.** Document the exact local build command, separate runtime configuration, installer output path, initial unchecked task, full scientific/synthetic data, empty CSV mode, existing-notebook boundary, and WebView2 browser prerequisite. Keep runtime redistribution and missing shared-policy limits explicit.
- [ ] **Step 10: Clean up and deliver evidence.** Remove only owned temporary scripts, test installs, and fixtures after their assertions. Keep the installer artifact and verification logs under `_OUT`. Report the artifact path, exercised full/empty creation and transition results, installed-runtime startup result, regression results, review outcome, and any remaining prerequisites. Do not claim official publication or alter Commercial's pin.

## Integration boundary

There is no authorized Git commit, branch change, tag, push, Commercial pin update, publication, or production installation in this plan. Preserve unrelated files and the earlier warning/catalog fixes. Leave the implemented source changes available for a separately authorized commit after verification.
