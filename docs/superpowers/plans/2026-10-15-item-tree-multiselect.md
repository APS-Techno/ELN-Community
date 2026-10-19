# Items Tree Multiple Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user select several nodes in the Items tree and run Delete, Extract values, Move to, Tags, Export files and Drag to the Projects panel on all of them, with one confirmation and one summary.

**Architecture:** A new VCL-free unit `ELN.Model/ViewModels/unit_ItemTreeBatch.pas` holds the batch rules: selection reduction, action availability, a read-only `Plan…` step that lists targets and skip reasons, and an `Execute…` step that calls the existing single-target APIs and collects failures. `frame_ItemTree` collects the selected nodes, shows one dialog, calls the batch unit, refreshes one time and shows the summary. Single-node actions use the same plan and execute code with one target.

**Tech Stack:** Delphi 13, VCL, VirtualTreeView, TMS Aurelius, DUnitX, Raize. Build helper `tools/build-community.ps1`, Win32 Debug.

**Spec:** `docs/superpowers/specs/2026-10-15-item-tree-multiselect-design.md`

## Global Constraints

- Repository: standalone Community `D:/APS/ELN/APS-ELN-Community` only. Do not edit `APS-ELN-Commercial` or its `Community/` pin.
- No commit, push or tag. The user commits.
- Read `AGENTS.md`, `ELN.Desktop/AGENTS.md`, `ELN.Model/AGENTS.md` and `ELN.Community.Tests/AGENTS.md` before you edit. Load the `delphi-development` skill before Delphi edits.
- Comment policy, verbatim: It is strictly PROHIBITED to post comments based on the principle that "a comment is useful if the information is accurate and relevant." Adopt the following approach: comments are not allowed by default; they must prove their right to exist. Pass this same briefing on to subagents verbatim.
- Keep `.pas`/`.dfm` pairs, published DFM event handlers, CRLF, and any existing UTF-8 BOM. Put new controls and menus in the DFM, not in code.
- `unit_ItemTreeBatch.pas` gets no `.dpk` or `.dproj` entry. The hosts find `ELN.Model\ViewModels` through their search paths, as for `unit_ItemTreeVM.pas`.
- A new test unit goes into the `uses` clause of `ELN.Community.Tests/DesktopRegressionTests.dpr` and into the `<ItemGroup Condition="'$(MainSource)'=='DesktopRegressionTests.dpr'">` of `ELN.Community.Tests/CommunityStorageTests.dproj`.
- Tests use a new GUID-rooted synthetic notebook. Copy the `Setup`/`TearDown` of `test_SharedDesktopMutations.pas` (lines 55-83). Never open an existing user notebook.
- Test command, from the repository root: `pwsh -NoProfile -File tools/build-community.ps1 -Target DesktopRegressionTests -RunTests`. It passes when the script exits with code 0 and the DUnitX log shows no failed test.
- Before each `CommunityDesktop` build, increase `VerInfo_Build` in `ELN.Community.Desktop/ELNCommunity.dproj` by 1 and update `ProductVersion` and `FileVersion` in `VerInfo_Keys` and the `## Source version` heading of `README.md` to the same value. The current value is `2.2.0.12`. Test targets do not change the version.
- If Win32 Debug is blocked by missing external packages, stop and report it. Do not change the external package setup and do not switch to Release.

## Review Focus

1. **A very large selection.** The user selects 300 nodes and many are skipped. The confirmation must stay readable: at most 20 reason lines, then `...and N more`. Test: Task 1 `FormatSkipsCapsLines`.
2. **An item and its own file or child are both selected.** Delete must process the item once and must not try to delete its file or child a second time. Test: Task 1 `TopLevelDropsDescendantsAndOwnedNodes`, Task 2 `DeleteItemWithSelectedOwnFile`.
3. **A signature added after the tree was loaded.** The VM signed cache (`FVM.IsItemSigned`) can be stale. The plan must use `IsItemSignedCheck` and skip the target. Test: Task 2 `PlanDeleteSeesFreshSignature`.
4. **Extract values: other files of the same reader differ.** A file can lack a chosen value, or a value can fail its range check. These values must be skipped and counted, not written. Test: Task 5 `WriteChosenValuesSkipsMissingAndIssues`.
5. **Export of two files with the same title.** The second copy must get ` (2)` and must not overwrite the first one, also when the folder already has the name. Test: Task 4 `ExportSameTitleTwice`.

---

### Task 1: Batch unit core

**Files:**
- Create: `ELN.Model/ViewModels/unit_ItemTreeBatch.pas`
- Create: `ELN.Community.Tests/test_ItemTreeBatch.pas`
- Modify: `ELN.Community.Tests/DesktopRegressionTests.dpr`, `ELN.Community.Tests/CommunityStorageTests.dproj` (register the test unit)
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas:597-626` (remove `SubtreeItemIds`; its caller at line 3652 uses the moved function)

**Interfaces:**
- Produces (interface section of `unit_ItemTreeBatch`):

```pascal
type
  TBatchTargetKind = (btItem, btFile, btNote);
  TBatchKinds = set of TBatchTargetKind;
  TBatchOperation = (boDelete, boExtract, boMove, boTags, boExport, boDrag);

  TBatchTarget = record
    Kind: TBatchTargetKind;
    Item: TItem;
    AFile: TFile;
    Entry: TLabEntry;
    function Title: string;
    function Key: string;
    class function ForItem(AItem: TItem): TBatchTarget; static;
    class function ForFile(AFile: TFile; AOwner: TItem): TBatchTarget; static;
    class function ForNote(AEntry: TLabEntry; AOwner: TItem): TBatchTarget; static;
  end;

  TBatchSkip = record
    Target: TBatchTarget;
    Reason: string;
  end;

  TBatchPlan = record
    Targets: TArray<TBatchTarget>;
    Skipped: TArray<TBatchSkip>;
  end;

  TBatchResult = record
    Done: TArray<TBatchTarget>;
    Failed: TArray<TBatchSkip>;
  end;

  TItemTreeBatch = class
  public
    constructor Create(AModel: TDataModel; AVM: TItemTreeVM);
    class function KindsOf(const Targets: TArray<TBatchTarget>): TBatchKinds; static;
    class function Allows(Op: TBatchOperation;
      const Targets: TArray<TBatchTarget>): Boolean; static;
    class function FormatSkips(const Skips: TArray<TBatchSkip>;
      MaxLines: Integer = 20): string; static;
    class function UniqueTargetPath(const Folder, FileName: string): string; static;
    function TopLevel(const Targets: TArray<TBatchTarget>): TArray<TBatchTarget>;
  end;

function SubtreeItemIds(Manager: TObjectManager; Root: TItem): TArray<Integer>;
```

- `Item` is the item for `btItem` and the owning item for `btFile` and `btNote`.
- `Key` returns `'I:<Item.Id>'`, `'F:<AFile.Id>'` or `'N:<Entry.Id>'`. Task 6 uses it to restore the selection.
- `Title` returns the item title, `AFile.Title + AFile.FileType.Ext`, or the `TProtocol` title of the entry.

- [ ] **Step 1: Write the failing tests** in `test_ItemTreeBatch.pas`, fixture `TItemTreeBatchTests` with the `test_SharedDesktopMutations` setup plus `FBatch := TItemTreeBatch.Create(Model, FVM)`.

```pascal
[Test] procedure TopLevelDropsDescendantsAndOwnedNodes;
  // Root -> Child -> Grandchild; File F on Root; Note N on Child; Other root item O.
  // TopLevel([Child, F, Root, Grandchild, N, O]) = [Root, O], in input order.
[Test] procedure AllowsFollowsSelectionRules;
  // boDelete [item, file, note] -> True
  // boExtract [file, file] -> True;  [file, item] -> False
  // boMove [item, item] -> True; [file, file] -> True; [item, file] -> False
  // boTags [item, folder item] -> True; [item, note] -> False
  // boExport [file, file] -> True; [file, note] -> False
  // boDrag [root item, root item] -> True; [root item, child item] -> False
  // any operation with an empty array -> False
[Test] procedure FormatSkipsCapsLines;
  // 25 skips with reasons 'R1'..'R25' and MaxLines = 20:
  // 21 lines; line 1 = '"<title>": R1'; line 21 = '...and 5 more'
[Test] procedure UniqueTargetPathAddsCounter;
  // empty temp folder: 'a.txt' -> Folder\a.txt
  // folder with a.txt: -> Folder\a (2).txt; with a.txt and a (2).txt: -> Folder\a (3).txt
```

- [ ] **Step 2: Run the tests and see them fail**

Run the test command. Expected: compile error `F1026 File not found: 'unit_ItemTreeBatch.pas'`.

- [ ] **Step 3: Implement Task 1 in `unit_ItemTreeBatch.pas`**

`TopLevel` keeps a target only if no other target is its ancestor. For `btFile` and `btNote`, the owning item and all its ancestors count. Walk `Item.Parent` with `FModel.Manager.Find<TItem>` until `Parent = 0`. `FormatSkips` writes one line per skip, `'"' + Title + '": ' + Reason`. Move `SubtreeItemIds` from the frame without changes, except that it takes `Manager` instead of using `Model.Manager`. Update the call at `frame_ItemTree.pas:3652` to `SubtreeItemIds(Model.Manager, Root)` and add `unit_ItemTreeBatch` to the frame's implementation `uses`.

- [ ] **Step 4: Run the tests and see them pass**

Run the test command. Expected: exit code 0, the 4 new tests pass.

---

### Task 2: Delete plan and execution

**Files:**
- Modify: `ELN.Model/ViewModels/unit_ItemTreeBatch.pas`
- Modify: `ELN.Model/unit_ItemModel.pas:87` and its implementation at line 426 (`RemoveEntry` returns `Boolean`)
- Modify: `ELN.Model/ViewModels/unit_ItemTreeVM.pas:96` and its implementation near line 419 (`DeleteEntry` returns `Boolean`)
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas:1052` (adjust the call; Task 7 replaces this code)
- Test: `ELN.Community.Tests/test_ItemTreeBatch.pas`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:

```pascal
function PlanDelete(const Targets: TArray<TBatchTarget>): TBatchPlan;
function ExecuteDelete(const Plan: TBatchPlan): TBatchResult;
function DescendantCount(const Plan: TBatchPlan): Integer;
class function PreviewStoragePath(ItemId: Integer; FileId: Int64): string; static;
```

- `TItemModel.RemoveEntry(Entry: TLabEntry; var Item: TItem; UserId: Integer): Boolean` returns `False` when the item is signed or `SafeFlush` fails.
- `TItemTreeVM.DeleteEntry(Entry: TLabEntry; var ParentItem: TItem): Boolean` calls `DoChanged` only on success. Commercial's `ELN.Tests/test_ItemTreeVM.pas:869` asserts one change event on success; this stays true.

Plan rules, in this order. The first rule that applies gives the reason:

| Kind | Condition | Reason text |
|---|---|---|
| any | `not FModel.Access.CanWrite(FModel.Manager, FModel.User, Item.ProjectID)` | `You cannot change this project.` |
| btItem | `FModel.Items.FindDeleteBlocker(Item) <> ''` | the blocker text |
| btFile, btNote | `IsItemSignedCheck(FModel.Manager, Item.Id)` | `Its item is signed.` |

Failure texts in `ExecuteDelete`:

| Kind | Condition | Text |
|---|---|---|
| btItem | `SoftDeleteItemTree` returns `False` | `The item was changed by another session. Refresh and try again.` |
| btFile | `RemoveFile` returns `False` | `The file was not deleted. It may be signed or changed by another session.` |
| btNote | `DeleteEntry` returns `False` | `The note was not deleted. It may be signed or changed by another session.` |
| any | exception other than `EAbort` | `E.Message` |

`EAbort` is re-raised and stops the loop. Every `Execute…` function in Tasks 3 and 4 uses the same exception rule.

- [ ] **Step 1: Write the failing tests**

```pascal
[Test] procedure PlanDeleteSkipsBlockedTargets;
  // A signed (SignItem), B plain, file FA on A, note NB on B.
  // PlanDelete([A, B, FA, NB]): Targets = [B, NB];
  // Skipped[0].Reason starts with 'Cannot delete item "A"'; Skipped[1].Reason = 'Its item is signed.'
[Test] procedure PlanDeleteSeesFreshSignature;
  // FVM.LoadItemData (fills the VM signed cache), then SignItem(B).
  // PlanDelete([file on B]).Skipped has 1 entry with 'Its item is signed.'
[Test] procedure ExecuteDeleteProcessesAllKinds;
  // items X, Y (Y has child Y1); file FZ on Z with stored bytes; note NZ on Z.
  // ExecuteDelete(PlanDelete([X, Y, FZ, NZ])): Length(Done) = 4, Failed empty;
  // a fresh TObjectManager sees X, Y, Y1 IsDeleted = True; no TFile row FZ; no TProtocol row NZ;
  // Model.Storage.Exists(<old FZ path>) = False
[Test] procedure DeleteItemWithSelectedOwnFile;
  // ExecuteDelete(PlanDelete(FBatch.TopLevel([X, file of X]))): Length(Done) = 1, Failed empty
[Test] procedure ExecuteDeleteContinuesAfterFailure;
  // Plan built for [P, Q]; then SignItem(P); ExecuteDelete(Plan):
  // Failed[0].Target = P with the item text; Done = [Q]
[Test] procedure DescendantCountCountsSubtrees;
  // Y has children Y1, Y2; Y1 has Y11; X has none: DescendantCount(PlanDelete([X, Y])) = 3
```

- [ ] **Step 2: Run the tests and see them fail.** Expected: `E2003 Undeclared identifier: 'PlanDelete'`.
- [ ] **Step 3: Implement** `PlanDelete`, `ExecuteDelete`, `DescendantCount` and `PreviewStoragePath` (`Format('previews/[1000]/%.*d_%.*d.png', [5, ItemId, 5, FileId])`). For `btFile`, read `StringReplace(FModel.GetFileName(AFile.Id), '\', '/', [rfReplaceAll])` before `RemoveFile`, then call `FModel.Storage.DeleteFile` for the file path and the preview path. Local preview files stay a frame task (Task 7). `DescendantCount` sums `Length(SubtreeItemIds(...)) - 1` for the `btItem` targets. Change `RemoveEntry` and `DeleteEntry` to functions and adjust `frame_ItemTree.pas:1052`.
- [ ] **Step 4: Run the tests and see them pass.**

---

### Task 3: Move plans and execution

**Files:**
- Modify: `ELN.Model/ViewModels/unit_ItemTreeBatch.pas`
- Test: `ELN.Community.Tests/test_ItemTreeBatch.pas`

**Interfaces:**
- Produces:

```pascal
function PlanMoveItems(const Targets: TArray<TBatchTarget>): TBatchPlan;
function PlanMoveItemsTo(const Plan: TBatchPlan; NewParentId: Integer): TBatchPlan;
function ExecuteMoveItems(const Plan: TBatchPlan; NewParentId: Integer): TBatchResult;
function PlanMoveFiles(const Targets: TArray<TBatchTarget>; NewItemId: Integer): TBatchPlan;
function ExecuteMoveFiles(const Plan: TBatchPlan; NewItemId: Integer): TBatchResult;
```

- `PlanMoveItemsTo` keeps the skips of `Plan` and adds new skips.
- `ExecuteMoveItems` calls `FVM.ReparentItem(Item, NewParentId)`.
- `ExecuteMoveFiles` copies the sequence of `frame_ItemTree.pas:4021-4028` for each file: read the old path, `FModel.Items.MoveFile`, read the new path, then `FModel.Storage.MoveFile` if the paths differ. If the storage move raises, call `MoveFile(AFile, OldItemId, UserId)` to roll back and record `E.Message` as the failure. Do not re-raise.

| Function | Condition | Reason text |
|---|---|---|
| PlanMoveItems | no write access (Task 2 rule) | `You cannot change this project.` |
| PlanMoveItems | `Item.Level = TItemLevel.Folder` | `Folders cannot be moved here.` |
| PlanMoveItems | `IsItemSignedCheck` | `The item is signed.` |
| PlanMoveItemsTo | `NewParentId` is in `SubtreeItemIds(FModel.Manager, Item)` | `The target is inside this item.` |
| PlanMoveItemsTo | `Item.Parent = NewParentId` | `The item is already there.` |
| PlanMoveFiles | no write access | `You cannot change this project.` |
| PlanMoveFiles | owning item signed | `Its item is signed.` |
| PlanMoveFiles | `Item.Id = NewItemId` | `The file is already there.` |
| ExecuteMoveItems | `ReparentItem` returns `False` | `The item could not be moved. It may be signed or changed by another session.` |
| ExecuteMoveFiles | `MoveFile` returns `False` | `The file could not be moved. It may be changed by another session.` |

- [ ] **Step 1: Write the failing tests**

```pascal
[Test] procedure PlanMoveItemsSkipsFolderSignedAndCycle;
  // folder item Fo, signed S, A with child A1, B; target T = A1.
  // PlanMoveItemsTo(PlanMoveItems([Fo, S, A, B]), A1.Id): Targets = [B];
  // reasons in order: folder, signed, inside
[Test] procedure ExecuteMoveItemsReparents;
  // B and C under root, target P: after ExecuteMoveItems, fresh read B.Parent = C.Parent = P.Id
[Test] procedure ExecuteMoveFilesMovesBytes;
  // files F1, F2 with stored bytes on item A; target B.
  // After ExecuteMoveFiles: Done has 2; storage has the bytes at the new GetFileName paths and not at the old ones
[Test] procedure PlanMoveFilesSkipsSameItem;
  // PlanMoveFiles([file on B], B.Id).Skipped[0].Reason = 'The file is already there.'
```

- [ ] **Step 2: Run the tests and see them fail.** Expected: `E2003 Undeclared identifier: 'PlanMoveItems'`.
- [ ] **Step 3: Implement** the five functions.
- [ ] **Step 4: Run the tests and see them pass.**

---

### Task 4: Tags and export execution

**Files:**
- Modify: `ELN.Model/ViewModels/unit_ItemTreeBatch.pas`
- Test: `ELN.Community.Tests/test_ItemTreeBatch.pas`

**Interfaces:**
- Produces:

```pascal
function PlanTags(const Targets: TArray<TBatchTarget>): TBatchPlan;
function CountTagged(const ItemIds: TArray<Integer>; TagId: Integer): Integer;
procedure AssignTagToAll(const ItemIds: TArray<Integer>; TagId: Integer);
procedure UnassignTagFromAll(const ItemIds: TArray<Integer>; TagId: Integer);
function ExecuteExportFiles(const Targets: TArray<TBatchTarget>;
  const Folder: string): TBatchResult;
```

- `PlanTags` skips only targets without write access (`You cannot change this project.`). Signed items keep the current single-item behaviour: tags are allowed.
- `ExecuteExportFiles` resolves each target path with `UniqueTargetPath(Folder, AFile.Title + AFile.FileType.Ext)` immediately before `FModel.Storage.CopyOut`. Thus two files with the same title get different names.

- [ ] **Step 1: Write the failing tests**

```pascal
[Test] procedure TagCountsAndAssignAll;
  // Tag := Model.Tags.AddTag('Synthetic', '#0000FF', Model.User.Id); items A, B, C; AssignTag(A, Tag).
  // CountTagged([A, B, C], Tag) = 1; AssignTagToAll -> 3; UnassignTagFromAll -> 0
[Test] procedure ExportSameTitleTwice;
  // files 'data' (.txt) on items A and B with different bytes; target folder already has data.txt.
  // ExecuteExportFiles: Done has 2; folder has 'data (2).txt' and 'data (3).txt' with the two byte sets;
  // the original data.txt keeps its bytes
```

- [ ] **Step 2: Run the tests and see them fail.** Expected: `E2003 Undeclared identifier: 'CountTagged'`.
- [ ] **Step 3: Implement** the five functions.
- [ ] **Step 4: Run the tests and see them pass.**

---

### Task 5: Split the Extract values dialog

**Files:**
- Modify: `ELN.Desktop/Dialogs/Items/dlg_ExtractValues.pas` (declarations at lines 15-77, `ShowExtractValuesDialog` from line 227)
- Test: `ELN.Community.Tests/test_ValueSourceDesktop.pas` (existing fixture with `Model`, `FItem`, file and value types)

**Interfaces:**
- Produces:

```pascal
type
  TExtractChoice = record
    Name: string;
    Units: string;
    Mapping: TReaderValueResolution;
  end;

function ChooseExtractValues(const KeyValues: TArray<TPluginKeyValue>;
  const ReaderId, Caption: string; const Analysis: IAnalysisKeyValueProvider;
  out Choices: TArray<TExtractChoice>): Boolean;

function WriteChosenValues(const Choices: TArray<TExtractChoice>;
  const KeyValues: TArray<TPluginKeyValue>; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider; SkipIssues: Boolean;
  ToleranceFactor: Double; out Skipped: Integer): Integer;
```

- `ChooseExtractValues` contains the dialog part of the current `ShowExtractValuesDialog`: setup, `ShowModal`/`ConfirmSelectedIssues` loop and "Remember" handling. It returns `False` on Cancel. An empty `Caption` keeps the current caption. `Choices` holds each checked value whose `Mapping.ValueType <> nil`.
- `WriteChosenValues` computes `AnalyzeReaderStatistics` for this file's `KeyValues`. For each choice it finds the key value with the same `Name` and `Units` (exact, case-sensitive). It copies `Choice.Mapping`, sets `Mapping.Statistics` to this file's statistics, and skips standard-deviation keys. If `SkipIssues` is `True` and `CheckValue(...) <> []`, it skips the value. It writes with `WriteExtractedValue` and the snapshot from `Analysis`. It returns the count written. `Skipped` counts the missing and skipped values.
- `ShowExtractValuesDialog` keeps its signature and result: `ChooseExtractValues`, then `WriteChosenValues(..., SkipIssues = False, ...) > 0`.

- [ ] **Step 1: Write the failing tests**

```pascal
[Test] procedure WriteChosenValuesMatchesNameAndUnits;
  // value type 'Synthetic thickness' (m); choice Name 'd', Units 'm', Factor 1.
  // KeyValues [d = 2e-9 m, d = 3 nm (other units), e = 1 m]: result 1; FItem has 1 value 2e-9; Skipped = 0
[Test] procedure WriteChosenValuesSkipsMissingAndIssues;
  // choices d (m) and h (m); VT.RangeMax := 4.0 on the 'd' value type (Nullable<Double>), then Model.Manager.Flush(VT).
  // KeyValues [d = 5 m] with SkipIssues = True: result 0, Skipped = 2, FItem.Values.Count = 0
  // the same with SkipIssues = False: result 1, Skipped = 1
```

- [ ] **Step 2: Run the tests and see them fail.** Expected: `E2003 Undeclared identifier: 'WriteChosenValues'`.
- [ ] **Step 3: Implement** the split. Keep `TryWriteAutomaticExtractedValue` and `WriteAutomaticExtractedValues` unchanged.
- [ ] **Step 4: Run the tests and see them pass.** All existing `test_ValueSourceDesktop` tests must also pass.

---

### Task 6: Frame selection model

**Files:**
- Modify: `ELN.Desktop/Views/frame_ItemTree.dfm` (line 235 `SelectionOptions`; new `pmBatch` popup)
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas`

**Interfaces:**
- Consumes: `TBatchTarget`, `TItemTreeBatch.Allows`, `TItemTreeBatch.TopLevel`.
- Produces (frame, private unless stated):

```pascal
function CurrentNode: PVirtualNode;
function SelectedTargets: TArray<TBatchTarget>;
function IsMultiSelection: Boolean;
procedure CaptureSelection(out Keys: TArray<string>; out FocusKey: string);
procedure RestoreSelection(const Keys: TArray<string>; const FocusKey: string);
procedure actSingleEditableUpdate(Sender: TObject);
FBatch: TItemTreeBatch;
```

- `CurrentNode` returns `Tree.FocusedNode` if it is selected, otherwise `Tree.GetFirstSelected`.
- `SelectedTargets` returns one `TBatchTarget` for each selected node in tree order (`GetFirstSelected`/`GetNextSelected`).
- `IsMultiSelection` is `Tree.SelectedCount > 1`.
- `FBatch` is created after `FVM` exists in `Init` and is freed with the frame.

- [ ] **Step 1:** Add `toMultiSelect` to `TreeOptions.SelectionOptions` (DFM line 235).
- [ ] **Step 2:** Replace each `Tree.GetFirstSelected` in the frame with `CurrentNode`, except in `TreeDragOver` and `TreeDragDrop`. Those handlers are not connected; leave them unchanged.
- [ ] **Step 3:** Change `TreeGetPopupMenu`: if `Node` is not selected, call `Tree.ClearSelection`, then select and focus `Node`. If it is selected, only focus it. If `IsMultiSelection`, prepare `pmBatch` (Step 4), set `PopupMenu := pmBatch` and exit. Otherwise keep the current per-kind code.
- [ ] **Step 4:** Add the DFM popup `pmBatch` with `miBatchDelete`, `miBatchExtract`, `miBatchMoveTo`, `miBatchTags` and `miBatchExport`. Copy the `ImageIndex` values of `miItemDelete`, `miFileExtractValues`, `miItemMoveTo`, `FmiItemTags` (43) and `miFileExport`. Each `OnClick` is a published handler that calls the existing handler: `miBatchDeleteClick` calls `BtnDeleteClick`, `miBatchExtractClick` calls `miFileExtractValuesClick`, `miBatchMoveToClick` calls `miItemMoveToClick` or `miFileMoveToClick` according to `KindsOf`, `miBatchTagsClick` calls `miItemTagsClick`, `miBatchExportClick` calls `miFileExportClick`. Tasks 7-10 rewrite those existing handlers for several targets. Before the popup opens, each item is visible only if `TItemTreeBatch.Allows(<op>, Targets)` and `FVM.CanEdit` (Export needs only `not FVM.IsReadOnly`). Delete, Move and Drag use `FBatch.TopLevel(SelectedTargets)`. Captions: `Delete %d nodes...`, `Extract values from %d files...`, `Move %d nodes to...`, `Tags for %d items...`, `Export %d files...`.
- [ ] **Step 5:** Add `actSingleEditableUpdate` (`Enabled := Assigned(FVM) and FVM.CanEdit and not IsMultiSelection`). In `CreateActions`, use it for `actEdit`, `actDuplicate`, `actAddFile`, the `actNew*` actions and the other selection-based add actions. `actLinksUpdate` also disables for a multiple selection. `actDelete` keeps `actEditableUpdate`.
- [ ] **Step 6:** In `RefreshKeepView`, call `CaptureSelection` before `FillTree` and `RestoreSelection` after it. `RestoreSelection` selects each node whose target `Key` is in `Keys` and focuses the node with `FocusKey`. When `Keys` has one entry or none, keep the current `FSelectedNode` code path.
- [ ] **Step 7: Build and run the tests.** Run the test command. Expected: exit code 0. `test_AddFileSourceFolder` and `test_SharedDesktopMutations` create the frame and must still pass.

---

### Task 7: Frame Delete through the batch layer

**Files:**
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas:971-1061` (`BtnDeleteClick`)
- Create: `ELN.Desktop/Dialogs/Items/dlg_BatchSummary.pas` and `.dfm`

**Interfaces:**
- Consumes: `PlanDelete`, `ExecuteDelete`, `DescendantCount`, `PreviewStoragePath`, `FormatSkips`.
- Produces:

```pascal
TdlgBatchSummary = class(TForm)
  class function Confirm(const ACaption, AQuestion: string;
    const Skips: TArray<TBatchSkip>; const AOkCaption: string): Boolean;
  class procedure Report(const ACaption: string; Done: Integer;
    const Skips, Failures: TArray<TBatchSkip>);
end;
```

- The dialog has a top `TRzLabel` for the question or the result line, a read-only `TMemo` for the `FormatSkips` text (hidden when there is no text), and OK and Cancel buttons. `Report` hides Cancel. Follow the existing `ExecuteDialog` and `Create`/`ShowModal`/`Free` pattern and the Raize panel rules (`BorderOuter := fsFlatRounded`, `AlignWithMargins := True`). Register the unit in every project that registers `dlg_ItemMove.pas`, in the same form: search the `.dpr` and `.dproj` files of `ELN.Community.Desktop` and `ELN.Community.Tests` for `dlg_ItemMove`. `frame_ProjectsPanel` (Task 11) also uses this dialog.

- [ ] **Step 1:** Rewrite `BtnDeleteClick`:
  1. `Targets := FBatch.TopLevel(SelectedTargets)`, then `Plan := FBatch.PlanDelete(Targets)`.
  2. If `Plan.Targets` is empty, show `MessageDlg(FormatSkips(Plan.Skipped), mtWarning, [mbOK], 0)` and exit. For one blocked item, this shows the current blocker text.
  3. With one target and no skips, keep the current confirmations: `Move item "%s" to the recycle bin?`, `Delete file "%s"?`, and the current note text.
  4. Otherwise call `TdlgBatchSummary.Confirm('Delete', Question, Plan.Skipped, 'Delete')`. Question: `Move %d items (%d descendants) to the recycle bin. Permanently delete %d files and %d notes.` Leave out each part whose count is 0.
  5. `Result := FBatch.ExecuteDelete(Plan)`. For each done `btFile` target, delete the local preview `GetPreviewPath(Item.Id, AFile.Id)`.
  6. Selection: if any skipped or failed target remains, select those targets. Otherwise select the owning item of the first done file or note, or nothing (`FVM.SelectItem(0, 0)`). Then `FillTree(FLocation)` and restore.
  7. If `Plan.Skipped` or `Result.Failed` is not empty, call `TdlgBatchSummary.Report('Delete', Length(Result.Done), Plan.Skipped, Result.Failed)`.
- [ ] **Step 2:** `miBatchDeleteClick` calls `BtnDeleteClick`.
- [ ] **Step 3: Build and run the tests.** Expected: exit code 0.

---

### Task 8: Frame Extract values for several files

**Files:**
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas:3685-3753` (`miFileExtractValuesClick`)

**Interfaces:**
- Consumes: `ChooseExtractValues`, `WriteChosenValues`, `TdlgBatchSummary.Report`, `LoadToleranceFactor`.

- [ ] **Step 1:** Move the load part of `miFileExtractValuesClick` (plugin lookup, `PrepareFile`, `LoadFromFile`, `AttachAnalysisContext`, `GetKeyValues`, `ReaderIdentityOf`) into `function LoadFileKeyValues(AFile: TFile; out Values: TFileKeyValues; out Reason: string): Boolean`. `TFileKeyValues` is a frame-private record with the fields `KeyValues`, `ReaderId`, `ReaderVersion` and `Analysis`. The single-file path keeps its current `ShowMessage` texts by showing `Reason`.
- [ ] **Step 2:** If `IsMultiSelection`, run `ExtractSelectedFiles`:
  1. Set `Screen.Cursor := crHourGlass` and load all selected files. Each file that fails becomes a skip with `Reason`.
  2. Group by `ReaderId` in first-appearance order.
  3. For each group, call `ChooseExtractValues` with the first file's values and the caption `Extract values: <ReaderId>, <n> files`. If the user cancels, skip all files of the group with `Cancelled.`.
  4. Call `WriteChosenValues` for the first file with `SkipIssues = False`. Call it for the other files with `SkipIssues = True` and `LoadToleranceFactor(Model.Manager)`.
  5. `FillTree(FLocation)`, restore the selection, then `TdlgBatchSummary.Report('Extract values', <values written>, <file skips>, [])`. Put the values written and the values skipped for each reader into the result line, for example `XRD: 12 values written, 3 skipped.`
- [ ] **Step 3:** `miBatchExtractClick` calls `miFileExtractValuesClick`.
- [ ] **Step 4: Build and run the tests.** Expected: exit code 0.

---

### Task 9: Frame Move to and Export files

**Files:**
- Modify: `ELN.Desktop/Dialogs/Items/dlg_ItemMove.pas` (`Execute` at lines 40-75, `LoadTree` from line 78, `UpdateMoveState`)
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas` (`miItemMoveToClick` 3305-3328, `miFileMoveToClick` 3940-4046, `miFileExportClick` 3755-3784)

**Interfaces:**
- Consumes: `PlanMoveItems`, `PlanMoveItemsTo`, `ExecuteMoveItems`, `PlanMoveFiles`, `ExecuteMoveFiles`, `ExecuteExportFiles`.
- Produces: `class function TdlgItemMove.Execute(const SourceItems: TArray<TItem>; AvailableItems: TItems; out NewParentId: Integer): Boolean;`

- [ ] **Step 1:** Change `TdlgItemMove`: replace `FSourceItem` with `FSourceItems: TArray<TItem>`. Call `CollectExcluded` for each source. Caption: `Move "%s" to...` for one source, `Move %d items to...` for more. Select the parent of the first source at start. `UpdateMoveState` disables Move only when every source already has the selected parent. Update the one caller.
- [ ] **Step 2:** Rewrite `miItemMoveToClick`: `PlanMoveItems(FBatch.TopLevel(SelectedTargets))`; stop with the skip text if there is no target; `TdlgItemMove.Execute` with the plan items; `PlanMoveItemsTo`; for more than one target, or when skips exist, `TdlgBatchSummary.Confirm`; `ExecuteMoveItems`; `FillTree`; restore; `Report` on skips or failures.
- [ ] **Step 3:** Rewrite `miFileMoveToClick`. Keep the current destination list dialog and the destination checks (deleted, signed, no access). For more than one file, the caption is `Move %d files to...` and no item is excluded from the list. Then `PlanMoveFiles`, `ExecuteMoveFiles`, `FillTree`, restore, and `Report` on skips or failures.
- [ ] **Step 4:** In `miFileExportClick`, keep the `TSaveDialog` path for one file. For more than one file, create a `TFileOpenDialog` with `Options := [fdoPickFolders]` and title `Export %d files to folder`, then call `ExecuteExportFiles`. Report the failures with `TdlgBatchSummary.Report('Export files', ...)`. On success show `%d files exported to <folder>.` with `MessageDlg(..., mtInformation, [mbOK], 0)`.
- [ ] **Step 5:** `miBatchMoveToClick` calls `miItemMoveToClick` or `miFileMoveToClick` according to `KindsOf`. `miBatchExportClick` calls `miFileExportClick`.
- [ ] **Step 6: Build and run the tests.** Expected: exit code 0.

---

### Task 10: Tags dialog batch mode

**Files:**
- Modify: `ELN.Desktop/Dialogs/Items/dlg_TagManager.pas` and `.dfm`
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas:4822-4837` (`miItemTagsClick`)

**Interfaces:**
- Consumes: `PlanTags`, `CountTagged`, `AssignTagToAll`, `UnassignTagFromAll`.
- Produces: `class procedure TdlgTagManager.ShowTagManagerBatch(ABatch: TItemTreeBatch; const ItemIds: TArray<Integer>);`

- [ ] **Step 1:** Add a third `lvTags` column `Items` (width 80) to the DFM. Single-item and editor modes set its width to 0 in `ApplyMode`.
- [ ] **Step 2:** Add the fields `FItemIds: TArray<Integer>` and `FBatch: TItemTreeBatch`. With more than one ID, `ApplyMode` sets the caption `Tags - %d items` and the label `Check a tag to assign it to all %d items. Uncheck it to remove it from all.`
- [ ] **Step 3:** In batch mode, `LoadTags` sets `SubItems[1] := Format('%d of %d', [Count, N])` and `Checked := Count = N`. `lvTagsItemChecked` calls `AssignTagToAll` or `UnassignTagFromAll` and updates the count text. `lvTagsCustomDrawSubItem` keeps drawing only `SubItem = 1`.
- [ ] **Step 4:** `miItemTagsClick`: for a multiple selection, call `PlanTags`; stop with the skip text if there is no target; call `ShowTagManagerBatch` with the plan item IDs; then call `FVM.RefreshTagsForItem` for each ID and `Tree.Invalidate`. The single-item path stays as it is. `miBatchTagsClick` calls `miItemTagsClick`.
- [ ] **Step 5: Build and run the tests.** Expected: exit code 0.

---

### Task 11: Drag several root items to the Projects panel

**Files:**
- Modify: `ELN.Desktop/Views/frame_ItemTree.pas` (field line 278, property line 419, `TreeDragAllowed` 2983-2994, reset at line 2143)
- Modify: `ELN.Desktop/Views/frame_ProjectsPanel.pas` (`TreeDragDrop` 2204-2251, `TreeDragOver` 2541-2560)

**Interfaces:**
- Produces: `property DraggedProcs: TArray<TItem> read FDraggedProcs;` This replaces `DraggedProc`. `DraggedProc` has no other reader in Community or Commercial outside the pin.

- [ ] **Step 1:** `TreeDragAllowed`: `Targets := FBatch.TopLevel(SelectedTargets)`. If `Node` is not selected, `Targets := [ForItem(<node item>)]`. `Allowed := TItemTreeBatch.Allows(boDrag, Targets)`. `FDraggedProcs` holds the target items when allowed, otherwise it is empty.
- [ ] **Step 2:** `TreeDragOver`: test `Length(DraggedProcs) > 0` instead of `Assigned(DraggedProc)`.
- [ ] **Step 3:** `TreeDragDrop`: for each item, record its old location (project and folder pair, without duplicates), then call `FVM.MoveProc(Item, NewProjectID, NewFolderID, Model.Relocator)` inside `try`/`except`. An exception other than `EAbort` becomes a failure with `E.Message`. After the loop, call `FillTree` one time and send one `TMessage<TLocation>` for each distinct old location. If there are failures, call `TdlgBatchSummary.Report('Move', <done>, [], Failures)`.
- [ ] **Step 4: Build and run the tests.** Expected: exit code 0.

---

### Task 12: Help, version and application build

**Files:**
- Modify: `ELN.Desktop/Assets/Runtime/Help/Items.html` (new `<h2>Select several records</h2>` before `Delete safely`)
- Modify: `ELN.Desktop/Assets/Runtime/Help/FilesAndNotes.html` (line 35 list), `Values.html` (after line 21), `TagsAndLinks.html` (tags section)
- Modify: `README.md` (`## Source version`), `ELN.Community.Desktop/ELNCommunity.dproj:46-47`

- [ ] **Step 1:** Write the Help text in the existing style (short sentences, `<strong>` for UI names):
  - `Items.html`: Ctrl+click, Shift+click and Shift+arrow keys; right-click on the selection; the batch commands; the single confirmation and the summary; skipped records; the detail panel shows the focused record; items go to the Recycle Bin, files and notes are deleted permanently.
  - `FilesAndNotes.html`: Move to, Export and Delete with several files. Export to a folder adds ` (2)` and never overwrites.
  - `Values.html`: Extract Values with several files: one dialog for each reader, matching by key name and unit, skipped values for the other files.
  - `TagsAndLinks.html`: the `k of N` column and check/uncheck for all items.
- [ ] **Step 2:** Increase the version to `2.2.0.13` in `ELNCommunity.dproj` (`VerInfo_Build`, `ProductVersion`, `FileVersion`). Rename the README heading to `## Source version 2.2.0.13`. Add one line: `The Items tree accepts a multiple selection. Delete, Extract values, Move to, Tags, Export files and drag to the Projects panel work on all selected records with one confirmation and one summary.`
- [ ] **Step 3:** Build the application: `pwsh -NoProfile -File tools/build-community.ps1 -Target CommunityDesktop`. Expected: exit code 0. Check that `_OUT/CommunityDesktop/Win32/Debug/ELNCommunity.exe` reports file version `2.2.0.13`:
  `(Get-Item _OUT/CommunityDesktop/Win32/Debug/ELNCommunity.exe).VersionInfo.FileVersion`
- [ ] **Step 4:** Run the full test target one more time. Expected: exit code 0.
- [ ] **Step 5:** Smoke test on a new synthetic notebook (not a user notebook): Ctrl and Shift selection; right-click inside and outside the selection; Ctrl+click that deselects the focused node; Delete of a mix with one signed item; Extract values on files of two readers; Move of items and of files; Tags `k of N`; Export with a name conflict; drag of two root items to another project. Report what you observed. The user accepts the result in the running application.
