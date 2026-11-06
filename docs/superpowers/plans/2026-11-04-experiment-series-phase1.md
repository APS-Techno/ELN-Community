# Experiment Series, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A series of depositions in a project gives a comparison table, a plot and an Origin-ready export, filled from stored values, with no hand transcription.

**Architecture:** Three new Aurelius entities (`Series`, `SeriesMember`, `SeriesColumn`) in `ELN.Domain`. A pure table builder (`unit_SeriesTable`) and a model (`TSeriesModel`) in `ELN.Model` that loads members, their subtrees and values in a fixed number of statements. A Series card in the desktop content viewer, an "Add to series..." item-tree action, an export unit, and two read-only MCP tools.

**Tech Stack:** Delphi VCL, TMS Aurelius (SQLite in Community), VirtualTreeView, TeeChart Standard (no `TErrorBarSeries` installed), DUnitX.

**Spec:** `docs/superpowers/specs/2026-11-04-experiment-series-design.md` (§7, §8.1–8.3, §11 phase 1, §12, §14). Read it before any task.

## Global Constraints

- Work in `D:/APS/ELN/APS-ELN-Community`, branch `master`. Do not edit `APS-ELN-Commercial` or its `Community/` submodule.
- **Commits:** commit only when the owner has authorized commits for this plan run. Then use path-limited commits (`git add <exact paths>`), never `git add -A`. Do not commit `.res` files or IDE `.dproj` churn that the task did not intend. No push.
- Schema changes only through `UpdateDatabaseAdditive` (`ELN.DB/unit_SchemaUpdate.pas`). Do not edit `ELN.Domain/unit_ELNDB_Dictionary.pas`; use string `Linq['Field']` names, as `unit_HypothesisModel.pas` does.
- Enum ordinals are append-only. New enum values go at the end.
- Delphi rules: controls in DFM, no runtime creation of VCL controls (TeeChart series and VirtualTree header columns are collection/series objects; the plan says where they may be filled at runtime). `TVirtualImageList`, not `TImageList`. `AlignWithMargins`. `fsFlatRounded` on Rz containers. `try/finally` for every owned object.
- Preserve each file's encoding and line endings. New `.pas`/`.dfm` files: UTF-8 without BOM, CRLF, like `ELN.Model/unit_HypothesisModel.pas`. `ELN.Desktop/Views/frame_ProjectsPanel.pas` has a BOM and CR CR LF line endings: edit it with a script that keeps them.
- Comments are not allowed by default; a comment must prove its right to exist (a non-obvious constraint only).
- Number formatting in export and MCP: `TFormatSettings.Invariant`.
- Build and test: `pwsh -NoProfile -File tools/build-community.ps1 -Target <T> [-RunTests]`. Before a build, stop processes that lock `ELNPluginCore.bpl`. Start with the script's default platform and configuration; if Win32 Debug fails on missing TMS packages, use `-Platform Win64`.
- Out of scope: Commercial wiring (its main form and MCP server) waits for an authorized pin bump. `frm_Analysis` is not changed.

## Review Focus

1. **Two specimens measured by the same method in one deposition** (for example two Si pieces both with XRR thickness). Expect one flagged cell that shows both values, never a mean. Test: Task 2 `SameSourceTwoValuesIsAmbiguous`, Task 4 `AmbiguousCellJoinsValues`.
2. **A member or a descendant in the recycle bin, or a member moved to another project.** Expect the member excluded from rows and listed in `Excluded`, and deleted descendants ignored; no exception. Test: Task 3 `BuildTableExcludesRecycledAndForeignMembers`, `BuildTableSkipsDeletedDescendant`.
3. **A comma-decimal Windows locale** (Russian, German). Expect `.` as the decimal separator in clipboard, CSV and MCP output. Test: Task 4 `InvariantDecimalUnderCommaLocale`.
4. **A large series** (dozens of depositions with deep subtrees). Expect the statement count of `BuildTable` not to grow with the member count below one chunk. Test: Task 3 `BuildTableStatementCountIndependentOfMembers`.
5. **A value whose value type is unknown or a descendant whose action type is missing.** Expect the value skipped (unknown type) or keyed by the item's level (`lvl:<ordinal>`) when no action type is set; no access violation. Test: Task 2 `UnknownValueTypeSkipped`, Task 3 `BuildTableKeysItemWithoutActionType`.

---

### Task 1: Domain entities and audit entity type

**Files:**
- Create: `ELN.Domain/unit_Series.pas`, `ELN.Domain/unit_SeriesMember.pas`, `ELN.Domain/unit_SeriesColumn.pas`
- Modify: `ELN.Domain/unit_DomainEntities.pas` (uses list, ~line 73), `ELN.Domain/ELN.Domain.dpk` (~line 59) and `ELN.Domain/ELN.Domain.dproj` (~line 154), `ELN.Model/ELN.Model.dpk` and `ELN.Model/ELN.Model.dproj` (they re-list domain units, ~line 62 / ~148)
- Modify: `ELN.Domain/unit_AuditLog.pas:13,59-60`, `ELN.MCPServer/unit_ToolsMetadata.pas` (~540-560 project resolution, and the `get_audit_log` entity type list if it enumerates names), `ELN.Community.Tests/unit_AuthorizationTestSupport.pas:224-225`
- Test: `ELN.Community.Tests/test_SeriesModel.pas` (new DUnitX fixture, add to `DesktopRegressionTests.dpr` uses)

**Interfaces:**
- Produces (copy the attribute style of `unit_HypothesisRun.pas`; enums with `[Enumeration(TEnumMappingType.emInteger)]`):
  - `TSeriesStatus = (ssDraft, ssActive, ssClosed, ssAbandoned)`, `TSeriesCreatedVia = (scvDesktop, scvMcp)` in `unit_Series.pas`.
  - `TSeries`, table `Series`: `Id`, `ProjectId` (required, index `IX_Series_ProjectId`), `Title` (required, 255), `Purpose` (lazy, 65536), `Status` (required), `TargetFolderId: Nullable<Integer>`, `CreatedBy` (required), `CreatedDate` (required), `CreatedVia` (required), `ModifiedDate: Nullable<TDateTime>`, `Version` (required; same optimistic-lock pattern as `THypothesis.Version`).
  - `TSeriesAttemptState = (satValid, satFailed)` in `unit_SeriesMember.pas`. `TSeriesMember`, table `SeriesMembers`: `Id`, `SeriesId` (required), `ItemId` (required, index `IX_SeriesMembers_ItemId`), `SlotId: Nullable<Integer>`, `AttemptState` (required), `FailReason` (500), `AddedBy`, `AddedDate`. Unique `SeriesId,ItemId`.
  - `TSeriesColumnRole = (scrShown, scrHidden, scrVaried, scrResponse)` in `unit_SeriesColumn.pas`. `TSeriesColumn`, table `SeriesColumns`: `Id`, `SeriesId`, `RecType: TRecType`, `ValueTypeId`, `SourceKey` (required, 64; `''` = unsplit column), `ColumnRole` column name for the `Role` field (`ROLE` is reserved in MySQL 8), `SortOrder`. Unique `SeriesId,RecType,ValueTypeId,SourceKey`.
  - `aetSeries` appended after `aetSetting`; `AuditEntityTypeNames` gets `'Series'`.

- [ ] **Step 1: Write the failing tests** in `test_SeriesModel.pas` (fixture `TSeriesModelTests`, synthetic notebook from `TLocalNotebook.CreateNew(TPath.Combine(FRoot,'notebook.sqlite'), TPath.Combine(FRoot,'files'), 'Synthetic', 'Scientist', <password>)` as in `test_ReadOnlySweep.pas:378`):
  - `EntitiesRoundTrip`: save one `TSeries` (Status `ssActive`, Title `'Rate calibration Ti'`), one `TSeriesMember`, one `TSeriesColumn` (`SourceKey = ''`, Role `scrResponse`); clear the manager; reload with `Find<...>.Where(Linq['SeriesId'] = Id)`; assert every field equals what was saved.
  - `DuplicateMemberRejected`: saving a second `TSeriesMember` with the same `SeriesId,ItemId` raises on `Flush`.
- [ ] **Step 2: Run** `pwsh -NoProfile -File tools/build-community.ps1 -Target DesktopRegressionTests -RunTests`. Expected: compile failure (units missing).
- [ ] **Step 3: Implement** the three entity units with `RegisterEntity` in `initialization`, and register them in `unit_DomainEntities.pas` and the four package files. Append `aetSeries`. In `unit_ToolsMetadata.pas` resolve `aetSeries` rows to `TSeries.ProjectId` the same way `aetHypothesis` uses `HypothesisProjects` (one batched lookup). In `unit_AuthorizationTestSupport.pas` add `AddAudit(aetSeries, 999999)` next to the `aetHypothesis` line so the unresolvable-row check covers it.
- [ ] **Step 4: Run** `DesktopRegressionTests -RunTests` and `AuthorizationTests -RunTests`. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): the files above, message `feat(series): add series entities and audit type`.

### Task 2: Pure table builder

**Files:**
- Create: `ELN.Model/unit_SeriesTable.pas` (add to `ELN.Model.dpk`/`.dproj`)
- Test: `ELN.Community.Tests/test_SeriesTable.pas` (DUnitX, no database; add to `DesktopRegressionTests.dpr`)

**Interfaces:**
- Produces:
```pascal
const
  SERIES_ROOT_KEY = 'root';
function SeriesActionTypeKey(AActionTypeId: Integer): string;   // 'at:<id>'
function SeriesLevelKey(ALevel: TItemLevel): string;             // 'lvl:<ordinal>'

type
  TSeriesHit = record
    RootItemId, ItemId, ValueId, ValueTypeId: Integer;
    RecType: TRecType;
    Value, Tol: Double;
    SourceKey: string;
  end;
  TSeriesValueTypeInfo = record Id: Integer; Title, Units: string; end;
  TSeriesSourceInfo = record Key, Caption: string; end;
  TSeriesRowInput = record MemberId, ItemId: Integer; Title: string; Failed: Boolean; end;
  TSeriesColumnPref = record
    RecType: TRecType; ValueTypeId: Integer; SourceKey: string;
    Role: TSeriesColumnRole; SortOrder: Integer;
  end;
  TSeriesTableColumn = record
    RecType: TRecType; ValueTypeId: Integer; SourceKey: string;
    Caption, Units: string; Role: TSeriesColumnRole;
  end;
  TSeriesCell = record
    Hits: TArray<TSeriesHit>;
    function IsMissing: Boolean;
    function IsAmbiguous: Boolean;
  end;
  TSeriesTableRow = record
    MemberId, ItemId: Integer; Title: string; Failed: Boolean;
    Cells: TArray<TSeriesCell>;
  end;
  TSeriesTable = record
    Columns: TArray<TSeriesTableColumn>;
    Rows: TArray<TSeriesTableRow>;
    Excluded: TArray<Integer>;
    function ColumnIndex(ARecType: TRecType; AValueTypeId: Integer; const ASourceKey: string): Integer;
  end;

function BuildSeriesTable(const ARows: TArray<TSeriesRowInput>;
  const AHits: TArray<TSeriesHit>; const ATypes: TArray<TSeriesValueTypeInfo>;
  const ASources: TArray<TSeriesSourceInfo>; const APrefs: TArray<TSeriesColumnPref>;
  AIncludeFailed: Boolean): TSeriesTable;
```
- Rules the tests pin (spec §8.1):
  - Column key = (RecType, ValueTypeId). Split when any included row has hits with two or more distinct `SourceKey`s for that key; then one column per distinct key over all included rows, `SourceKey` = that key. Otherwise one column with `SourceKey = ''`.
  - Caption: value type `Title`; split columns append ` [<source caption>]`, where `root` → `deposition` and other keys use `ASources`; an unknown key uses the key text.
  - Order: `EXP_CONDITION` columns before `TEST_RESULT`; then a matching pref's `SortOrder`; then caption (ordinal compare). Role from the exact-key pref, else `scrShown`. Hidden columns stay in `Columns`.
  - Hits whose `ValueTypeId` is not in `ATypes` are skipped. Rows keep `ARows` order. Failed rows are dropped unless `AIncludeFailed`.

- [ ] **Step 1: Write the failing tests:** `UnsplitWhenOneSourcePerColumn` (2 rows, thickness from `at:5` in both → 1 column, caption `'Thickness'`, `SourceKey = ''`); `SplitsWhenTwoSourcesInAnyRow` (row 1 `at:5` + `at:7`, row 2 only `at:5`, sources `at:5='XRR'`, `at:7='Profilometry'` → captions `'Thickness [Profilometry]'`, `'Thickness [XRR]'`; row 2 `at:7` cell `IsMissing`); `SameSourceTwoValuesIsAmbiguous` (one row, two `at:5` hits 50 and 52 → one cell with 2 hits, `IsAmbiguous`); `ConditionAndResultOfSameTypeAreSeparate`; `RootKeyCaptionIsDeposition`; `FailedRowsExcludedUnlessRequested`; `PrefsApplyRoleAndOrder` (pref Hidden kept with role `scrHidden`; pref `SortOrder` beats caption order); `UnknownValueTypeSkipped`.
- [ ] **Step 2: Run** `DesktopRegressionTests -RunTests`. Expected: compile failure.
- [ ] **Step 3: Implement** `BuildSeriesTable` and the helpers in `unit_SeriesTable.pas`.
- [ ] **Step 4: Run** the same command. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): `feat(series): pure series table builder`.

### Task 3: Series model

**Files:**
- Create: `ELN.Model/unit_SeriesModel.pas` (add to `ELN.Model.dpk`/`.dproj`)
- Modify: `ELN.Model/unit_RecycleBinModel.pas:64-83` (`ItemChildDeletes`) and its purge routine
- Test: `ELN.Community.Tests/test_SeriesModel.pas` (extend Task 1 fixture)

**Interfaces:**
- Consumes: Task 1 entities, Task 2 `BuildSeriesTable` and records, `IdChunks` (`unit_HypothesisModel.pas:199`), `RecordAudit`, `IProjectAccessPolicy`.
- Produces:
```pascal
type
  ESeriesError = class(Exception);
  ESeriesAccess = class(ESeriesError);
  TSeriesSummary = record
    Id, ProjectId: Integer; Title, Purpose: string;
    Status: TSeriesStatus; MemberCount: Integer;
  end;
  TSeriesAddResult = record Added, AlreadyIn: Integer; end;

  TSeriesModel = class
  public
    constructor Create(AManager: TObjectManager; const AAccess: IProjectAccessPolicy);
    function ListSeries(AUser: TUser; AProjectId: Integer): TArray<TSeriesSummary>;
    function Get(AUser: TUser; AId: Integer): TSeriesSummary;
    function SeriesForItem(AUser: TUser; AItemId: Integer): TArray<TSeriesSummary>;
    function CreateSeries(AUser: TUser; AProjectId: Integer; const ATitle, APurpose: string): Integer;
    procedure UpdateSeries(AUser: TUser; AId: Integer; const ATitle, APurpose: string);
    procedure ChangeStatus(AUser: TUser; AId: Integer; ANew: TSeriesStatus);
    function AddMembers(AUser: TUser; AId: Integer; const AItemIds: TArray<Integer>): TSeriesAddResult;
    procedure RemoveMember(AUser: TUser; AId, AItemId: Integer);
    procedure SaveColumnPrefs(AUser: TUser; AId: Integer; const APrefs: TArray<TSeriesColumnPref>);
    function BuildTable(AUser: TUser; AId: Integer; AIncludeFailed: Boolean): TSeriesTable;
  end;
```
- Rules:
  - Access: read methods call `FAccess.CanRead`, write methods `FAccess.CanWrite`, on the series project; refuse with `ESeriesAccess` (pattern: `RequireRead`/`RequireWrite`, `unit_HypothesisModel.pas:362-371`).
  - `CreateSeries`: trimmed title, 1..255 chars, else `ESeriesError`; Status `ssActive`, `CreatedVia = scvDesktop`, Version 1.
  - `ChangeStatus` allows only Active→Closed, Closed→Active, Draft→Abandoned, Active→Abandoned; anything else raises.
  - `AddMembers`, `RemoveMember`, `SaveColumnPrefs` raise `ESeriesError('The series is closed.')` when Status is Closed or Abandoned.
  - `AddMembers` runs in one transaction. Each item must exist, be non-deleted, have `ParentID = 0`, `Level <> Folder`, and the series `ProjectId`; otherwise raise `ESeriesError` naming the item id, and nothing is saved. An existing member counts in `AlreadyIn`.
  - `SaveColumnPrefs` replaces all `SeriesColumn` rows of the series.
  - Writes follow `AttachRun` (`unit_HypothesisModel.pas:690-749`): `BeginTransaction`, `Flush`, `RecordAudit(FManager, aetSeries, Id, aoCreate|aoUpdate, AUser.Id, <text>)`, `Commit`, and `UnwindFailedWrite`-style rollback. One audit row per call (create, update, status, add members with the id list, remove member). No audit for column prefs.
  - `BuildTable` loads: members of the series; all non-deleted items of the series project as projections (Id, ParentID, Level, ActionType id, IsDeleted, Title only for roots) in one query, as `SubtreeItemIds` (`ELN.Model/ViewModels/unit_ItemTreeBatch.pas:89`) but for all roots in one walk; values by `ItemID._In(chunk)` (projections: Id, ItemID, TypeID, RecType, Value, Tol); value types and action types by `_In(chunk)`. Use projections, as `TLiveRows` in `unit_HypothesisModel.pas`, so the identity map cannot give stale rows.
  - Source key of a value: `SERIES_ROOT_KEY` on the root; else `SeriesActionTypeKey(ActionType.Id)`; if the item has no action type, `SeriesLevelKey(Level)`. Source caption = action type title, or the level name.
  - A member whose item is deleted or now in another project is not a row; its item id goes to `Excluded`.

- [ ] **Step 1: Write the failing tests** (fixture builds items with the model or `Manager.Save` of `TItem`/`TValue`, as in `test_ItemLevelTools.pas:27-45`; create a `TActionType` row `'XRR'` if the notebook seed has none):
  - `CreateAndList` (title `'  Rate calibration Ti '` stored trimmed; `ListSeries` returns it with `MemberCount = 0`); `CreateRejectsEmptyTitle`.
  - `AddMembersRejectsNonRootItem`, `AddMembersRejectsOtherProject`, `AddMembersRejectsDeletedItem`: each raises `ESeriesError` and leaves 0 members, also for a valid item in the same call.
  - `AddMembersCountsAlreadyIn` (add [A,B] then [B,C] → second result Added 1, AlreadyIn 1).
  - `ClosedSeriesRefusesAddAndReopenAllows`; `ChangeStatusRejectsAbandonedToActive`.
  - `BuildTableReadsGrandchildValues`: Deposition D (Proc, Synthesis, `EXP_CONDITION` power 200) → Specimen S → Measurement M (Action, action type XRR, `TEST_RESULT` thickness 51.0, Tol 0.5) → one row; power cell 200 with `SourceKey` column `''`; thickness cell 51.0, Tol 0.5, hit `ItemId = M`.
  - `BuildTableSkipsDeletedDescendant` (M soft-deleted → thickness cell missing).
  - `BuildTableExcludesRecycledAndForeignMembers` (member root soft-deleted; another member moved to a second project → 0 rows for them, both ids in `Excluded`).
  - `BuildTableKeysItemWithoutActionType`.
  - `BuildTableStatementCountIndependentOfMembers`: count statements as `test_DesktopLoadStatements.pas` does; 2 members vs 20 members (each with a 3-level subtree) give the same count.
  - `CreateWritesSeriesAudit` (one `TAuditLog` with `EntityType = aetSeries`, `EntityId` = new id).
  - `PurgeRemovesMembershipWithAudit`: soft-delete a member root, purge it through `TRecycleBinModel`; no `SeriesMembers` row is left for that item id, and one `aetSeries` audit row says the item was purged. (SQLite reuses item ids, so a left-over row would silently add a new item to the series.)
- [ ] **Step 2: Run** `DesktopRegressionTests -RunTests`. Expected: compile failure.
- [ ] **Step 3: Implement** `TSeriesModel`. In `unit_RecycleBinModel.pas`, add `'DELETE FROM SeriesMembers WHERE ItemId = %ID%'` to `ItemChildDeletes` (grow the array bound), and before the deletes write one `aetSeries` audit row per affected series: `Purged item <id> from the recycle bin; removed from the series.`
- [ ] **Step 4: Run** the same command. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): `feat(series): series model with subtree value table`.

### Task 4: Export

**Files:**
- Create: `ELN.Model/unit_SeriesExport.pas` (add to `ELN.Model.dpk`/`.dproj`)
- Test: `ELN.Community.Tests/test_SeriesExport.pas` (DUnitX; add to `DesktopRegressionTests.dpr`)

**Interfaces:**
- Consumes: `TSeriesTable` (Task 2).
- Produces: `function SeriesTableToText(const ATable: TSeriesTable; ADelimiter: Char): string;`
- Format (spec §8.3): columns with `Role <> scrHidden`, in table order, after a first column `Item` (row title). Row 1 = names (captions); row 2 = units (`''` for `Item`). After a value column, add `± <caption>` only if any cell of that column has `Tol > 0`; its unit equals the value unit. Data rows: `FloatToStr(..., TFormatSettings.Invariant)`; missing cell → empty field; ambiguous cell → all values joined with `'; '`, and its `±` field empty. Line ending CRLF. With `,` as delimiter, quote a field that contains `,`, `"`, CR or LF, and double inner quotes. With tab, replace tab, CR and LF in a field by a space.

- [ ] **Step 1: Write the failing tests:** `NamesAndUnitsRows` (first two lines equal `Item<TAB>Power<TAB>Thickness` and `<TAB>W<TAB>nm`); `ToleranceColumnOnlyWhenAnyTol`; `HiddenColumnsSkipped`; `AmbiguousCellJoinsValues` (`'50; 52'`); `InvariantDecimalUnderCommaLocale` (set `FormatSettings.DecimalSeparator := ','` in the test, restore in `finally`; expect `51.5`); `CsvQuotesTitlesWithCommaAndQuote` (title `D-1, "Ti"` → `"D-1, ""Ti"""`).
- [ ] **Step 2: Run** `DesktopRegressionTests -RunTests`. Expected: compile failure.
- [ ] **Step 3: Implement** `SeriesTableToText`.
- [ ] **Step 4: Run** the same command. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): `feat(series): Origin-ready table export`.

### Task 5: Read-only MCP tools

**Files:**
- Create: `ELN.MCPServer/unit_ToolsSeries.pas`
- Modify: `ELN.MCPServer/unit_ToolCatalog.pas:28-41` (call `RegisterSeriesTools` after `RegisterHypothesisTools`), `ELN.Community.Tests/unit_ReadToolAllowlist.pas:16-32`, `ELN.Community.Tests/test_ReadOnlySweep.pas:455-461` (`ParamsFor`), `ELN.Desktop/Assets/Runtime/Help/MCP.html`
- Test: add cases next to the `list_hypotheses` tests in `ELN.Community.Tests/test_ValueSourceTools.pas:3396-3467` and register them in its `RunTest` (~3915)

**Interfaces:**
- Consumes: `TSeriesModel` (Task 3), `TSeriesTable` (Task 2).
- Produces `procedure RegisterSeriesTools(Registry: TToolRegistry);` with two tools, `tscProjectScoped`, `taRead`, handlers wrapped like `RunHypTool` (`unit_ToolsHypotheses.pas:101-115`; map `ESeriesAccess` to a plain message and `ESeriesError` to the `[refusal]` form):
  - `list_series`, params `project_id` (required) → `{"project_id":N,"series":[{"id","title","purpose","status","member_count"}]}`. `status` uses the enum name without prefix (`Active`).
  - `get_series_table`, params `series_id` (required), `include_failed` (boolean, default false) → `{"series_id","project_id","title","status","columns":[{"rec_type":"EXP_CONDITION|TEST_RESULT","value_type_id","caption","units","source_key","role"}],"rows":[{"item_id","title","cells":[[{"value","tol","value_id","item_id"}]]}],"excluded_item_ids":[...]}`. All columns, including Hidden ones, with their role. Each cell is an array of hits (empty = missing, 2+ = ambiguous).
  - Both refuse a project outside `Context.ScopedProjects` the same way `get_hypothesis_tree` does.

- [ ] **Step 1: Write the failing tests:** `list_series` returns the series made in the fixture; `get_series_table` on a series with one deposition (power 200, thickness 51.0 from XRR) returns 2 columns and the cell values in invariant format; a scoped context without the project is refused; both tools are in the read allowlist and pass the read-only sweep.
- [ ] **Step 2: Run** `DesktopRegressionTests -RunTests`. Expected: failures for the new tool names.
- [ ] **Step 3: Implement** `unit_ToolsSeries.pas`, registration, allowlist and sweep entries. Add both tools to `MCP.html` in the read tools list.
- [ ] **Step 4: Run** `DesktopRegressionTests -RunTests`, then build `-Target CommunityMCP`. Expected: tests pass; MCP builds.
- [ ] **Step 5: Commit** (if authorized): `feat(series): list_series and get_series_table MCP tools`.

### Task 6: Series view in the desktop

**Files:**
- Create: `ELN.Desktop/ViewModels/unit_SeriesVM.pas`, `ELN.Desktop/Views/frame_Series.pas`, `ELN.Desktop/Views/frame_Series.dfm`, `ELN.Desktop/Assets/Runtime/Help/Series.html`
- Modify: `ELN.Desktop/Views/frame_ContentViewer.pas/.dfm` (~77-93, 33-34, 86-89, 630-641), `ELN.Desktop/Views/frame_ProjectsPanel.pas/.dfm` (~972, 986, 2418-2431, 244-247, 443-447; script edit), `ELN.Community.Desktop/frm_CommunityMain.pas` (~304, 431, 1126-1129), `ELN.Community.Desktop/ELNCommunity.dpr` (next to `frame_Hypotheses`, line 20), `ELN.Desktop/Assets/Runtime/Help/help-toc.json`, `ELN.Desktop/Assets/Runtime/Help/Projects.html`

**Interfaces:**
- Consumes: `TSeriesModel`, `TSeriesTable`, `SeriesTableToText`.
- Produces:
  - `TOpenSeriesEvent = procedure(Sender: TObject; AProjectId, ASeriesId: Integer) of object;` declared in `unit_SeriesVM.pas`.
  - `TSeriesVM.Create(AManager: TObjectManager; AUser: TUser; const AAccess: IProjectAccessPolicy)`; `OpenProject(AProjectId, ASeriesId: Integer)`; `Reload`; `Select(AIndex: Integer)`; properties `Series: TArray<TSeriesSummary>`, `SelectedIndex`, `Table: TSeriesTable`, `CanWrite: Boolean`; commands `NewSeries(const ATitle, APurpose: string): Integer`, `EditSelected(const ATitle, APurpose: string)`, `ChangeStatus(ANew: TSeriesStatus)`, `AddItems(const AItemIds: TArray<Integer>): TSeriesAddResult`, `RemoveMember(AItemId: Integer)`, `SetColumnRole(AColumn: Integer; ARole: TSeriesColumnRole)`, `ExportText(ADelimiter: Char): string`; event `OnChanged: TNotifyEvent`. Ownership and refresh as `THypothesesVM` (`frame_Hypotheses.pas:221-256, 328-339, 815-819`).
  - `TframeSeries.OpenProject(AProjectId, ASeriesId: Integer)` and `ResetSession`.
  - `TframeContentViewer.ShowSeries(AProjectId, ASeriesId: Integer)` and `SeriesShowing: Boolean`.
  - `TframeProjectsPanel.actSeries` ('Series...', same enable rule as `actHypotheses`) and `OnOpenSeries: TOpenSeriesEvent`.
- Layout (DFM): toolbar `New series...`, `Edit...`, `Close`/`Reopen` (one button, caption by status), `Abandon...`, `Remove from series`, `Refresh`, `Copy table`, `Save CSV...` (`TFileSaveDialog` in DFM, filter `*.csv`). Left `vstSeries` (columns Series, Status, Depositions). Right `TPageControl`: **Table** tab with `vstTable`, **Plot** tab with `cbX` (visible condition columns), `clbY` (visible result columns), `cbGroup` (`(none)` + condition columns), `chkTrend`, `chtPlot: TChart`. Status bar text when `Excluded` is not empty: `<n> deposition(s) are in the recycle bin or another project.`
- Table tab: header columns are rebuilt from `Table.Columns` in `VMChanged` (collection items, allowed). Cell text: value, `value ± tol`, `—` for missing, values joined with `; ` plus a warning glyph for ambiguous. Header popup sets the role (Shown, Hidden, Varied, Response) through `SetColumnRole`. Double-click opens the hit's item through the same item-navigation event `frame_Hypotheses` uses for run rows.
- Plot tab: DFM holds a pool `serGroup1..serGroup8: TLineSeries` (pointer visible) and `serTrend: TLineSeries`. One pool series per distinct `cbGroup` value (first 8; then show `Showing the first 8 groups.`); with `(none)`, one series per Y column. Default X = first Varied column, else first condition column; default Y = Response columns. Ambiguous or missing cells are not plotted. Error bars: draw vertical bars in `chtPlot.OnAfterDraw` from `Tol` with `CalcXPosValue`/`CalcYPosValue` (TeeChart Standard has no error bar series). Trend: least squares as `TfrmAnalysis.AddRegressionLine`, for a single visible curve only.
- `Copy table` → `Clipboard.AsText := VM.ExportText(#9)`; `Save CSV...` → `TFile.WriteAllText(Path, VM.ExportText(','), TEncoding.UTF8)`.

- [ ] **Step 1: Implement** the VM, frame, card, panel action (script edit for `frame_ProjectsPanel.pas`), main-form wiring, `.dpr` entry, `ResetSession` on logout (as `frmHypotheses`), and `Series.html` (copy the header of `Hypotheses.html`; sections: make a series, add depositions, read the table, plot, export to Origin) with its `help-toc.json` entry and a link from `Projects.html`.
- [ ] **Step 2: Build** `-Target CommunityDesktop`. Expected: success, no new warnings in the new units.
- [ ] **Step 3: Smoke run** the built desktop with a scratch Community notebook: three depositions with power 100/200/300 W, each with one specimen and an XRR measurement with thickness and Tol, plus one deposition with two XRR specimens. Open **Project > Series...**, create a series, add the four depositions, and check: one row per deposition; the two-specimen row shows a flagged cell; the plot shows thickness against power; `Copy table` pasted into a text editor shows the names row, the units row and `.` decimals.
- [ ] **Step 4: Run** `DesktopRegressionTests -RunTests`. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): `feat(series): series view with table, plot and export`.

### Task 7: Item tree entry and item detail

**Files:**
- Create: `ELN.Desktop/Dialogs/Series/dlg_SeriesPick.pas`, `ELN.Desktop/Dialogs/Series/dlg_SeriesPick.dfm`
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas/.dfm` (menu next to `miItemAttachHypothesis`, dfm:626-629; handler pattern pas:3707-3741; popup update ~3410; multi-selection rule function; detail panel near `lblDetails`, pas:71), `frm_CommunityMain.pas` (wire `frmItemTree.OnOpenSeries`, as line 306 does for hypotheses), `ELN.Desktop/Assets/Runtime/Help/Series.html`

**Interfaces:**
- Consumes: `TSeriesVM.AddItems`, `NewSeries`, `TSeriesModel.ListSeries`, `SeriesForItem`, `TOpenSeriesEvent`.
- Produces: `class function TdlgSeriesPick.Execute(const AChoices: TArray<TSeriesSummary>; out ASeriesId: Integer; out ANewTitle: string): Boolean; static;` — list of Active series plus a `New series` option with a title edit; exactly one of `ASeriesId > 0` or `ANewTitle <> ''` on OK. Same form lifetime pattern as `TdlgHypothesisPick.Execute`.
- Rules: `miItemAddToSeries` ('Add to series...') is enabled when the user can edit and every selected node is a root item (`ParentID = 0`, not Folder). It is a batch action in the multi-selection rule function (the multiselect design names the others as disabled; this one is enabled for 1..n roots). Handler reads ids before any refresh, calls the dialog, creates the series if needed, calls `AddItems`, shows `<n> already in the series.` when `AlreadyIn > 0`, then fires `OnOpenSeries`. Detail panel: `lblSeries: TRzLabel` (DFM) shows `Series: <title>, <title>` for a root item that is a member of one or more series, hidden otherwise.

- [ ] **Step 1: Implement** dialog, menu item, enable rule, handler, wiring and `lblSeries`; add an "Add from the item tree" paragraph to `Series.html`.
- [ ] **Step 2: Build** `-Target CommunityDesktop`. Expected: success.
- [ ] **Step 3: Smoke run:** select three root depositions → **Add to series...** → new series `'Smoke B'` → the Series view opens with 3 rows; repeat with one of them → message `1 already in the series.`; a child item shows the menu item disabled; the detail panel of a member shows `Series: Smoke B`.
- [ ] **Step 4: Run** `DesktopRegressionTests -RunTests`. Expected: all pass.
- [ ] **Step 5: Commit** (if authorized): `feat(series): add to series from the item tree`.

### Task 8: Final verification

- [ ] **Step 1: Run** `DesktopRegressionTests -RunTests`, `AuthorizationTests -RunTests`, `GateTests -RunTests`, `NotebookTests -RunTests`. Expected: all pass.
- [ ] **Step 2: Build** `CommunityDesktop` and `CommunityMCP`. Expected: success.
- [ ] **Step 3: Owner acceptance (spec §11 phase 1):** the owner opens a real past series (copy of a notebook, never live data), adds its depositions, and compares the table and plot with the one made by hand in Origin. Record the result in `D:/APS/ELN/.claude/HANDOFF.md`.
