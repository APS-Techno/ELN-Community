# APS ELN Community

This repository owns the shared scientific implementation, the local single-user hosts, local scientific tests and selected viewer source. Commercial consumes an exact commit from this repository; it must not keep a second active copy of shared units.

APS-owned source, scientific templates, artwork, resources and documentation are licensed under [Apache-2.0](LICENSE); see [NOTICE](NOTICE). Separately licensed third-party files and assets retain their original grants; see [third-party notices](THIRD-PARTY-NOTICES.md). The public source repository is [APS-Techno/ELN-Community](https://github.com/APS-Techno/ELN-Community).

## Install ELN Community

The latest Windows release is [ELN Community 2.2.1.43](https://github.com/APS-Techno/ELN-Community/releases/tag/v2.2.1.43).
Download `ELNCommunitySetup-2.2.1.43.exe` from that release.
The installer is unsigned. Use the release's `SHA256SUMS.txt` to check the download.
The installer contains the Win32 Desktop application, its selected viewers and the MCP server (`ELNCommunityMCP.exe`).

Windows 10 or later is required. Browser-based viewers and Help also require
the [Microsoft WebView2 Evergreen Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/).
The installer includes the WebView2 loader, not the browser runtime.
Installation is per-user and does not require administrator access.
Demo/reference data and the desktop shortcut are off by default.
Installer task changes affect future notebooks only, not existing notebooks.
Back up each notebook database and its attachment directory together.

## Source layout

- `ELN.Domain`, neutral `ELN.Model` and `ELN.DB`: shared scientific records and implementation.
- `ELN.Community`: local notebook, identity, access policy and working-file service.
- `ELN.Community.Desktop` and `ELN.Community.MCP`: local VCL and stdio hosts.
- `ELN.Community.Tests`: local storage/notebook/gate/authorization/file suites and the canonical report fixture.
- Selected `ELN.Desktop` files: original scientific VCL surface, dialogs, assets and helpers.
- Selected `ELN.MCPServer` files: neutral transport and scientific tools, not private identity/server composition.
- `ViewerPlugins`: Core/Core.Protocol, the Markdown Editor and 26 viewers: Image, HTML, Markdown, ColumnarData, PDF, Protocol, JSON, Note, OLE, File, LAMMPS, XRDML, DM3, OPJU, XRayCalc, XRFX, Deposition, ProcessLog, Recipe, DSC, DSR, ZRW, MIT, FIBPS, Tribo (plain-text tribometer `.raw`) and VK4.

The MIT (`.mit`, Anton Paar UNHT nanoindentation), FIBPS (`.fibps`, Filmetrics Profilm3D surface) and VK4 (`.vk4`, Keyence laser confocal microscope) readers were written from analysis of our own measurement files only. They contain no vendor code and no code from other parsers. APS is not affiliated with or endorsed by Anton Paar, KLA/Filmetrics or Keyence; the names identify file compatibility only.

The standalone Domain and Model package projects overlap unit ownership. Do not load both packages in one process. The current source-compiled hosts and private Model composition preserve the existing package model.

## External build configuration

Use valid external Delphi/component installations. Do not copy vendor source, DCUs, DCPs, BPLs, keys or installers into this tree.

Copy `tools/build-dependencies.example.psd1` to ignored `build-dependencies.local.psd1`, then set each path to the matching installed dependency. The fields are `RsVarsPath`, `MSBuildPath`, `ShellPath`, `Dcc32Path`, `TmsRoot` and `ExternalUnitPaths`. External unit entries may use `{Platform}` and `{Configuration}`. Paths must be absolute. `-DependencyConfig` or `ELN_BUILD_DEPENDENCIES` can select the file explicitly.

Requirements include Delphi 13, Aurelius/BCL, TMS Plugin Framework, KSVC/Raize, TeeChart, VirtualTreeView, SynEdit, JAM ShellBrowser (File viewer), DUnitX, Python/Pillow and Windows SDK `rc.exe`. Developer coverage and official-binary redistribution rights are separate checks.

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target StorageTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target ScientificTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target DesktopRegressionTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target MarkdownEditorAttachmentTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target MarkdownLauncherTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target ViewerPackages
pwsh -NoProfile -File tools/build-community.ps1 -Target CommunityDesktop
pwsh -NoProfile -File tools/build-community.ps1 -Target CommunityMCP
```

Other test targets are `StorageSmoke`, `NotebookTests`, `GateTests`, `AuthorizationTests` and `LocalFileTests`. The default is Win32 Debug. Hosts are never launched by `-RunTests`. Build package targets sequentially because Delphi can generate source-adjacent package resource files. Generated output belongs under `_OUT/<Target>/<Platform>/<Configuration>`. The exception is `CommunityDesktop`: the executable, its core BPLs, `Icons`, `CSV` and `Help` go directly to `_OUT/CommunityDesktop`, and compiler intermediates go to `_OUT/CommunityDesktop/Intermediate/<Platform>/<Configuration>`. The last Desktop build replaces the previous one, whatever its platform or configuration.

Build Community applications and installers only in this standalone repository.
Commercial's pinned `Community/` checkout supplies shared source and regression
fixtures, not a second Community application build location.

`DesktopRegressionTests` covers signed mutations, draft dialogs, file identity,
preview isolation, protocol extraction, viewer state, and the LAMMPS, DM3,
XRFX, XRDML, DSC, X-Ray Calc and ZRW readers. It uses synthetic
notebooks and temporary settings. `MarkdownEditorAttachmentTests` checks
attachment URL resolution without a browser. `MarkdownLauncherTests` runs in
its own process because it redirects that process's registry root to a new
temporary key. Do not combine that fixture with another runner. Select
`-Configuration Release` only when the installed dependencies support that
configuration; a Release result does not establish Debug coverage.

Storage traversal regressions use an existing outside source and check that its
bytes remain unchanged. File-service guard tests require proof that each injected
write attempt ran. Scientific report tests check signature integrity badges,
and Desktop file-identity tests move attachment bytes with 64-bit IDs.

The default source root is this repository. The default viewer root is `ViewerPlugins` within it. Explicit `-SourceRoot` and `-ViewerRoot` overrides are available for controlled verification; they are not permission to fall back to old APS checkouts or installed APS packages.

For direct IDE builds, set `ELN_EXTERNAL_UNIT_PATHS` and `ELN_TMS_ROOT` explicitly and select the current local package outputs. The helper is the supported composition entry point.

## Local runtime layout

A source build is not a standalone installer. Supply SQLite and WebView2 from the approved external installations. The `CommunityDesktop` target reads `WebView2Runtime` from the ignored root `installer-runtime.local.psd1`, or from `-RuntimeConfig` with an absolute path. That loader must match the build platform; for Win32 it is the x86 `WebView2Loader.dll`. Keep proprietary runtime BPLs external and process-local. Do not copy a legacy installer `_REDIST` tree.

For a developer run, the Desktop output directory needs:

- `CSV/`: the seven selected scientific catalogs from `ELN.Desktop/Assets/Runtime/CSV`, staged by the Desktop helper. New Notebook checks these files before creating the database.
- `ProtocolTemplates/` and `ExperimentTemplates/`: the selected scientific templates, with their subdirectories.
- `Icons/ELNIcons.dll`: generated by the Desktop helper.
- `Help/`: the 19 English offline HTML pages and `help.css` from `ELN.Desktop/Assets/Runtime/Help`, staged by the Desktop helper.
- `WebView2Loader.dll`: copied by the Desktop helper from the configured `WebView2Runtime`. Without it beside the executable, Windows can find a loader for another architecture on `PATH`, and Help and the browser viewers stay blank.
- `Plugins/Templates/`: `ViewerPlugins/Core.Protocol/Templates`.
- `Plugins/MarkdownViewer/`: the contents of `ViewerPlugins/Viewer.Markdown/assets`.
- `Plugins/`: the 27 selected APS add-on BPLs, built by the Desktop helper together with the host. Shared Core/Core.Protocol BPLs are host-side prerequisites, not private replacements. The OLE viewer embeds `.xlsx`, `.docx` and `.pptx` files through their installed OLE server application.

The application and installer use a shaded teal notebook with metal spiral
binding, visible page edges, and a recessed flask emblem.
Regenerate the ICO and matching 150/600-pixel logos with
`python ELN.Desktop/Assets/DevTools/AppIcons/generate_icon.py`.
The ICO contains size-specific images from 16 to 256 pixels.

The Desktop shows a 600x340 startup splash (`ELN.Community.Desktop/frm_CommunitySplash`) after `Application.Initialize` and frees it before `Application.Run`. The splash displays the executable version and the current startup step as live labels. The artwork (icon, edition text, divider, accent line) is a PNG embedded in `frm_CommunitySplash.dfm`. Regenerate the PNG and re-embed it with
`python ELN.Desktop/Assets/DevTools/AppIcons/generate_splash.py`;
it requires Pillow and the Windows Segoe UI fonts, reuses `draw_icon(216)` from `generate_icon.py`, and also writes `splash.png` beside the script.

The Desktop build places all 27 selected add-on BPLs in `_OUT/CommunityDesktop/Plugins` and the matching shared core BPLs beside the executable. It also stages `Plugins/Templates` and `Plugins/MarkdownViewer`, including Markdown vendor assets. No separate viewer build or manual copy is needed for Desktop.

The standalone `ViewerPackages` target places the same add-ons and plugin assets under `_OUT/ViewerPackages/<Platform>/<Configuration>/Plugins` and the shared core BPLs beside that directory. Do not merge unrelated private viewer output into either selected plugin directory.

The Desktop accepts `--config`, `--plugins`, `--notebook`, and an optional `--storage` that needs `--notebook`. Use new GUID-rooted synthetic notebooks for verification, not laboratory records. The MCP host requires `--notebook`, `--upload-root`, and `--plugins`; its `--storage` is optional. Local human review remains in Desktop; human hypothesis gate execution is not exposed through MCP.

The plugin host restores the previous VCL application window when it closes.
Repeated host creation does not retain a destroyed parent window. Failed
construction preserves its original error, and plugin code stays loaded
until process exit.

MCP file-name search matches the stored title plus extension. File hits include
`file_id`, `full_name`, and `extension`. Multi-word queries retain matching files
when the other terms occur in the owning item's title.
Both extraction tools include `file_name` and identify a complete `.depo.json`
suffix even when the catalog extension is `.json`. Extraction still requires
a configured viewer that supports the file format.

The ZRW viewer (`aps.zrw`, `.zrw` and `.zrv` tribometer files) parses the data rows strictly and independently of the system locale. Every line before the first data row (the first line that starts with a number) is header; the older tab-separated header and the newer one-line `Key: value [unit]` header are both read. Extraction gives `Fn`, `Cycles`, `Stroke`, `Speed`, `Sampling Rate` (older files), `Sampling Interval` (newer files; a different quantity, no unit), `COF` and `COF STD`. `COF` is the mean friction coefficient over the selected interval (by default the first coating plateau after running-in), and `COF STD` is the population standard deviation over all samples of that interval; extraction stores it as the tolerance of `COF`. The automatic plateau candidate is the first cycle (in cycle order) whose own median gives ±30% band coverage of at least 95% over the next 20% of the recorded cycle span and over the next 5%; that median then stays fixed. The plateau ends at the first cycle where the centred 5% rolling median leaves the band, so short spikes do not end it; if the rolling median stays in the band, the plateau runs to the end of the record. A candidate that ends within 20% of the span is skipped. Then the running-in is removed with a marginal-standard-error rule fitted to a straight line: for each possible start in the first half of the plateau samples, the residual sum of squares of a least-squares line through the rest of the plateau is divided by the square of its sample count. The start is the first cycle whose value is the lowest within ±10% of the recorded cycle span. A steady drift therefore stays in the plateau, while an oscillating or overshooting running-in is cut. A result shorter than 20% of the recorded cycle span gives no plateau. Snapshots and shared selections record algorithm version 3, `truncation` 0.5 and `local_window` 0.1. The viewer interval panel switches between Automatic and Manual start/end. Apply stores one shared interval per file in the notebook settings; drafts are never saved, and if the shared interval was changed after you opened the file, the draft is kept and Reload is required. If the file bytes change, the stored interval is stale and COF extraction is blocked until you click Apply again, with a Manual interval or with Automatic. Desktop extraction stores a snapshot with each `COF` value; MCP stores one when `analysis_snapshot` from `extract_file_key_values` is passed to `add_value`/`add_values`. A COF value without a snapshot cannot be re-checked over its interval; the drift check reports it as `interval_unusable`. The drift check calculates a snapshot value again over the stored interval. Scientific package export does not carry snapshots, and the package importer does not restore value rows.

A notebook saves its attachment directory in the `COMMUNITY_ATTACHMENT_DIR` row of `DBSettings`. On the same drive the value is relative to the folder of the database (for example `..\Files` for a `DB` folder beside a `Files` folder), so a notebook moved together with its attachment directory opens at the new location; on another drive the value is absolute. On open, a drive-relative value, a missing directory, a directory that contains the database, or a reparse point is refused. New Notebook saves the directory. Desktop asks for the directory only when the notebook has no saved directory or the saved directory cannot be used. After that choice, Desktop offers to remember the directory and writes the row only when the user accepts. MCP never writes the row. An explicit `--storage` overrides the saved directory in both hosts.

Without `--notebook`, Desktop reopens the last successfully opened notebook from the selected settings file. The settings file does not store an attachment directory. Explicit paths take priority. If the last notebook is unavailable, Desktop reports the problem and leaves the welcome screen usable. Normal shutdown does not show a working-directory retention notice or require a separate database Save command.

`File → Recent Notebooks` lists up to eight notebooks that opened successfully, the most recent first, from the `RecentNotebook1` to `RecentNotebook8` keys of the selected settings file. The active notebook has a check mark. Selecting another entry switches to it with the same validation as Open Notebook. A missing entry can be removed from the list; Clear Recent List removes all entries.

When no notebook is open, the welcome message and New/Open buttons are centered as one block in the workspace. Resizing and display scaling preserve their relative spacing and keep the block centered.

## Version 2.2.1.43

The Add/Edit action dialog has drop-down lists for Item type, Action type and Equipment, and Values and Properties tabs. The Values tab shows the source of the selected value. Go to file closes the dialog and opens the source file in the viewer.
In the Projects, Items and Hypotheses trees, the Collapse all below, Expand all below and Focus buttons show only on the selected row, not on every row under the mouse. They use thin outline glyphs in the row text colour; the button under the mouse shows a light rounded highlight.
The installer contains the MCP server (`ELNCommunityMCP.exe`) beside Desktop.
Help describes the tree row buttons, the action dialog, the restored project selection at startup, the MIT, FIBPS, Tribo and VK4 viewers, value types without a unit, and the MCP server in the installer.

## Version 2.2.0.39

The file browser uses folder and document icons with normal-weight text.
Icons scale with display DPI and retain transparent backgrounds.
File selection and folder navigation are unchanged.
Desktop builds now deploy all selected viewer packages and their runtime assets to the working folder.
Automatic ZRW plateau detection removes oscillating and slow running-in, keeps a steady drift in the plateau and ignores short COF spikes.
The thumbnail of a `.depo.json` deposition snapshot shows the Overview tab. A `.tsv` deposition log keeps the chart of its first curve.
Attaching a file with a compound type such as `.depo.json` or `.process.log` removes the full extension from the suggested name. The stored name no longer repeats `.depo`.
Replacing an attachment keeps its current file type when the new file ends with that type's extension, so a `.depo.json` file stays `.depo.json`. Otherwise the longest matching registered extension sets the new type.
The Items tree accepts a multiple selection. Delete, Extract values, Move to, Tags, Export files and drag to the Projects panel work on all selected records with one confirmation and one summary.
Extracting values again from the same file, also through Regenerate previews, updates the Reader value that the file gave before instead of adding a second value. Deleting a file also deletes the Reader values that it gave to its item; the confirmation shows their count. Manual values stay.
The Help dialog keeps its Close button at the bottom-right corner when the dialog is resized.
Link Types, Go to Item and the Save and Reload Attachment Working Draft commands in the main menu have their own icons.
Desktop builds copy the configured WebView2 loader beside the executable, so Help and the browser viewers show their content when run from the working folder.
Recipe conditions in a `.depo.json` deposition snapshot map by default in a new or upgraded notebook, with the same rules as a `.recipe` file. Parameters of the `Layer <Material>`, `Parameters` and `Deposition Conditions` groups map by their unit for every material and parameter name, so a new material combination or parameter needs no new rule.
A new value type without a unit, such as Cycles, can be saved in Value Types. Before, saving it stopped with "Field 'Units' must have a value".
In the Projects, Items and Hypotheses trees, the selected row stops at the right edge of the last column, the same as the other rows. Before, the selection also filled the empty area to the right of the columns.
In the Projects and Items trees, the last visible column fills the remaining tree width, so no empty area stays to the right of the columns. The stretch follows a resize of the tree or of another column, Show IDs and a column drag. Saved column widths keep the width of the last column when it is not stretched.
Opening another notebook no longer asks for its attachment directory each time. The notebook saves the directory, relative to the folder of the database when both are on the same drive, so a `DB` folder beside a `Files` folder works. Desktop and MCP use it. New Notebook suggests an empty `<name> files` folder beside the database.
The X-Ray Calc reader `aps.xrcx` is now version 2. Layer values of the main repeated stack are means over its periods, including polynomial and table profiles. Period is the sum of its mean layer thicknesses. The main stack has the largest repeat count greater than one; a tie selects the first stack. Its material keys have no stack suffix for the first occurrence. Other stacks use their model index in the key suffix. Chi2 is returned only when `chiSquared` exists and parses as a number. Detailed JSON is unchanged. Existing stored Reader values are not migrated.
File → Recent Notebooks switches to one of the last eight opened notebooks without the Open dialog.
The MIT reader `aps.mit` is now version 2. When the file holds valid instrument results, `Hardness` is the instrument H_IT and `Modulus` is the instrument sample modulus E_IT, per indent, and `Reduced Modulus` is Er from the stored stiffness. When the instrument results are missing, the reader computes `Hardness` and `Reduced Modulus` from the measured peak force and skips an indent with an unphysical unloading fit; `Modulus` is not given then. `Max Force` is the measured peak force. `Indent Count` and `Indents Excluded` tell how many indents the mean uses and how many the file cannot give. The ticked indents are the selection of the file: they are stored as the shared selection, the extraction dialog stores them as a snapshot with each value, and `extract_file_key_values` accepts `selection` with `{"mode":"indents","checked":[1,3,5]}` for one call. Existing stored MIT values are not migrated; the drift check reports them as reader version changed.

## Community Help

Open `Help → Contents...` or `Help → Keyboard Shortcuts...`. Both use the selected HTML viewer and external WebView2 runtime. No network assets or legacy laboratory screenshots are needed. The manual covers local notebook safety, scientific records, files/drafts, Wiki, review, signatures, reports, reference data and MCP. Commands and shortcuts follow the current Community composition, not the legacy Commercial host.

The Help assets are staged only by the Community Desktop target. Direct IDE builds must supply that same `Help/` tree beside the executable. The HTML viewer retains the latest requested content when its frame is reparented between the host and Help dialogs.

Scientific package import is not a full notebook restore. Keep database and attachment backups together, and retain unsaved drafts separately. The manual records this boundary and the current signature, chart, DPI and deep-path limits.

## Integrity and data compatibility

New item signatures use a versioned, length-framed hash with locale-independent
numeric encoding. Verification reads committed records, not the editor cache.
Older unversioned signatures remain stored and keep the item locked. Their
status is **Legacy signature; integrity cannot be verified**. This status is
not evidence of modification. The application does not silently re-sign them.

Editing an in-use protocol template creates a separate version and preserves
the old schema. Failed package imports and experiment-template applications
roll back their operation without saving unrelated editor drafts. Mass
concentration and molar concentration are separate quantities; the converter
does not invent a molar mass.

File identities use 64-bit integers. Rebuild the host, Core packages, and every
selected viewer together after this interface change. Do not load older plugin
binaries. File identities need no migration: SQLite integer columns already
preserve these values.

Current source builds use notebook format 5. Format 4 added reader-to-value-type
mapping rules and saves the original reader unit and applied conversion factor
with each new Reader value. Default rules include deposition and recipe
conditions, XRCX layer values, and the demonstration reader keys. The recipe
rules apply to both `aps.recipe` and `aps.deposition`, because a `.depo.json`
snapshot embeds the same recipe. Each parameter of the `Layer <Material>`,
`Parameters` and `Deposition Conditions` groups maps by its unit, through the
patterns `Layer <Material>.<Any>`, `Parameters.<Any>` and
`Deposition Conditions.<Any>`: `mTorr` and `Torr` to Pressure (Pa), `sccm` to
Flow, `mA` to Current (A), `s`, `sec`, `min` and `us` to Time (s), `kHz` to
Frequency (Hz), `%` to Duty cycle, `W` to Power, `V` to Voltage and `mm` to
Distance (m). In a layer group, the material becomes the label. Exact rules
keep the period counts `Parameters.N` and `Deposition Conditions.N` and the
BN/DLC material labels of `Parameters.PowerBN`, `.CurrentC`, `.TimeBN`,
`.TimeC` and `.TimeCtop`. A parameter with another unit stays unmapped. The
seed runs only when a
notebook is created or upgraded and adds only missing rules. An existing
format-5 notebook does not get the new rules automatically: add them through
`Reference Data → Value Types... → Reader mappings...`. A mapping
does not install a reader or add keys to an existing reader. Format 5 adds the
Derived source kind: the formula ID and version on the value (`DataValues`
`FormulaId`, `FormulaVersion`) and one row per input in the `DerivedValueInputs`
table (result value, role, input value ID and the input number that was used).

Edit rules through `Reference Data → Value Types... → Reader mappings...`.
Rules specify reader ID, exact key or key pattern, expected reader unit, target
value type, factor, and description label. A key pattern contains fixed text
and the placeholders `<Material>` and `<Any>`. `<Material>` captures a
material name; every `<Material>` in one pattern must capture the same text,
and the captured text becomes the label. `<Any>` matches any text. Matching
uses exact rules first, then the matching pattern with the most fixed text,
then the existing title-and-unit fallback. Units must match before conversion.
Desktop extraction and MCP use the same resolver. Range checks use the
converted number. Mapping edits affect future extraction only.

Extraction pairs each `<Key>` with `<Key> STD` from the same reader batch.
Their emitted units must match. The stored tolerance is STD multiplied by the
absolute conversion factor; no separate STD value is stored. Missing STD
leaves tolerance unset. Invalid or ambiguous STD gives a warning and leaves
the main value without tolerance. Orphan STD keys are reported and not stored.
The existing range and tolerance-scale checks still apply. Source drift
checks compare the main number, not its tolerance.

A Derived value is computed from other stored values by a named formula. The
first formula is `wear_rate_reciprocating` version 1, the reciprocating wear
rate `K = A / (2 · F · N)`. Its roles are `area` (value type Wear area, mm²),
`normal_force` (Normal force, N) and `cycles` (Cycles, no unit); the result is
Wear rate in mm³/(N·mm). The area can be zero; force and cycles must be
positive. Negative and non-finite inputs are refused. Every input must be a
stored value of the required type and unit on the result item or an item below
it in the same project. An input can be Reader, Manual or another Derived
value; Derived inputs are checked recursively, and a dependency cycle is
refused. One formula registry serves Desktop, MCP and the drift check. The
result goes through the value-type range check; no tolerance is stored, because
no uncertainty-propagation rule is defined. Desktop: `Add → Derived Value...`
on a Proc or Action item; choose the formula and, per role, a stored value
from the item subtree. The client computes the number; the user cannot type
it. Editing a Derived number by hand afterwards makes it a Manual value with
the note `Edited by hand; was derived by <formula> version <n>`. MCP:
`add_derived_value` takes `item_id`, `formula_id`, `inputs` (role → value ID),
an optional `description` and `confirm_out_of_range`; the server computes the
number and refuses any other field, including `value`. `add_value` refuses
source kind Derived. On a database without the format-5 objects,
`add_derived_value` is registered but refuses the call and stores nothing.
`get_values`, `get_item` and `query_values` show the formula ID, version and
inputs. Deleting or editing an input does not delete the Derived value.

`check_value_drift` and Desktop `Check Value Sources...` also check Derived values.
Reader inputs are re-read through their readers with the saved factor, Derived
inputs are recomputed recursively, and Manual or Unknown inputs use their
stored number. The result is recomputed with the saved formula version. Flags:
`value_changed`; `input_changed` (an input differs from the number used when
the value was stored); `input_missing`; `formula_version_changed` (a newer
version exists, the saved one was used); `formula_version_mismatch` (the saved
version is not available; the value is not recomputed); `dependency_cycle`;
`read_failed`; and `not_fully_rerunnable` (a Manual or Unknown value is in the
input tree). A Derived value with only Manual inputs is therefore always listed
with `not_fully_rerunnable`.

Desktop asks before upgrading a format-2, format-3 or format-4 notebook. It
first copies the database beside the original as
`<name>.format<old-version>-backup-<timestamp>-<guid>.sqlite`, then adds the schema,
seeds missing mapping defaults and the Wear area, Normal force, Cycles and Wear
rate value types, and stamps format 5. Existing values keep their source kind
and A1 provenance. A notebook that already has a Wear rate type in another unit
gets a second Wear rate type in mm³/(N·mm). It preserves existing
values and descriptions. Legacy Reader values keep their original raw-output
drift comparison because their conversion provenance is unknown. New Reader
values use their saved factor; a changed reader unit is reported without
applying that factor. The published 2.1 installer remains a separate release.

Value entry checks the value-type range and the tolerance scale. A tolerance
larger than the value, or smaller than the value divided by the tolerance factor
(DBSettings `VALUE_TOLERANCE_FACTOR`, default 1000), is flagged. Desktop asks for
confirmation; MCP `add_value` and `add_values` refuse unless
`confirm_out_of_range` is true. Read-only checks: `check_value_drift` re-reads
Reader values with their source file, `report_value_issues` lists range and
tolerance problems, and `check_storage` compares stored bytes with the recorded
MD5. `check_storage` accepts an optional `baseline` list of earlier findings and
reports their current status in `previously_reported`.
The shared additive updater does not require a file-identity width migration.
It leaves existing column types unchanged; each host retains its schema-update
workflow and stored-column limits.

New project-root operations use folder ID `0`. Desktop and MCP use the same
root context. Existing records with nonpositive root-folder IDs remain visible;
opening a notebook does not rewrite those records.
Shared project views retain the signed-in viewer's identity when selecting an
owner group. An owner filter does not grant that owner's permissions.

## Windows installer

Use PowerShell 7 and the installed Inno Setup compiler. The installer is
Community-only and uses the built Community EXE's version. It does not read
Commercial source, output, inventory, or licensing.

Keep the existing build dependency configuration. Create the ignored root
`installer-runtime.local.psd1` from `tools/installer-runtime.example.psd1`
only if the local file does not already exist. Set four absolute paths:

| Field | Required input |
| --- | --- |
| `IsccPath` | Installed Inno Setup `ISCC.exe` |
| `RuntimeBplRoot` | Approved installed Win32 component runtime BPL directory |
| `SQLiteRuntime` | Approved Win32 `sqlite3.dll` |
| `WebView2Runtime` | Approved Win32 `WebView2Loader.dll` |

The installed WebView2 Evergreen browser runtime is also required for browser
viewers and Help. The package contains its loader, not the browser runtime.
Do not infer runtime redistribution rights from the source licenses.

Validate prerequisites without compilation or output mutation:

```powershell
pwsh -NoProfile -File tools/build-installer.ps1 -ValidateOnly
```

Build the host and 27 selected viewers sequentially, stage the runtime,
and compile the installer locally:

```powershell
pwsh -NoProfile -File tools/build-installer.ps1 -Platform Win32 -Configuration Release
```

Use `-DependencyConfig` and `-RuntimeConfig` to select explicit absolute
configuration files. Installer builds default to Win32 Release; this does
not change the developer helper's Win32 Debug default.

The generated installer is
`_OUT/Installer/Win32/Release/Output/ELNCommunitySetup-<version>.exe`.
The stage and build log remain under `_OUT/Installer/Win32/Release`,
not in installer source directories.

Installation is per-user, under the user's `Programs/ELN Community`
directory by default. Community has its own shortcuts and uninstall identity.
The desktop shortcut and **Install demo/reference data** are unchecked on
a fresh installation.

| Demo task | CSV catalogs used by New Notebook |
| --- | --- |
| Unchecked | All seven required CSV files, with schema headers and no data rows |
| Checked | Full scientific definitions, four fictional instruments, and four matching action assignments |

The fictional instruments are Demo Furnace, Demo Diffractometer, Demo Balance,
and Demo Deposition System. They use fictional manufacturer and location
fields, with no real laboratory inventory or booking links. Neutral source
equipment catalogs remain empty.

An upgrade retains the previous task choice unless the user changes it.
Silent installation can select `/TASKS=demodata` or deselect with `/TASKS=`.
`/NOICONS` suppresses Start Menu shortcuts; do not select `desktopicon` if
no desktop shortcut is wanted.

Changing the task changes the CSV seeds for future notebooks only.
Installation never opens or changes existing notebooks. Uninstall removes
installer-owned program files and shortcuts, not notebooks, attachments,
user preferences, or retained editor drafts.

Run the synthetic staging boundary regressions with:

```powershell
pwsh -NoProfile -File Installer/Test-StageRuntime.ps1
```

This local build does not publish or deploy the installer. Official binary
distribution, signing, and licensed runtime redistribution require separate
authorization and entitlement checks.

## Public source publication

The maintainer development checkout and the public GitHub repository have
separate histories. Do not push the development branch or its tags directly
to GitHub: this can publish nonpublic ancestors.

For an authorized release:

1. Use a clean, reviewed development commit. Record its commit ID with
   `git rev-parse HEAD` and its tree ID with `git rev-parse HEAD^{tree}`.
2. Create an owned temporary directory outside the source and build trees.
   Clone `https://github.com/APS-Techno/ELN-Community.git` there with
   `--single-branch --branch main --no-tags`. Do not build in this clone.
3. Fetch public `main` into the development checkout with `--no-tags`.
   Record `FETCH_HEAD` and require it to match the temporary clone's `HEAD`.
   Stop on a failed Git command or a changed public base.
4. Export a binary, full-index patch from that public base to the reviewed
   development commit with `git diff --binary --full-index --output`.
   Apply the patch in the temporary public clone with `git apply --index`.
5. Require `git write-tree` in the temporary clone to equal the recorded
   development tree. Review the payload and licenses before creating a commit.
   The new public commit must have only the existing public base as its parent.
6. Commit, tag, and push only from the temporary public clone, after separate
   publication authorization. Match the tag to the built application version.
   Build and verify the installer in standalone Community, then upload that
   exact installer and its SHA-256 checksum to the authorized release.
7. Verify the remote tag and downloaded assets. Then remove only the owned
   temporary clone and patch. Keep release artifacts and verification evidence
   under this repository's `_OUT`; do not retain another development checkout.

## Release limits

Community uses native Windows VCL styling and does not embed Carbon. Saved unavailable theme names use the active Windows style; Preferences lists only registered styles. The shared VCL controls are retained. The Community host gives the project, item and viewer columns a common vertical gutter, without adding vertical margins at each nested splitter. Legacy private Help and personal user catalogs remain excluded; the Community manual replaces the private Help payload. Win64, Release, live MySQL, instrument viewers outside the selected set, OLE documents without their installed OLE server, existing deep-path/DPI limits and official binary distribution are not inferred from Win32 Debug checks.

Top-level tree rows keep a spacer above their content band. The shared renderer clears this spacer across the full row width, including unused space after the last column, so selection highlighting remains inside the content band.

The Community equipment and action-to-equipment catalogs contain their schema headers and one empty logical row. They contain no laboratory inventory. Keep that empty row: the current importer recognizes a header only when a second logical line exists. Add owned equipment through the reference-data editor or import an owned catalog. Operational inventory remains a private Commercial runtime input, not a shared Community seed.
