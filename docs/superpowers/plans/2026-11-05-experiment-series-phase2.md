# Experiment Series, Phase 2 (Plan-First) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A series starts as a plan (factors, levels, fixed conditions, responses). Its table shows every planned point from the start, and depositions enter only by being made from a point or linked to one.

**Architecture:** Four new Aurelius entities (factors, fixed conditions, slots, slot levels) join notebook format 6, which is not released yet. A new value source kind, `vskPlanned`, marks values written from the plan until a person confirms them. `TSeriesModel` gets the plan, point, make, link, fail and unlink operations; the pure builder builds one row per point. The desktop gets a plan editor dialog, a point-based Series view with row actions in a context menu, and **Link to plan point...** in the item tree. The phase 1 free membership (**Add to series...**, `AddMembers`) is removed. MCP gets `create_series` and `update_series_plan` (Draft only for MCP).

**Tech Stack:** Delphi VCL, TMS Aurelius (SQLite in Community), VirtualTreeView, TeeChart Standard, DUnitX.

**Spec:** `docs/superpowers/specs/2026-11-04-experiment-series-design.md` (§7, §7.1, §8.4–8.7, §9 MCP bullet, §11 phase 2, §12, §13 Q2). Read it before any task. Phase 1 plan: `docs/superpowers/plans/2026-11-04-experiment-series-phase1.md` (its Global Constraints still apply).

## Global Constraints

- Work only in the worktree `D:/APS/ELN/APS-ELN-Community/.worktrees/experiment-series`, branch `feature/experiment-series`. Do not touch the main checkout, `APS-ELN-Commercial`, or any `Community/` submodule.
- Commits: allowed, path-limited only (`git add <exact paths>`). No `.res` files, no unintended `.dproj` churn. NEVER push.
- Schema: additive Aurelius entities, created by `UpdateDatabaseAdditive` during the format upgrade. Do not edit `ELN.Domain/unit_ELNDB_Dictionary.pas`; use string `Linq['Field']` names. Reserved words (`ROLE`, `VALUE`, `ORDER`, `LEVEL`) are not column names; use `LevelValue`, `FixedValue`, `SortOrder`.
- Notebook format stays `'6'` (unreleased). Every new table is checked in `TLocalNotebook.VerifyCurrentSchema`.
- Enum ordinals are append-only.
- Delphi rules: controls in DFM; no runtime creation of VCL controls (VirtualTree header columns and TeeChart series pool are allowed as in phase 1); `TVirtualImageList`; `AlignWithMargins`; `fsFlatRounded` on Rz containers; `try/finally` for every owned object.
- Preserve encoding and line endings. New `.pas`/`.dfm`: UTF-8 without BOM, CRLF. `frame_ProjectsPanel.pas` and `frame_ItemTree.pas` have a BOM: keep it. After each task, no file that was CRLF may contain LF-only lines.
- Comments are not allowed by default; a comment must prove its right to exist (a non-obvious constraint only). It is strictly PROHIBITED to post comments based on the principle that "a comment is useful if the information is accurate and relevant."
- Number formatting in export and MCP: `TFormatSettings.Invariant`; MCP numbers through `ExactNum` (`unit_JSONCompact`).
- Test runners: series model/builder/export tests and value-source desktop tests → `DesktopRegressionTests`; MCP tool tests in `test_ValueSourceTools.pas` → `AuthorizationTests`; notebook format tests → `NotebookTests` (`LocalNotebookTests.dpr`). Command: `pwsh -NoProfile -File tools/build-community.ps1 -Target <T> -RunTests` from the worktree root.
- MCP never passes a human step: no MCP tool starts a series, makes or links a deposition, confirms planned values, or edits a planned value.
- Out of scope: approval gates, notices, hypothesis link (phase 3); Taguchi (phase 4); Commercial wiring.

## Review Focus

1. **A deposition whose stored factor value differs slightly from the plan** (199.97 W planned as 200 W, Tol 0.1). Expect it to link by value to the 200 W point and the cell not flagged as a deviation; 195 W with Tol 0.1 is flagged. Test: Task 3 `LinkByValuesMatchesWithinTolerance`, Task 4 `DeviationUsesValueTolerance`.
2. **Unconfirmed planned values reaching the plot or the export as data.** Expect empty export fields, no plot point, and a plot note. Test: Task 5 `PlannedHitsExportEmpty`, Task 4 `PlannedHitIsNotPresentForMeasured`.
3. **A format-6 notebook from the phase 1 build** (no phase 2 tables). Expect `Open` to refuse with a message naming the `.format5-backup` copy, without changing a byte. Test: Task 1 `PreReleaseFormat6IsRefused`.
4. **A second deposition for a point that already has a valid one** (double click, two users). Expect refusal; the user marks the first failed first. Test: Task 3 `MakeRefusedWhenSlotHasValidMember`, `LinkRefusedWhenSlotHasValidMember`.
5. **Editing the plan after points have depositions** (remove a factor, narrow a range). Expect refusal with a message that names the blocking points; nothing changes. Test: Task 3 `SavePlanRefusesFactorChangeWithPoints`, `SavePlanRefusesRangeExcludingPoint`.

---

### Task 1: Phase 2 entities, `vskPlanned`, schema check on open

**Files:**
- Create: `ELN.Domain/unit_SeriesFactor.pas`, `ELN.Domain/unit_SeriesFixed.pas`, `ELN.Domain/unit_SeriesSlot.pas` (slot and slot level)
- Modify: `ELN.Domain/unit_DomainEntities.pas`, `ELN.Domain/ELN.Domain.dpk/.dproj`, `ELN.Model/ELN.Model.dpk/.dproj`; `ELN.Domain/unit_SeriesColumn.pas` (append `scrFixed`); `ELN.Domain/unit_ItemTypes.pas:21` (append `vskPlanned`); `ELN.Community/unit_LocalNotebook.pas` (Open, VerifyCurrentSchema)
- Test: `ELN.Community.Tests/LocalNotebookTests.dpr`, `ELN.Community.Tests/test_SeriesModel.pas`

**Interfaces (produces):**
- `TSeriesFactor`, table `SeriesFactors`: `Id`, `SeriesId` (req), `ValueTypeId` (req), `RangeMin`, `RangeMax`, `ApprovedMin`, `ApprovedMax` (all `Nullable<Double>`), `SortOrder` (req). Unique `SeriesId,ValueTypeId`.
- `TSeriesFixed`, table `SeriesFixedConditions`: `Id`, `SeriesId`, `ValueTypeId`, `FixedValue: Double`, `Tol: Double`. Unique `SeriesId,ValueTypeId`.
- `TSeriesSlotOrigin = (ssoPlanned, ssoAdded)`. `TSeriesSlot`, table `SeriesSlots`: `Id`, `SeriesId` (req, index), `Origin` (req), `AddedBy`, `AddedDate`, `Reason` (500).
- `TSeriesSlotLevel`, table `SeriesSlotLevels`: `Id`, `SlotId` (req, index), `FactorId` (req), `LevelValue: Double`. Unique `SlotId,FactorId`.
- `TSeriesColumnRole` gains `scrFixed` (last). `TValueSourceKind` gains `vskPlanned` (last).
- `VerifyCurrentSchema` also selects one column from each of the four tables (`WHERE 1 = 0`).
- `TLocalNotebook.Open`, for a notebook whose stored format equals `LOCAL_FORMAT_VERSION`, calls `VerifyCurrentSchema` after the format check and before `ReadPrincipal`. Any exception from it becomes `ELocalNotebookError` with exactly: `This notebook was upgraded by a pre-release ELN Community build and lacks tables of format 6. Open its .format5-backup copy and upgrade that copy again.`

- [ ] **Step 1: Write the failing tests.** LocalNotebookTests: extend `TestFormat5UpgradesToFormat6AddsSeries` to drop and then expect the four new tables (`SeriesFactors`, `SeriesFixedConditions`, `SeriesSlots`, `SeriesSlotLevels` each count 0 after upgrade); add `TestPreReleaseFormat6IsRefused` (fresh notebook, `DROP TABLE SeriesSlotLevels`, free, `Open` raises `ELocalNotebookError` whose message contains `.format5-backup`, database bytes unchanged) and register it. test_SeriesModel: `PlanEntitiesRoundTrip` (save one of each new entity, `Manager.Clear`, reload, every field equal, `RangeMin` null stays null).
- [ ] **Step 2: Run** `NotebookTests -RunTests` and `DesktopRegressionTests -RunTests`. Expected: compile failure / new tests fail.
- [ ] **Step 3: Implement** entities (pattern: `unit_SeriesMember.pas`), registration, enum appends, schema check, Open change.
- [ ] **Step 4: Run** `NotebookTests`, `DesktopRegressionTests`, `AuthorizationTests` (`-RunTests`). Expected: all pass. A `case` over `TValueSourceKind` or `TSeriesColumnRole` that the compiler now warns about is fixed in Task 2 or Task 4; in this task make it compile with the narrowest behaviour (`vskPlanned` treated like `vskManual`) and list each such place in the report.
- [ ] **Step 5: Commit** `feat(series): plan entities, planned source kind, schema check on open`.

### Task 2: Planned source kind behaviour

**Files:**
- Modify: `ELN.Model/unit_ValueSource.pas` (:57-160), `ELN.Model/unit_ItemModel.pas`, `ELN.Model/unit_ValueDrift.pas` (:309, :438, :483, :595, :765), `ELN.Desktop/Dialogs/Items/dlg_Value.pas` (:105-120, :269-272), `ELN.Desktop/Dialogs/Items/dlg_Action.pas` (:321 if needed), `ELN.MCPServer/unit_ToolsWrite.pas` (:1275-1285), `ELN.MCPServer/unit_ToolsValueEdit.pas` (:82-96, :416-420), `ELN.MCPServer/unit_ToolsValueChecks.pas:174`, `ELN.MCPServer/unit_ToolHelpers.pas:102`
- Test: `ELN.Community.Tests/test_ValueSourceDesktop.pas`, `ELN.Community.Tests/test_ValueSourceTools.pas`

**Interfaces (produces):**
- `class function TValueSourceInfo.Planned(const ANote: string): TValueSourceInfo;` → `Kind = vskPlanned`, `Note = ANote`, no reader/formula fields.
- `SourceKindName(vskPlanned) = 'Planned'`. `TryParseSourceKind('Planned')` returns False (no client may write Planned). `ValidateSource` refuses reader or formula fields on Planned.
- `function TItemModel.HasPlannedValues(AItemId: Integer): Boolean;`
- `function TItemModel.ConfirmPlannedValues(AUserId, AItemId: Integer): Integer;` — every `vskPlanned` value of that item becomes `vskManual` with `SourceNote = 'Confirmed planned value'`; returns the count; one audit row `aetValue`/`aoUpdate` per value `Confirmed planned value <title>`; refuses a signed item (same check as AddValue).
- Drift check: Planned values are skipped like Manual values.
- Desktop value dialog: describes Planned as `Planned (from an experiment series, not confirmed)`; changing the number of a Planned value saves it as Manual (same mechanism as the Derived rule at `dlg_Value.pas:270`).
- MCP: outputs show `"source_kind":"Planned"`; `add_value` with `source_kind` `Planned` is refused (error lists the accepted kinds without Planned); `update_value` and `remove_value` on a Planned value are refused with `Planned values are confirmed or corrected in the desktop.`; value-issue rows include Planned values like Manual ones.

- [ ] **Step 1: Write the failing tests:** desktop `PlannedSourceNameAndParse`, `PlannedRejectsReaderFields`, `ConfirmPlannedValuesConvertsAndAudits` (2 planned + 1 manual → returns 2, both Manual with the note, 2 audit rows, manual untouched), `ConfirmRefusedOnSignedItem`, `DriftSkipsPlanned`, `ValueDialogEditMakesPlannedManual`; MCP `AddValueRefusesPlanned`, `UpdateAndRemoveRefusePlanned`, `GetValuesShowsPlanned`.
- [ ] **Step 2: Run** `DesktopRegressionTests` and `AuthorizationTests`. Expected: failures.
- [ ] **Step 3: Implement.** Grep `Audit` and `SourceKind` once more for consumers the fact list missed; handle each.
- [ ] **Step 4: Run** both suites. Expected: all pass.
- [ ] **Step 5: Commit** `feat(series): planned value source kind`.

### Task 3: Plan, points, make, link in `TSeriesModel`

**Files:**
- Modify: `ELN.Model/unit_SeriesModel.pas`
- Test: `ELN.Community.Tests/test_SeriesModel.pas`

**Interfaces (consumes):** Task 1 entities; Task 2 `TValueSourceInfo.Planned`; existing `RequireRead/RequireWrite/RequireOpen`, `MarkModified`, `Unwind`, `RecordAudit(aetSeries, ...)`.

**Interfaces (produces):** `TSeriesFactorSpec`, `TSeriesFixedSpec`, `TSeriesPlan` and `TSeriesPoint` are declared in `ELN.Model/unit_SeriesTable.pas` (the builder in Task 4 needs `TSeriesFixedSpec`, and the table unit must not depend on the model unit); the rest in `unit_SeriesModel.pas`.
```pascal
type
  TSeriesFactorSpec = record ValueTypeId: Integer; RangeMin, RangeMax: Nullable<Double>; end;
  TSeriesFixedSpec = record ValueTypeId: Integer; Value, Tol: Double; end;
  TSeriesPlan = record
    Factors: TArray<TSeriesFactorSpec>;      { order = SortOrder }
    Fixed: TArray<TSeriesFixedSpec>;
    Responses: TArray<Integer>;              { TEST_RESULT value type ids }
    TargetFolderId: Integer;                 { 0 = project root }
  end;
  TSeriesPoint = TArray<Double>;              { one level per factor, factor order }
  TSeriesSlotInfo = record SlotId: Integer; Levels: TSeriesPoint; Origin: TSeriesSlotOrigin; ValidItemId: Integer; end;
  TSeriesPlanInfo = record Plan: TSeriesPlan; Slots: TArray<TSeriesSlotInfo>; end;
  TSeriesDepositionDraft = record Title, Description, Properties: string; ActionTypeId, EquipmentId: Integer; end;
  TSeriesLinkOutcome = (sloLinked, sloNewPoint, sloNoValue, sloAmbiguousValue, sloSlotTaken, sloAlreadyMember, sloOutsideRange, sloNotRoot);
  TSeriesLinkLine = record ItemId: Integer; Outcome: TSeriesLinkOutcome; SlotId: Integer; Levels: TSeriesPoint; end;
```
- `constructor Create(AManager: TObjectManager; const AAccess: IProjectAccessPolicy; AVia: TSeriesCreatedVia = scvDesktop);`
- `function CreateSeries(AUser: TUser; AProjectId: Integer; const ATitle, APurpose: string; const APlan: TSeriesPlan; const APoints: TArray<TSeriesPoint>): Integer;` — status `ssActive` when `FVia = scvDesktop`, `ssDraft` when `scvMcp`; `CreatedVia = FVia`; points get `ssoPlanned`. Replaces the phase 1 `CreateSeries` signature; update every caller.
- `function GetPlan(AUser: TUser; AId: Integer): TSeriesPlanInfo;`
- `procedure SavePlan(AUser: TUser; AId: Integer; const APlan: TSeriesPlan);` — Draft/Active only. When the series has points, the factor list (value type ids and order) must not change: raise `ESeriesError('Remove all points before you change the factors.')`. A range that would exclude an existing point raises `ESeriesError` naming the point (`Point 300 W is outside the new range.`). Responses are stored as `SeriesColumn` rows (`TEST_RESULT`, `SourceKey ''`, role `scrResponse`) through the upsert below; a response removed from the plan has its column role set back to `scrShown`.
- `procedure SetColumnRole(AUser: TUser; AId: Integer; ARecType: TRecType; AValueTypeId: Integer; const ASourceKey: string; ARole: TSeriesColumnRole);` — upsert one pref, keeps the others. `SaveColumnPrefs` is removed; the VM switches to this (fixes the phase 1 deferred minor).
- `function AddPoints(AUser: TUser; AId: Integer; const APoints: TArray<TSeriesPoint>; const AReason: string): TArray<Integer>;` — each point needs one level per factor; a point equal to an existing one (same levels within 1e-9 relative) or outside a set range is refused (whole call). Origin `ssoPlanned` while Draft, `ssoAdded` while Active.
- `function FillGrid(AUser: TUser; AId: Integer; const ALevels: TArray<TArray<Double>>): TArray<Integer>;` — adds every missing combination (one list per factor), same rules.
- `procedure RemovePoint(AUser: TUser; AId, ASlotId: Integer);` — refused when the slot has any member: `Unlink the depositions of this point first.`
- `procedure Start(AUser: TUser; AId: Integer);` — Draft→Active; raises `ESeriesError('A series is started in the desktop.')` when `FVia = scvMcp`.
- `function DefaultDepositionTitle(AUser: TUser; AId, ASlotId: Integer): string;` — `<series title> <level> <units>[, <level> <units>]`, levels with `FloatToStr(..., Invariant)`, e.g. `Ti rate 200 W`.
- `procedure DepositionDefaults(AUser: TUser; AId: Integer; out AActionTypeId, AEquipmentId: Integer);` — from the most recently added valid member's item; 0 when none.
- `function MakeDeposition(AUser: TUser; AId, ASlotId: Integer; const ADraft: TSeriesDepositionDraft): Integer;` — Active only; refused if the slot has a valid member. One transaction: root item (`Level Proc`, `Type_ Synthesis`, series `ProjectId`, `TargetFolderId`, draft fields, `CreatedBy`), one `EXP_CONDITION` value per slot level (Tol 0) and per fixed condition (its Tol), each `TValueSourceInfo.Planned('Planned value from series <title>')` and description `Planned value from series <title>`, and a valid `SeriesMember` with `SlotId`. Returns the new item id. Audit on the series and `aetItem` create.
- `procedure LinkToSlot(AUser: TUser; AId, ASlotId, AItemId: Integer);` — Active only; item rules as phase 1 `AddMembers` (exists, non-deleted, root, not Folder, same project); refused if the slot has a valid member or the item already has any membership in this series. Writes no values.
- `function PreviewLinkByValues(AUser: TUser; AId: Integer; const AItemIds: TArray<Integer>): TArray<TSeriesLinkLine>;` and `function LinkByValues(AUser: TUser; AId: Integer; const AItemIds: TArray<Integer>; ACreateMissing: Boolean): TArray<TSeriesLinkLine>;` — per item, for each factor, the `EXP_CONDITION` values of that value type on the root or its non-deleted descendants; none → `sloNoValue`, more than one distinct → `sloAmbiguousValue`; then the slot whose level equals within `max(Tol of the value, 1e-9 * max(1, |level|))` for every factor: free → `sloLinked`, taken → `sloSlotTaken`; no slot → `sloNewPoint` (outside range → `sloOutsideRange`). `LinkByValues` applies `sloLinked` lines, and `sloNewPoint` lines only when `ACreateMissing` (new `ssoAdded` slot with reason `Linked from existing deposition`), in one transaction; returns the final lines. Two items mapping to the same free slot: the first in input order links, the second gets `sloSlotTaken`.
- `procedure MarkFailed(AUser: TUser; AId, AItemId: Integer; const AReason: string);` — valid → failed; empty reason refused.
- `procedure Unlink(AUser: TUser; AId, AItemId: Integer);` — removes the membership (valid or failed); replaces `RemoveMember` (rename all callers).
- `TSeriesSummary` gains `PointCount, MeasuredCount: Integer` (fixed number of statements for `ListSeries`).
- `AddMembers` stays until Task 8 removes it with its last caller; slot-less members are not rows (they go to `Excluded`).

- [ ] **Step 1: Write the failing tests** (names; each asserts the stated rule with concrete values — factor Power `W` with points 100/200/300, fixed Ar flow 20 sccm Tol 1, response Thickness `nm`): `CreateWithPlanMakesPlannedPoints`, `McpCreateIsDraftAndCannotStart`, `SavePlanRefusesFactorChangeWithPoints`, `SavePlanRefusesRangeExcludingPoint`, `SetColumnRoleKeepsOtherPrefs`, `AddPointRefusesDuplicateAndOutsideRange`, `AddPointWhileActiveIsAdded`, `FillGridAddsMissingCombinations` (2 factors 2×2, one existing → 3 added), `RemovePointRefusedWithMember`, `DefaultDepositionTitleFormatsLevels` (`'Ti rate 200 W'`), `MakeDepositionWritesPlannedValuesAndMember` (root Proc Synthesis in target folder; Power 200 and Ar flow 20 ± 1 with `vskPlanned`; member valid on that slot), `MakeRefusedWhenSlotHasValidMember`, `MakeRefusedWhileDraft`, `LinkRefusedWhenSlotHasValidMember`, `LinkByValuesMatchesWithinTolerance` (199.97 ± 0.1 → 200 point), `LinkByValuesReportsNoValueAndAmbiguous`, `LinkByValuesCreatesMissingOnlyWhenAsked`, `LinkByValuesSecondItemSameSlotTaken`, `MarkFailedFreesSlot` (then a second make succeeds), `UnlinkRemovesMembership`, `ListSeriesCountsPointsAndMeasured`. Migrate existing phase 1 model tests from `AddMembers` to `MakeDeposition`/`LinkToSlot` where they test table content.
- [ ] **Step 2: Run** `DesktopRegressionTests`. Expected: failures.
- [ ] **Step 3: Implement.** Writes follow the existing transaction pattern; every write marks the series modified.
- [ ] **Step 4: Run** `DesktopRegressionTests`, `AuthorizationTests`. Expected: pass (update compile-time callers of the renamed/changed signatures: VM, frame, MCP, tests).
- [ ] **Step 5: Commit** `feat(series): plan, points, make and link in the series model`.

### Task 4: Point-based table builder

**Files:**
- Modify: `ELN.Model/unit_SeriesTable.pas`, `ELN.Model/unit_SeriesModel.pas` (`BuildTable` feeds the new inputs)
- Test: `ELN.Community.Tests/test_SeriesTable.pas`, `test_SeriesModel.pas`

**Interfaces (produces):**
- `TSeriesHit` gains `Planned: Boolean` (`SourceKind = vskPlanned`).
- `TSeriesPlannedLevel = record ValueTypeId: Integer; Value: Double; end;` `TSeriesRowState = (srsPlanned, srsDeposited, srsMeasured, srsFailed);`
- `TSeriesRowInput` gains `SlotId: Integer; Origin: TSeriesSlotOrigin; Levels: TArray<TSeriesPlannedLevel>; HasMember: Boolean` (a slot without a valid member is one input row with `HasMember = False`, `ItemId = 0`).
- `TSeriesCell` gains `HasPlanned: Boolean; PlannedValue: Double; Deviation: Boolean`.
- `TSeriesTableRow` gains `SlotId, Origin, State`.
- New parameter: `BuildSeriesTable(ARows, AHits, ATypes, ASources, APrefs, const AFixed: TArray<TSeriesFixedSpec>; AIncludeFailed)`.
- Rules (spec §8.6, §8.7):
  - A pref with role Varied, Fixed or Response creates its column (`SourceKey ''`) even when no row has a hit. The model passes factors as Varied (`EXP_CONDITION`), fixed conditions as Fixed (`EXP_CONDITION`), responses as Response (`TEST_RESULT`); these roles win over stored prefs for those keys.
  - A factor cell with no hit shows the slot level: `HasPlanned = True`, `PlannedValue = level`.
  - State: no member → `srsPlanned`; failed member row → `srsFailed`; valid member with every Response column holding at least one non-planned hit (for a split response, the stored `SourceKey` choice, else any source) → `srsMeasured`; else `srsDeposited`.
  - Deviation: on a member row, a factor cell whose non-planned hit differs from the slot level, or a fixed cell whose non-planned hit differs from the plan value, by more than the tolerance (plan Tol if > 0, else the hit's Tol, else exact). Planned hits never deviate.
  - Rows sort by levels in factor order (ascending), then the failed attempts of that slot after its row (when included). Slot-less members are not rows.
  - Keep the phase 1 column split and indexing rules.

- [ ] **Step 1: Write the failing tests:** `PlannedRowShowsLevels`, `PlanColumnsExistWithoutHits`, `StateDepositedVsMeasured`, `PlannedHitIsNotPresentForMeasured`, `DeviationUsesValueTolerance` (factor 195 ± 0.1 vs 200 → flagged; 199.97 ± 0.1 → not), `FixedDeviationUsesPlanTolerance`, `RowsSortByLevels` (points added 300, 100, 200 → rows 100, 200, 300), `FailedAttemptFollowsItsPoint`. Adjust existing builder tests to the new signature without weakening them.
- [ ] **Step 2: Run** `DesktopRegressionTests`. Expected: failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `DesktopRegressionTests`. Expected: pass.
- [ ] **Step 5: Commit** `feat(series): point-based series table`.

### Task 5: Export rules for planned data

**Files:** Modify `ELN.Model/unit_SeriesExport.pas`; Test `ELN.Community.Tests/test_SeriesExport.pas`.

- Rows with `State = srsPlanned` are not exported. A planned hit is exported as an empty field (its `±` field empty). A cell with only `HasPlanned` is empty. Everything else as phase 1.

- [ ] **Step 1: Write the failing tests:** `PlannedRowsNotExported`, `PlannedHitsExportEmpty`.
- [ ] **Step 2–4: Run, implement, run** `DesktopRegressionTests`. Expected: fail, then pass.
- [ ] **Step 5: Commit** `feat(series): export skips unconfirmed planned data`.

### Task 6: MCP plan tools and table fields

**Files:** Modify `ELN.MCPServer/unit_ToolsSeries.pas`, `ELN.Community.Tests/test_ValueSourceTools.pas`, `ELN.Community.Tests/unit_ReadToolAllowlist.pas` (no change for write tools), `ELN.Community.Tests/test_ReadOnlySweep.pas` (seed through `CreateSeries` with a plan), `ELN.Desktop/Assets/Runtime/Help/MCP.html`.

**Interfaces (produces):**
- `get_series_table` adds per row `slot_id`, `state` (`Planned|Deposited|Measured|Failed`), `origin` (`Planned|Added`), per cell `planned_value` (only when `HasPlanned`) and `deviation` (only when true), per hit `planned` (only when true); adds top-level `plan` = `{factors:[{value_type_id,title,units,range_min,range_max}], fixed:[{value_type_id,title,units,value,tol}], responses:[value_type_id], target_folder_id}`.
- `create_series` (`taWrite`, `tscProjectScoped`): `project_id` (req), `title` (req), `purpose`, `factors`, `fixed`, `responses`, `points` (array of arrays of numbers), `target_folder_id` → `{series_id, status:"Draft"}`. Model created with `scvMcp`.
- `update_series_plan` (`taWrite`): `series_id` (req) and any of `purpose`, `factors`, `fixed`, `responses`, `target_folder_id`, `add_points`, `reason`. Draft or Active; refusals from the model map to `[refusal]`.
- Write access through `CheckProjectWriteAccess`; out-of-scope and missing series give the same `SOutOfScope` refusal as `get_series_table`.

- [ ] **Step 1: Write the failing tests:** `CreateSeriesIsDraftViaMcp`, `UpdateSeriesPlanAddsPoints`, `PlanToolsRefusedInReadOnlyMode`, `GetSeriesTableShowsPlanAndStates` (planned row: `state` Planned, `planned_value` 200; made row after model `MakeDeposition`: hit `planned` true).
- [ ] **Step 2: Run** `AuthorizationTests`. Expected: failures.
- [ ] **Step 3: Implement**; update `MCP.html`.
- [ ] **Step 4: Run** `AuthorizationTests`, `DesktopRegressionTests`; build `CommunityMCP`. Expected: pass, clean build.
- [ ] **Step 5: Commit** `feat(series): MCP plan tools`.

### Task 7: Plan editor and point-based Series view

**Files:**
- Create: `ELN.Desktop/Dialogs/Series/dlg_SeriesPlan.pas/.dfm`, `ELN.Desktop/Dialogs/Series/dlg_SeriesPlanEntry.pas/.dfm`
- Modify: `ELN.Desktop/ViewModels/unit_SeriesVM.pas`, `ELN.Desktop/Views/frame_Series.pas/.dfm`, `ELN.Desktop/Assets/Runtime/Help/Series.html` (rewrite: plan a series, make or link depositions, confirm planned values, add points, read the table, plot, export)

**Layout and behaviour:**
- `TdlgSeriesPlan.Execute(AManager: TObjectManager; AProjectId: Integer; var ATitle, APurpose: string; var APlan: TSeriesPlan; var ALevelsText: string; AHasPoints: Boolean): Boolean` — fields Title, Purpose, Target folder (combo: `(project root)` + the project's folders), three `TListView`s with Add / Edit / Remove buttons: **Factors** (value type, range), **Fixed conditions** (value type, value, tol), **Responses** (value type). Add/Edit open `dlg_SeriesPlanEntry` (value type combo filtered to the needed fields, numeric edits validated with the invariant and the user's decimal separator). With one factor and no points yet, a **Levels** edit (`100; 200; 300`) creates the initial points. With points, the factor list is read-only and a note says `Remove all points to change the factors.` A two-factor plan shows **Fill grid** (one levels edit per factor).
- **New series** opens the plan dialog, then `CreateSeries`. **Edit plan...** opens it with `GetPlan` and calls `SavePlan`. **Add point...** asks for one level per factor and a reason (`AddPoints`). **Start** is shown for Draft series.
- Table columns: **Point** (levels with units, an `added` mark for `ssoAdded`), **State** (`planned`, `deposited`, `measured`, `failed`), then the data columns. Planned values: grey italic with the text `planned`; `HasPlanned` cells show the level in grey; deviation cells get a warning mark and the hint `Differs from the plan (<planned>)`.
- Table context menu (DFM `TPopupMenu`): **Make deposition...** (planned row), **Link existing deposition...** (planned row; `TdlgItemPicker.Execute`), **Open deposition** (member row), **Confirm planned values** (member row with planned hits; `TItemModel.ConfirmPlannedValues`), **Mark failed...** (valid member; reason via the existing input pattern), **Unlink deposition** (member row, confirmation), **Remove point** (planned row, confirmation). Double-click: planned row → Make deposition; member row → open the item.
- **Make deposition...**: build a transient `TItem` with `DefaultDepositionTitle`, `Synthesis`, `Proc`, and `DepositionDefaults`, show `ShowActionDialog(dmNew, Item, [TItemLevel.Proc])`; on OK pass its fields as `TSeriesDepositionDraft` to `MakeDeposition`; free the transient item in `finally`.
- Toolbar keeps series-level commands only: New series, Edit plan..., Add point..., Start / Close / Reopen, Abandon..., Refresh, Copy table, Save CSV..., Show failed, Unlink excluded. Use `AutoSize` on the toolbar panels so no button is clipped at any width.
- Series list columns: Series, Status, Progress (`<measured>/<points> measured`).
- Plot: rows with members only; planned hits not plotted; note `<n> point(s) wait for confirmed values.` when any member row has planned hits in X or Y.
- Empty state: a series with no points shows `This series has no points. Click Edit plan... to add factors and levels.`

- [ ] **Step 1: Implement** VM (new commands mirror the model API; `SetColumnRole` uses the model upsert), dialogs, frame, help.
- [ ] **Step 2: Build** `CommunityDesktop`. Expected: success, no new warnings.
- [ ] **Step 3: Throwaway check (not committed):** drive the VM over a scratch notebook: create a plan with Power 100/200/300 W, Ar flow fixed, Thickness response; make a deposition for 200 W; confirm its values; add a Thickness result; add point 250 W; check rows, states and export text. Delete the check afterwards and paste its output into the report.
- [ ] **Step 4: Run** `DesktopRegressionTests`. Expected: pass.
- [ ] **Step 5: Commit** `feat(series): plan editor and point-based series view`.

### Task 8: Item tree, removal of free membership

**Files:**
- Create: `ELN.Desktop/Dialogs/Series/dlg_SeriesLink.pas/.dfm`
- Delete: `ELN.Desktop/Dialogs/Series/dlg_SeriesPick.pas/.dfm`
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas/.dfm` (`miItemAddToSeries`, `miBatchAddToSeries`, handler `:1824`, `UpdateSeriesLine`), `ELN.Desktop/ViewModels/unit_ItemTreeBatch.pas` (`boSeries` → `boSeriesLink`, same rule), `ELN.Model/unit_SeriesModel.pas` (delete `AddMembers`, `TSeriesAddResult`), `unit_SeriesVM.pas` (delete `AddItems`), tests that still use `AddMembers`, `ELN.Desktop/Assets/Runtime/Help/Items.html`, `Series.html`

**Behaviour:**
- **Link to plan point...** (single and multi root selection, rule as phase 1 `boSeries`): `TdlgSeriesLink.Execute(AManager, AUser, AAccess, AProjectId, const AItemIds): Integer` (returns the series id or 0). The dialog lists the project's Active series; for the chosen series it shows `PreviewLinkByValues` as a list (`item → 200 W`, `item → new point 250 W`, `item: no Power value`, ...), with a check box `Add new points for depositions that match no point` (default off). For a single item it also offers a point combo to choose a free point by hand (then `LinkToSlot`). OK applies (`LinkByValues` or `LinkToSlot`) and opens the series.
- **Confirm planned values** in the item context menu: enabled for a single item where `HasPlannedValues`; calls `ConfirmPlannedValues`, refreshes.
- Detail line: `Series: <title> (<levels with units>)` per membership, failed ones with `, failed`.
- Remove every remaining use of `AddMembers`, `AddItems`, `dlg_SeriesPick`, `miAddToSeries*`.

- [ ] **Step 1: Implement**, including the help updates (Items.html multi-selection list names **Link to plan point...**).
- [ ] **Step 2: Build** `CommunityDesktop`; grep shows no `AddMembers`, `AddToSeries`, `dlg_SeriesPick` in source.
- [ ] **Step 3: Throwaway check (not committed):** three root depositions with Power 100, 200, 260 W against a 100/200/300 plan: preview gives linked, linked, new point; apply with new points on gives a 4-point table. Delete the check; paste the output in the report.
- [ ] **Step 4: Run** `DesktopRegressionTests`, `AuthorizationTests`. Expected: pass. Byte-check BOM and CRLF of `frame_ItemTree.pas`.
- [ ] **Step 5: Commit** `feat(series): link depositions to plan points from the item tree`.

### Task 9: Final verification

- [ ] **Step 1: Run** `DesktopRegressionTests`, `AuthorizationTests`, `GateTests`, `NotebookTests` (`-RunTests`). Expected: all pass.
- [ ] **Step 2: Build** `CommunityDesktop`, `CommunityMCP`. Expected: success; only the 4 known warnings (`unit_ItemModel.pas` H2077, `unit_LocalNotebookStorage.pas` W1002 ×3).
- [ ] **Step 3: Owner GUI check** (owner, not agents): restore the notebook copy from its `.format5-backup`, upgrade it with this build, then: New series → plan with three levels → Make deposition for one point → add a thickness measurement → Confirm planned values → plot and Copy table; Link to plan point... with an old deposition; Add point 250 W; Mark failed and make again.
