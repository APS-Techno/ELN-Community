# Items tree multiple selection design

## Purpose and agreed requirements

Users must do Delete and Extract values one node at a time. They want to select several nodes in the Items tree and do one operation on all of them, with one confirmation and one result.

The user approved these decisions:

- Batch operations in the first version: Delete, Extract values, Move to, Tags, Export files, and Drag & drop.
- Extract values on several files shows one dialog for each reader. The choices from the dialog apply to all files of that reader.
- A target that cannot be processed is skipped. The confirmation lists the skipped targets and the reasons. A summary shows the result.
- The detail panel shows the focused node, as in Windows Explorer.
- Drag & drop with several nodes goes only to the Projects panel. The drag inside the Items tree stays disconnected.
- The batch logic goes into one batch layer in the view model (approach B). Each handler in the frame does not get its own loop.

This design requires review before implementation. It does not authorize a commit, a push, or a Commercial pin update.

## Current evidence

- `ELN.Desktop/Views/frame_ItemTree.dfm` sets `TreeOptions.SelectionOptions = [toFullRowSelect, toSelectNextNodeOnRemoval]`. The tree allows one selection only.
- About 45 handlers in `frame_ItemTree.pas` read `Tree.GetFirstSelected`. No handler reads more than one selected node.
- `TreeGetPopupMenu` sets `FocusedNode` and `Selected[Node]` on each right-click. This clears all other selections.
- `TreeClick` (DFM `OnClick`) updates the detail panel from `GetFirstSelected`. `SelectedItemId` gives the hypotheses panel the first selected item.
- `BtnDeleteClick` deletes one node. Items go to the recycle bin through `SoftDeleteItemTree`. That call uses one transaction for the item's subtree. Files are deleted permanently: `RemoveFile`, then two `Storage.DeleteFile` calls and the local preview. Notes are deleted permanently through `RemoveEntry`.
- `TItemModel.RemoveEntry` is a procedure. If the item is signed, or if the flush fails, it exits and reports nothing.
- `miFileExtractValuesClick` loads one file and calls `ShowExtractValuesDialog`. The dialog maps each value name to a value type for one reader. The dialog writes the values itself.
- `TdlgTagManager.ShowTagManager(ItemId, ItemTitle)` works on one item. Each checkbox change assigns or unassigns the tag immediately (`TTagModel.AssignTag`, `UnassignTag`).
- The DFM does not connect `TreeDragOver` and `TreeDragDrop`. The drag inside the Items tree does not work now. Only one drag works: one root item to the Projects panel, through `TframeItemTree.DraggedProc` (`frame_ProjectsPanel.pas`, `TreeDragDrop` and `TreeDragOver`).
- Commercial compiles the same `frame_ItemTree.pas` through its pinned `Community/` submodule. Commercial has no item tree code of its own.
- The model has no API that takes a list of targets. The batch must call the existing single-target APIs in a loop.

## Selection model

- Add `toMultiSelect` to `TreeOptions.SelectionOptions` in the DFM.
- Ctrl+click adds or removes one node. Shift+click selects a range. Shift+arrow keys extend the selection. These come from VirtualTreeView. The design adds no other selection commands.
- Right-click on a selected node keeps the selection. Right-click on a node that is not selected selects only that node and focuses it.
- The detail panel, `FItem`, `FCurrentFile`, and `SelectedItemId` use the current node: the focused node if it is selected, otherwise the first selected node. A Ctrl+click that deselects the focused node thus does not leave the panel on a node that is not selected.
- `SelectedNodes` returns all selected nodes in tree order. `TItemTreeBatch.TopLevel` removes each target whose item, owning item, or ancestor item is also a selected target. For example, if an item and a file of that item are both selected, only the item remains.
- After a refresh (`RefreshKeepView`) or a batch operation, the tree selects the nodes with the same IDs again and focuses the same node. `FillTree` rebuilds all nodes, so `toSelectNextNodeOnRemoval` has no effect after a delete. After a delete, the tree selects the targets that remain (the skipped and failed ones). If none remains, it selects the owning item of the first deleted file or note, or nothing.

## Action availability

When the user selects one node, all actions work as they do now. When the user selects two or more nodes, these rules apply:

| Action | Allowed selection | Uses `TItemTreeBatch.TopLevel` |
|---|---|---|
| Delete | any mix of items, files and notes | yes |
| Extract values | files only | no |
| Move to | items only, or files only; a mix disables the action | yes |
| Tags | items only, folders included | no |
| Export files | files only | no |
| Drag to Projects panel | root items only | yes |
| All other actions (Edit, Add, New, Duplicate, Sign, Links, Comments, Bookmark, Hypothesis, Analyze, Regenerate previews, Check Value Sources, Copy MCP link, Reupload, Open) | disabled | not applicable |

The popup menu and the `OnUpdate` handlers of the actions use the same rule function. The popup menu shows the batch actions with the count, for example `Delete 7 nodes...`.

## Batch layer

Put the new unit `ELN.Model/ViewModels/unit_ItemTreeBatch.pas` next to `unit_ItemTreeVM.pas`. Like `unit_ItemTreeVM`, it has no `.dpk` or `.dproj` entry: the hosts find `ELN.Model\ViewModels` through their unit search paths. The unit has no VCL dependency.

The unit defines these types:

- `TBatchTargetKind = (btItem, btFile, btNote)`.
- `TBatchTarget`: kind, ID, title, and owning item ID.
- `TBatchSkip`: target and reason text.
- `TBatchPlan`: the targets to process and the skipped targets.
- `TBatchResult`: the count of done targets, and the failed targets with their reasons.

Each operation has two functions:

- `Plan<Operation>(Targets, ...)`: check each target and put it in the targets list or in the skipped list. It does not write.
- `Execute<Operation>(Plan, ...)`: process each target with the existing single-target API. A failure on one target goes into `TBatchResult` and does not stop the loop.

The frame does these steps for each batch action:

1. Collect the targets from `SelectedNodes`, and apply `TItemTreeBatch.TopLevel` where the table above says so.
2. Call `Plan…`. If the plan has no targets, show the skip reasons and stop.
3. Show one confirmation or one parameter dialog that includes the skip list.
4. Call `Execute…`.
5. Refresh the tree one time.
6. Show the summary if any target was skipped or failed. If all targets succeeded, show no summary.

The single-node actions use the same `Plan…` and `Execute…` functions with a list of one target. They keep their current confirmation text. Thus there is only one code path for each operation.

## Operations

### Delete

Plan rules:

- Item: skip if `FindDeleteBlocker` returns a reason, if the item is signed, or if the user cannot edit.
- File: skip if the owning item is signed.
- Note: skip if the owning item is signed.

The confirmation shows the counts and the result of each kind, for example: `Move 3 items (12 descendants) to the recycle bin. Permanently delete 5 files and 1 note.` Then it shows the skipped targets. The buttons are Delete and Cancel.

Execution:

- Item: `Model.Items.SoftDeleteItemTree`. There is one transaction for each item.
- File: move the current file-delete code from `BtnDeleteClick` into one method. That method does `RemoveFile`, the storage delete, and the preview delete.
- Note: `RemoveEntry`. Change `RemoveEntry` to a function that returns `Boolean`, so that the batch can detect a failure. Update all callers.

### Extract values

1. Load the key values of each selected file: `PrepareFile`, `Plugin.LoadFromFile`, `IKeyValueProvider.GetKeyValues`. Show the wait cursor while this runs.
2. Put each file that has no reader, or that fails to load, into the skipped list.
3. Group the files by `ReaderId`.
4. For each group, show `dlg_ExtractValues` one time with the values of the first file. The caption shows the reader and the file count, for example `Extract values: XRD reader, 5 files`.
5. Split `ShowExtractValuesDialog` into two parts. The dialog returns the chosen values: name, units, and mapping. A separate procedure writes the chosen values to one file through `WriteExtractedValue`. The single-file path calls both parts. Its behaviour does not change.
6. For each file in the group, write each chosen value that has the same name and units in that file. Each chosen value that the file does not have is counted as skipped. The user confirmed range and tolerance issues only for the first file. For the other files, a value that fails the range or tolerance check is skipped and counted, as in automatic extraction. Each file uses its own reader statistics for the tolerance.
7. If the user cancels the dialog for one group, skip that group and continue with the next group.
8. The summary shows the values written, the values skipped, and the files skipped, for each reader.

The "Remember" choice of the dialog keeps its current meaning: it saves the reader mapping for later use.

### Move to

Items:

- Plan rules: skip folders, signed items, and targets for which the user cannot edit.
- `TdlgItemMove` opens one time. Change its `SourceItem` parameter to a list of source items, so that the dialog can exclude all their subtrees from the target list.
- After the user selects the target, skip each item whose subtree contains the target, and each item that already has that parent.
- Execution: `FVM.ReparentItem` for each item.

Files:

- Plan rules: skip files whose owning item is signed.
- The current target picker of `miFileMoveToClick` opens one time.
- Execution: `Model.Items.MoveFile`, then `Storage.MoveFile` with the current rollback, for each file.

### Tags

Add a batch mode to `TdlgTagManager`: `ShowTagManagerBatch(ItemIds)`.

- Each tag shows a checkbox and a count column with the text `k of N`.
- The checkbox is checked only if all N items have the tag.
- If the user checks a tag, the dialog assigns it to the items that do not have it.
- If the user unchecks a tag, the dialog unassigns it from all items.
- Changes apply immediately, as in the single-item mode. The dialog has no new buttons.
- The frame calls `FVM.RefreshTagsForItem` for each item and repaints the tree.

### Export files

- `TFileOpenDialog` in folder mode selects the target folder one time.
- Execution: `Model.Storage.CopyOut` for each file.
- If a file name already exists in the folder, the copy gets the name `name (2).ext`, then `name (3).ext`, and so on. The export never overwrites an existing file.

### Drag to the Projects panel

- `TreeDragAllowed` allows a drag only when all targets in `TItemTreeBatch.TopLevel` of the selection are root items.
- Replace `DraggedProc: TItem` with `DraggedProcs: TArray<TItem>`. Update `frame_ProjectsPanel.TreeDragOver` and `TreeDragDrop`.
- `TreeDragDrop` calls `FVM.MoveProc` for each item inside `try`/`except`. It collects the failures, then calls `FillTree` one time. Then it sends one location message for each source project and folder pair.
- The drag inside the Items tree stays disconnected.

## Error handling

- The plan step reads only. It writes nothing.
- Each target in the execute step uses the existing transaction and compensation of its single-target API. A batch is not atomic. A failure leaves the earlier targets done, and the summary lists the failure.
- An exception in one target is caught, put in `TBatchResult` with its message, and the loop continues. `EAbort` stops the loop.
- The summary is one dialog that lists the done count and each skipped or failed target with its reason.

## Verification

- Add DUnitX tests for `unit_ItemTreeBatch` in `ELN.Community.Tests`. Use a new GUID-rooted synthetic SQLite notebook. Test these points:
  - `TopLevel` removes descendants and files of selected items.
  - Delete plan: a signed item, an item with a delete blocker, and a file of a signed item are skipped with reasons.
  - Delete execution: items go to the recycle bin, files and notes are removed, and one failure does not stop the others.
  - Move plan: a target inside the source subtree and a folder source are skipped.
  - Tags batch: assign to the items that do not have the tag; unassign from all.
  - Extract matching: a chosen value is written only to files that have the same name and units.
  - Export naming: an existing name gets ` (2)`.
- Build `CommunityDesktop` with the product helper in Win32 Debug. If the Debug configuration is blocked by missing external packages, report this. Do not change the external package setup.
- Smoke test in the running Community application: select with Ctrl and Shift, use the right-click popup, run each batch action, check the detail panel and the drag to the Projects panel.
- The user accepts the result in the running application. A build and passing tests do not prove acceptance.

## Out of scope

- Commercial pin update. Commercial gets the change only after a separate authorization.
- Drag inside the Items tree.
- Batch versions of Edit, Duplicate, Sign, Links, Comments, Bookmark, Hypothesis, Analyze, and Regenerate previews.
- New model APIs that take a list of IDs, and atomic batch transactions.
- Ctrl+A, the Delete key, and other new keyboard commands.
