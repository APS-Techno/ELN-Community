# APS ELN Community

This repository owns the shared scientific implementation, the local single-user hosts, local scientific tests and selected viewer source. Commercial consumes an exact commit from this repository; it must not keep a second active copy of shared units.

APS-owned source, scientific templates, artwork, resources and documentation are licensed under [Apache-2.0](LICENSE); see [NOTICE](NOTICE). Separately licensed third-party files and assets retain their original grants; see [third-party notices](THIRD-PARTY-NOTICES.md). The public source repository is [APS-Techno/ELN-Community](https://github.com/APS-Techno/ELN-Community).

## Install ELN Community

The first Windows release is [ELN Community 2.0.0.0](https://github.com/APS-Techno/ELN-Community/releases/tag/v2.0.0.0).
Download `ELNCommunitySetup-2.0.0.0.exe` from that release.
The installer is unsigned. Use the release's `SHA256SUMS.txt` to check the download.
The installer contains the Win32 Desktop application and its selected viewers.
It does not contain the MCP executable.

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
- `ViewerPlugins`: Core/Core.Protocol, Image, HTML, Markdown, ColumnarData, PDF, Protocol and Markdown Editor.

The standalone Domain and Model package projects overlap unit ownership. Do not load both packages in one process. The current source-compiled hosts and private Model composition preserve the existing package model.

## External build configuration

Use valid external Delphi/component installations. Do not copy vendor source, DCUs, DCPs, BPLs, keys or installers into this tree.

Copy `tools/build-dependencies.example.psd1` to ignored `build-dependencies.local.psd1`, then set each path to the matching installed dependency. The fields are `RsVarsPath`, `MSBuildPath`, `ShellPath`, `Dcc32Path`, `TmsRoot` and `ExternalUnitPaths`. External unit entries may use `{Platform}` and `{Configuration}`. Paths must be absolute. `-DependencyConfig` or `ELN_BUILD_DEPENDENCIES` can select the file explicitly.

Requirements include Delphi 13, Aurelius/BCL, TMS Plugin Framework, KSVC/Raize, TeeChart, VirtualTreeView, SynEdit, DUnitX, Python/Pillow and Windows SDK `rc.exe`. Developer coverage and official-binary redistribution rights are separate checks.

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

Other test targets are `StorageSmoke`, `NotebookTests`, `GateTests`, `AuthorizationTests` and `LocalFileTests`. The default is Win32 Debug. Hosts are never launched by `-RunTests`. Build package targets sequentially because Delphi can generate source-adjacent package resource files. Generated output belongs under `_OUT/<Target>/<Platform>/<Configuration>`.

`DesktopRegressionTests` covers signed mutations, draft dialogs, file identity,
preview isolation, protocol extraction, and viewer state. It uses synthetic
notebooks and temporary settings. `MarkdownEditorAttachmentTests` checks
attachment URL resolution without a browser. `MarkdownLauncherTests` runs in
its own process because it redirects that process's registry root to a new
temporary key. Do not combine that fixture with another runner. Select
`-Configuration Release` only when the installed dependencies support that
configuration; a Release result does not establish Debug coverage.

The default source root is this repository. The default viewer root is `ViewerPlugins` within it. Explicit `-SourceRoot` and `-ViewerRoot` overrides are available for controlled verification; they are not permission to fall back to old APS checkouts or installed APS packages.

For direct IDE builds, set `ELN_EXTERNAL_UNIT_PATHS` and `ELN_TMS_ROOT` explicitly and select the current local package outputs. The helper is the supported composition entry point.

## Local runtime layout

A source build is not a standalone installer. Supply SQLite and WebView2 from the approved external installations. Keep proprietary runtime BPLs external and process-local. Do not copy a legacy installer `_REDIST` tree.

For a developer run, the Desktop output directory needs:

- `CSV/`: the seven selected scientific catalogs from `ELN.Desktop/Assets/Runtime/CSV`, staged by the Desktop helper. New Notebook checks these files before creating the database.
- `ProtocolTemplates/` and `ExperimentTemplates/`: the selected scientific templates, with their subdirectories.
- `Icons/ELNIcons.dll`: generated by the Desktop helper.
- `Help/`: the 19 English offline HTML pages and `help.css` from `ELN.Desktop/Assets/Runtime/Help`, staged by the Desktop helper.
- `Plugins/Templates/`: `ViewerPlugins/Core.Protocol/Templates`.
- `Plugins/MarkdownViewer/`: the contents of `ViewerPlugins/Viewer.Markdown/assets`.
- `Plugins/`: the seven selected APS add-on BPLs from the `ViewerPackages` target. Shared Core/Core.Protocol BPLs are host-side prerequisites, not private replacements.

The viewer build places the seven add-on BPLs under `_OUT/ViewerPackages/Win32/Debug/Plugins` and the shared core BPLs beside that directory. Do not merge unrelated private viewer output into the selected plugin directory.

The Desktop accepts `--config`, `--plugins`, and paired `--notebook`/`--storage` arguments. Use new GUID-rooted synthetic notebooks for verification, not laboratory records. The MCP host uses its local notebook and storage arguments. Local human review remains in Desktop; human hypothesis gate execution is not exposed through MCP.

The plugin host restores the previous VCL application window when it closes.
Repeated host creation does not retain a destroyed parent window. Failed
construction preserves its original error, and plugin code stays loaded
until process exit.

Without `--notebook`/`--storage`, Desktop reopens the last successfully opened notebook and its matching attachment directory from the selected settings file. Explicit paths take priority. If the saved location is unavailable, Desktop reports the problem and leaves the welcome screen usable. Normal shutdown does not show a working-directory retention notice or require a separate database Save command.

When no notebook is open, the welcome message and New/Open buttons are centered as one block in the workspace. Resizing and display scaling preserve their relative spacing and keep the block centered.

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
binaries. Existing Community format-2 notebooks remain supported: SQLite
integer columns already preserve these values, so no marker-only migration is
required.
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

Build the host and seven selected viewers sequentially, stage the runtime,
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

## Release limits

Community uses native Windows VCL styling and does not embed Carbon. Saved unavailable theme names use the active Windows style; Preferences lists only registered styles. The shared VCL controls are retained. The Community host gives the project, item and viewer columns a common vertical gutter, without adding vertical margins at each nested splitter. Legacy private Help and personal user catalogs remain excluded; the Community manual replaces the private Help payload. Win64, Release, live MySQL, unsupported instrument/OLE viewers, existing deep-path/DPI limits and official binary distribution are not inferred from Win32 Debug checks.

Top-level tree rows keep a spacer above their content band. The shared renderer clears this spacer across the full row width, including unused space after the last column, so selection highlighting remains inside the content band.

The Community equipment and action-to-equipment catalogs contain their schema headers and one empty logical row. They contain no laboratory inventory. Keep that empty row: the current importer recognizes a header only when a second logical line exists. Add owned equipment through the reference-data editor or import an owned catalog. Operational inventory remains a private Commercial runtime input, not a shared Community seed.
