# ELN Community installer design

## Purpose and agreed requirements

Build a separate Windows installer for ELN Community. Add an install-time choice between full CSV catalogs and empty CSV catalogs. The user selected full scientific definitions plus synthetic demo equipment and matching action assignments. The user approved one installer with a demo checkbox that is off by default.

The installer must produce a runnable local Community application. It must not install Commercial hosts, team policy, licensing, private equipment inventory, services, or client trust settings. It must not change existing notebooks or attachment directories.

This design requires review before implementation. It does not authorize a commit, push, publication, or production deployment.

## Current evidence

- Community has no installer project or packaging pipeline.
- Commercial uses Inno Setup 6, separate runtime staging, explicit external runtime paths, and generated output under `_OUT`.
- Community has supported build targets for `CommunityDesktop` and `ViewerPackages`.
- Community runtime assets include seven CSV catalogs, scientific templates, icons, Help, Markdown assets, and protocol viewer templates.
- New Notebook scans all seven CSV filenames before it creates notebook bytes. Missing catalogs stop creation.
- The CSV importer needs a header and one empty logical row for an empty catalog. A header-only file can be treated as data.
- Neutral Community equipment and action-to-equipment source catalogs are empty. They must remain empty.
- The Community project declares product and file version `2.0`. The current EXE links the shared legacy resource and reports `1.5.2.1548` with `ELabNotebook3` product metadata.
- Win32 Release builds and synthetic notebook creation were exercised. Win32 Debug is blocked by missing installed Aurelius Debug packages. This installer must not work around that gap with alternate source roots or global tool settings.

## Selected approach

Use one Inno Setup installer with two alternative CSV payloads. The installer copies the selected payload to `{app}/CSV`. The application keeps its current catalog import path.

This is simpler than two installer editions or a new runtime data-selection setting. It also keeps the application independent of Inno Setup task state.

All installer source and synthetic demo source belong in standalone Community. Commercial source and generated output are not package inputs. Do not edit or update Commercial's Community pin for this feature.

## Product and installation identity

- Display name: `ELN Community`.
- Main executable: `ELNCommunity.exe`.
- Stable AppId: a new Community-only GUID, recorded in the installer source.
- Default install location: `{localappdata}/Programs/ELN Community`.
- Installation privilege: per-user, without required elevation.
- Start menu group: `ELN Community`.
- Desktop shortcut: optional and off by default.
- Uninstall entry and icon: Community-only.
- No Commercial update URL, credential deletion, settings reset, file association takeover, MCP registration, or Windows service.
- Do not launch the application during silent installation. Interactive installation may offer launch after completion.

Uninstall removes installer-owned program files and shortcuts. It must not remove notebooks, attachment directories, user configuration, or retained editor drafts.

## Version and application resource

Use the existing Community version `2.0`, represented as `2.0.0.0` where a four-part version is required. Do not increase the product version or build number.

Change the Community executable to link its own generated project resource instead of `ELN.Desktop/ELabNotebook3.res`. Keep the current Community icon and manifest configuration. Ensure that generated fixed version fields and string metadata agree:

- ProductName: `ELN Community`.
- FileDescription: `ELN Community Desktop`.
- OriginalFilename: `ELNCommunity.exe`.
- ProductVersion and FileVersion: `2.0.0.0`.

Derive the installer version from the built Community executable. Do not introduce a second version file or read Commercial `VERSION.txt`. Fail packaging if Community product metadata or version is missing or inconsistent.

## Runtime payload

Build `CommunityDesktop` and `ViewerPackages` sequentially with the same Win32 configuration. Installer builds default to Release. Existing developer build defaults stay unchanged.

The program payload contains:

- Community Desktop EXE.
- Matching Core and Core.Protocol BPLs at the application root.
- The seven selected Community add-on BPLs under `Plugins`.
- Markdown browser assets under `Plugins/MarkdownViewer`.
- Protocol viewer templates under `Plugins/Templates`.
- Community `ProtocolTemplates`, `ExperimentTemplates`, `Icons`, and `Help`.
- Selected CSV catalogs under `CSV`.
- Required Delphi and licensed component runtime BPLs from explicit approved external locations.
- The Win32 SQLite runtime and WebView2 loader from explicit approved external locations.
- Applicable APS and third-party license and notice files.

Use the current selected viewer identities from Community. Do not import private instrument viewers or copy an entire installed library directory. External runtime filenames must match the built Win32 host and viewer dependencies. Validate required inputs before replacing a previous stage.

The WebView2 Evergreen browser runtime remains a documented host prerequisite. The package includes its loader, not an invented browser runtime. Packaging and verification must report this prerequisite. Do not install or download machine-wide prerequisites without separate authorization.

## Build and staging contract

Add Community-local installer source under `Installer` and a supported PowerShell entry point under `tools`.

Planned files:

| File | Responsibility |
| --- | --- |
| `Installer/ELNCommunitySetup.iss` | Product identity, task UI, files, shortcuts, and uninstall behavior |
| `Installer/Stage-Runtime.ps1` | Validate and assemble only the Community runtime and both CSV choices |
| `Installer/Demo/Equipment.csv` | Four fictional demo instruments |
| `Installer/Demo/ActionTypeEquipment.csv` | Four matching demo action assignments |
| `tools/build-installer.ps1` | Build host and viewers, stage runtime, read EXE version, and invoke Inno Setup |
| `tools/installer-runtime.example.psd1` | Explicit external packaging configuration schema |
| `Installer/Test-StageRuntime.ps1` | Synthetic staging boundary and catalog-selection regressions |
| `ELN.Community.Desktop/ELNCommunity.dpr` | Link the Community project resource |
| `ELN.Community.Desktop/ELNCommunity.dproj` | Consistent existing Community version metadata |
| `README.md` and `THIRD-PARTY-NOTICES.md` | Build, runtime, data-choice, and release contracts |
| `.gitignore` | Exclude the local installer runtime configuration |

Keep the existing six-field build dependency schema. Packaging runtime configuration is separate. It uses four required absolute inputs:

- `IsccPath`: installed Inno Setup compiler.
- `RuntimeBplRoot`: approved installed component runtime BPL directory. Standard Delphi runtime BPLs may also come from the configured Delphi bin directory.
- `SQLiteRuntime`: Win32 `sqlite3.dll`.
- `WebView2Runtime`: Win32 `WebView2Loader.dll`.

Use ignored root `installer-runtime.local.psd1` by default. Allow an explicit absolute runtime configuration path. Do not create or overwrite a local configuration file automatically. Do not add paths to global IDE or shell settings.

Generated installer staging, output, and logs stay under `_OUT/Installer/Win32/<Configuration>`. Staging and installer output remain separate from source and from developer host/viewer build output.

The build entry point must support prerequisite validation without compilation or output mutation. Normal builds produce the installer locally. There is no network deployment or publishing stage.

## Full and empty CSV behavior

Task label: `Install demo/reference data`.

For a first installation, the task is unchecked. On an upgrade, retain the previous choice unless the user selects a different choice. Silent installation must allow an explicit task selection or deselection.

Both choices install all seven required filenames:

1. `EquipmentTypes.csv`.
2. `ValueTypes.csv`.
3. `FileTypes.csv`.
4. `Equipment.csv`.
5. `ActionTypes.csv`.
6. `FileTypeLinks.csv`.
7. `ActionTypeEquipment.csv`.

### Empty choice

Generate each empty catalog from the corresponding neutral Community header. Preserve a header and an empty logical row with valid UTF-8 and CRLF. Do not omit files or use zero-byte files.

After New Notebook, the seven CSV-driven catalog entity sets must contain no imported data rows. Existing built-in non-CSV initialization, such as link types and notebook identity, remains unchanged.

### Full choice

Use the existing scientific rows from the neutral Community catalogs. Replace only the full payload's equipment and action-assignment catalogs with the synthetic demo files.

Use these four demo instruments:

| Equipment type | Model | Matching action |
| --- | --- | --- |
| Furnace | Demo Furnace | Annealing |
| Diffractometer | Demo Diffractometer | XRD |
| Balance | Demo Balance | Mass |
| Deposition System | Demo Deposition System | Deposition |

Every demo instrument uses manufacturer `Fictional Demo Instruments` and location `Synthetic demo lab`. Booking and information URLs are empty. Each description states that the instrument is a synthetic example, not a real instrument.

All type names and action titles must resolve to the existing full scientific catalogs. Do not add real manufacturers, laboratory locations, credentials, bookings, equipment records, or research content.

Keep `ELN.Desktop/Assets/Runtime/CSV/Equipment.csv` and `ActionTypeEquipment.csv` empty. Demo rows are installer inputs, not default Community source seeds.

### Selection and upgrade boundaries

Install exactly one complete CSV set to `{app}/CSV`. Do not concatenate full and empty sets, leave stale demo rows in a selected empty set, or import CSVs into existing notebooks during installation.

Changing the installer selection changes the seed catalogs for future notebooks only. An existing notebook retains its imported definitions, equipment, and user records. The installer never opens a notebook database.

## Failure and safety behavior

- A missing EXE, selected viewer, runtime dependency, catalog, asset tree, or required notice stops staging with its exact path.
- A failed validation or staging operation leaves the previous complete stage intact.
- A repository staging destination must be below Community `_OUT`. Reject the repository root, source directories, and ancestor destinations.
- Missing or inconsistent version metadata stops packaging.
- Do not bypass build guards, substitute Commercial or archived outputs, download dependencies, or change global settings to make a check pass.
- No fallback from an empty choice to full catalogs.
- No deletion, repair, migration, or adoption of existing notebooks or populated attachment directories.

## Verification and acceptance

Use only owned GUID-rooted synthetic notebooks, configuration files, staging directories, and install targets. Do not open existing research records.

Required evidence:

1. Runtime staging tests cover both catalog sets, synthetic demo reference integrity, missing-input failures, unsafe destinations, and preservation of the previous complete stage.
2. Community EXE metadata and installer metadata agree on the existing Community version and product name.
3. The installer compiles with the configured installed Inno Setup compiler.
4. The actual installer UI shows the demo task unchecked on a fresh install.
5. Isolated full installation stages all seven full catalogs and the required runtime and asset trees.
6. Actual New Notebook creation from the full installation succeeds without catalog import errors. It imports the scientific definitions, four synthetic instruments, and four matching assignments. The notebook reopens.
7. Isolated empty installation stages all seven valid empty catalogs. Actual New Notebook creation succeeds and imports zero CSV catalog rows. The notebook reopens.
8. Changing a test installation from full to empty and from empty to full selects the correct complete CSV set. A previously created synthetic notebook and its attachments remain unchanged.
9. Uninstall removes only installer-owned program files and shortcuts. Synthetic notebooks, attachments, configuration, and drafts outside the install tree survive.
10. A staged program can start with only its packaged application libraries and the documented Windows/browser prerequisites, without relying on Delphi or component directories in developer PATH.
11. Independent review covers package ownership, source isolation, dependency selection, installer task precedence, and data preservation before delivery.

No permanent tests may assert only copied source text or incidental wiring. Tests must exercise real staging behavior, references, boundaries, failure preservation, or user-visible data results. Installer and GUI verification remain required; tests alone do not prove the installed application works.

## Release boundary and known prerequisites

This task builds and verifies a local installer. It does not authorize redistribution of licensed runtimes, official binary publication, signing, deployment, a Git commit, or a Commercial pin update.

The required shared policy `D:/APS/Policy/Software_Policy.md` is unavailable. Apply the available product rules and user decisions; do not claim compliance with the missing policy or use its deprecated replacement.

The packaging configuration must point to approved runtime files. Existing source licenses and notices do not prove runtime redistribution rights. Report any unavailable runtime or compiler prerequisite rather than substitute an archive or private payload.
