# Design: Experiment series (plan, slots, comparison table)

_Date: 2026-11-04. Status: DRAFT, waiting for owner approval._

Edition-specific gate rules for Commercial are in the Commercial addendum:
`APS-ELN-Commercial/docs/superpowers/specs/2026-11-04-experiment-series-commercial-addendum.md`.

## 1. Intent

Scientists make sample series in the item tree and compare them by hand. They open each deposition, write the values down, and plot one result against the changed parameter in Origin. The owner never used hypotheses for a real series, because a hypothesis gives no help with this work.

All conditions and results are now stored as ELN values. The ELN can therefore build the comparison itself. A **series** is a new object that:

- plans which parameter values to make (the plan),
- links each deposition to the planned point that it makes (the slot),
- builds the comparison table and plot from stored values,
- exports the table to Origin,
- can stand alone, or can be used by a hypothesis as its runs and evidence.

A series does not need a hypothesis. Example: deposition-rate calibration for a new target or material. There is no scientific question, but it is still a planned series.

## 2. Facts about the lab (from the owner)

- Tree shape is always Deposition → Specimen → Measurement, in the real physical order.
- Conditions are on the deposition. Results are on measurements under each specimen.
- One deposition can hold several specimens. Usually they are different substrates for different measurements. Sometimes they are identical pieces measured by different methods.
- Series are adaptive. A few levels are planned first. Then points are added around the interesting region.
- Usually one varied parameter. Sometimes two (for example power and pressure).
- Repeats happen only when a sample fails. Planned replicates are not usual.

## 3. Goals

1. Remove hand transcription: a series table with one row per deposition, filled from stored values.
2. A plot of a result against the varied parameter, with one curve per level of a second parameter.
3. An export that Origin reads with names and units.
4. A plan: varied parameters with ranges, fixed conditions, slots, adaptive additions with history.
5. "Make from slot": create the deposition from a slot, linked and with planned conditions filled in.
6. Slot states that show what is planned, deposited, measured or failed.
7. Optional link to a hypothesis: series depositions become its runs, the series table becomes evidence.
8. Plan approval only for a series used by a hypothesis whose author needs approval (Commercial User; see the addendum). A standalone series never needs plan approval. Community never needs it.

## 4. Non-goals

- Taguchi and other designed arrays in phases 1 to 3 (phase 4, §11).
- Statistical analysis beyond mean, spread and linear trend. ANOVA and response surfaces are not in scope.
- Changes to the item tree shape. Depositions stay where they are.
- Launching or controlling deposition equipment.
- The hypothesis UX clarity work (labels, visible rules, item-side links). That is a separate task, recorded in `D:/APS/ELN/.claude/HANDOFF.md`.
- Web UI. Desktop and MCP only in this design.

## 5. Anti-goals (failure even if it works)

- The series makes the user enter the same value twice (once in the plan, once on the item).
- The table averages or merges values from different sources without showing it.
- A planned value is shown as a measured value.
- An MCP client can start a plan or pass an approval without a human action in the desktop.
- Existing hypotheses, their seals or their runs change behavior.

## 6. Approaches considered

|Approach|Summary|Result|
|---|---|---|
|A. Separate Series object|Own tables. Depositions stay root items and link to slots. One deposition can be in more than one series. A hypothesis can use zero or more series.|**Chosen**, in phases.|
|B. Series as a tree item|A "Series" item with the depositions as children; plan in item properties.|Rejected. One parent per item, so one deposition cannot be in two series. Existing depositions must move. Ranges and slots in properties are hard to query and approve. Items have no approval gate.|
|C. Series view only|Select depositions, get table, plot and export. No plan.|Rejected as the end state: no slots, ranges or approval. Its function is phase 1 of A.|

The owner picked A because a series must exist without a hypothesis. A also lets one deposition be in more than one series of the same project (assistant's reason).

## 7. Concepts and data model

All new tables are Aurelius entities in `ELN.Domain`, added through `ELN.DB/unit_SchemaUpdate.pas` (`UpdateDatabaseAdditive`). Use `unit_HypothesisRun.pas` and `unit_HypothesisEvidence.pas` as templates. Enum ordinals are append-only, as for hypotheses.

|Entity|Purpose|Main fields|Phase|
|---|---|---|---|
|`Series`|One series in one project|`ProjectId`, `Title`, `Purpose` (free text), `Status`, `TargetFolderId`, `CreatedBy`, `CreatedDate`, `CreatedVia` (Desktop/MCP), `Version`|1|
|`SeriesMember`|A deposition in a series|`SeriesId`, `ItemId`, `SlotId` (null in phase 1), `AttemptState` (Valid/Failed), `FailReason`, `AddedBy`, `AddedDate`. Unique on `SeriesId, ItemId`. The item must be a non-deleted root item in the series project. _Assistant's call: no cross-project members, as for hypothesis runs._|1|
|`SeriesColumn`|User choice of columns and response source|`SeriesId`, `RecType`, `ValueTypeId`, `SourceKey` (`''` = the unsplit column), `Role` (Shown/Hidden/Varied/Response; Fixed appended in phase 2), `SortOrder`. Unique on `SeriesId, RecType, ValueTypeId, SourceKey`.|1|
|`SeriesFactor`|A varied parameter|`SeriesId`, `ValueTypeId`, `RangeMin`, `RangeMax`, `ApprovedMin`, `ApprovedMax`, `SortOrder`|2|
|`SeriesFixed`|A held-fixed condition|`SeriesId`, `ValueTypeId`, `Value`, `Tol`|2|
|`SeriesSlot`|A planned point|`SeriesId`, `Origin` (Planned/Added), `AddedBy`, `AddedDate`, `Reason`. Slot state is computed (§8.6), not stored.|2|
|`SeriesSlotLevel`|Factor level of a slot|`SlotId`, `FactorId`, `Value`|2|
|`SeriesPlanChange`|History and notices: level added or removed, range change request, approval decision|`SeriesId`, `Kind`, `Payload`, `By`, `Date`, `NeedsApproval`, `Decision`, `DecidedBy`, `DecidedDate`, `Comment`|3|
|`HypothesisSeries`|A hypothesis uses a series|`HypothesisId`, `SeriesId`. Unique pair.|3|

A slot has one level for each factor. One factor gives a line of points; two factors give a set of (A, B) points. The model allows more factors so that Taguchi (phase 4) needs no new tables. The phase 2 UI supports one or two factors.

### 7.1 Series status

`Draft` → `Active` → `Closed`, `Closed` → `Active` (reopen by the author), and `Abandoned` from `Draft` or `Active`.

- Phase 1 has no gate. A new series is `Active` at once.
- A series never waits for plan approval as a series. Its plan is approved only through a hypothesis that uses it (§9, §10).
- A series made through MCP stays `Draft` until a human clicks **Start** in the desktop, in all editions. This keeps the current rule that MCP cannot pass a human gate.
- `Closed` is set by the author. No review. Accepting a hypothesis does not close the series it uses; the hypothesis seal keeps its own snapshot (§10). _Assistant's call: a series can serve several hypotheses, so a freeze on one acceptance would block the others._

## 8. Behavior

### 8.1 Table (phase 1)

- **Rows:** one row per `SeriesMember` with `AttemptState = Valid`. Failed attempts are hidden by default, with a "Show failed" toggle.
- **Value search:** for each row, the ELN reads all values on the deposition item and on all its non-deleted descendants. A new model query reads descendants for a set of root ids in a fixed number of statements (chunk ids at 500, as `IdChunks` in `unit_HypothesisModel.pas`). The current `frm_Analysis.pas` `PlotData` walk is a reference, not a dependency.
- **Columns:** one column per (record type, value type). Condition columns use `EXP_CONDITION` values, result columns use `TEST_RESULT` values. A value type stored both ways gives two columns.
- **Source key:** each found value gets a source key. A value on the deposition itself has key `root`. A value on a descendant has key `at:<ActionTypeId>` of the item that holds it (the method, for example XRR or profilometry), labelled with the action type title. Titles are not used, because they contain sample ids and differ in every row. If a column has values with more than one source key among the rows of the table, it splits into one column per source key. The ELN never averages different sources. _Revised in planning (2026-11-04)._
- **Same source, two values:** if one row has two or more values with the same key in one column (for example two specimens measured by the same method), show all of them in the cell and flag the cell. Do not pick one.
- **Tolerance:** shown as `value ± tol` when present.
- **Missing:** an empty cell shows "—".
- **Column choice:** the user hides columns, gives roles (Varied, Response, Shown) and picks the response source for a split column. In phase 1 the user sets the roles by hand. From phase 2, Varied comes from `SeriesFactor` and Fixed from `SeriesFixed`. This is stored in `SeriesColumn`.
- **Open:** double-click a cell to open the item that holds the value.

### 8.2 Plot (phase 1)

- X = one condition column (varied parameter). Y = one or more result columns. A split column is used through the `SourceKey` stored in `SeriesColumn`; if none is stored, the plot asks the user to pick a source.
- Group by = an optional second condition column. One curve per distinct value of it.
- Error bars from `Tol` when present.
- Use TeeChart, as in `ELN.Desktop/Forms/frm_Analysis.pas`. Optional linear trend, as there.

### 8.3 Export (phase 1)

- **Copy table** (clipboard, tab-separated) and **Save CSV**.
- Row 1 = column names, row 2 = units, then data. A split column keeps its source label in the name. _Builder's call (assistant): Origin's import wizard maps these rows to Long Name and Units; no `.opju` writing._
- Tolerance goes into a separate `± <name>` column next to its value column, so Origin can use it for error bars.

### 8.4 Plan (phase 2)

- **Factors:** value type, planned range, list of levels. Phase 3 adds the approved range.
- **Fixed conditions:** value type, value, tolerance.
- **Slots:** made from the level lists. One factor: one slot per level. Two factors: the user picks combinations; **Fill grid** makes all combinations.
- **Adding points:** allowed at any time while the series is `Active`. Each added slot stores `Origin = Added`, user, date and an optional reason. The plan view shows planned and added points differently.
- **Removing a slot:** allowed only if it has no members.
- **No follow-up needed:** a plan change never needs a new hypothesis. A follow-up hypothesis is for a new question (new factor or response), not for a new point.

### 8.5 Make from slot (phase 2)

- Creates one root item: level `Proc`, type `Synthesis`, in `TargetFolderId`. Title = `<series title> <level values with units>`; the user can edit it in the normal new-item dialog before save.
- Writes each slot level and each fixed condition as an `EXP_CONDITION` value. Its description is the label of the plan entry, or "Planned value from series <title>" when the entry has no label; the source note is always "Planned value from series <title>". The user corrects them if the real deposition differed.
- **Planned mark (owner decision):** a new source kind `vskPlanned`, appended to `TValueSourceKind` (`ELN.Domain/unit_ItemTypes.pas:21`). The table marks planned values as "planned". **Confirm** on the deposition (one click for all its planned values), or a manual edit of a value, changes it to `vskManual`. Every place that branches on `TValueSourceKind` (drift check, MCP output, reports, value dialogs) must handle the new ordinal.
- Adds the item as a `SeriesMember` of the slot.
- Specimens and measurements are added as today.
- **Link existing:** the user can also link an existing deposition to a slot (needed for series made before this feature). A multi-selection links by value: each deposition goes to the open slot whose levels equal its stored factor values; a deposition with no matching slot gets a new `Added` slot after confirmation.

### 8.6 Slot state and checks (phase 2)

Computed, not stored:

|State|Rule|
|---|---|
|Planned|no valid member|
|Deposited|valid member, at least one response value missing|
|Measured|valid member, all response values present|
|Failed only|members exist, all failed|

The response set = columns with role Response. For a split response column, "present" means the chosen `SourceKey` has a value; with no chosen source, any source counts. Planned-mark values never count as present.

- **Mark failed:** on a member, with a reason. The slot returns to Planned. Make from slot again creates the next attempt.
- **Deviation flags:** a cell is flagged when the deposition's stored value of a factor differs from the slot level, or a fixed condition differs from the plan, outside the plan tolerance. _Builder's call (assistant): with no plan tolerance, compare with the value's own `Tol`; with neither, exact match._

### 8.7 Plan-first flow (owner decision, 2026-11-05)

The owner tested phase 1: a new series was an empty list with an "add depositions" step, which does not match the idea. Phase 2 makes the plan the entry point and replaces free membership:

- **New series** opens the plan editor (title, purpose, target folder, factors with optional range and levels, fixed conditions, response value types).
- The table has one row per slot from the start. A slot without a deposition shows its levels, marked planned.
- A deposition enters a series only through a slot: **Make deposition** or **Link existing**. The phase 1 **Add to series...** action and free (slot-less) members are removed.
- Rows sort by factor levels (first factor, then second), not by insertion order.
- Unconfirmed planned values are not data: the plot does not use them and the export writes them as empty fields. The plot says how many points wait for confirmation.
- Format 6 is not released, so the phase 2 tables are part of format 6. `TLocalNotebook.Open` runs the read-only schema check. A format-6 notebook made by a pre-release build without the phase 2 tables asks for the normal upgrade (backup copy `.format6-backup-…`, then the additive schema update), so series made with the pre-release build are kept. _Revised 2026-11-06 (owner): the first design refused such notebooks and sent the user to the `.format5-backup` copy, which lost work done after the first upgrade._
- Each factor, fixed condition and response has an optional label (`EntryLabel`, at most 100 characters) that says which parameter or result it is, for example "Mo layer" for a Time factor. The label only names the entry: values still match by value type, and a value type is still used once per plan. The plan lists, the levels box, the Add point dialog, the table headers and the MCP plan show it. A factor label can change while the series has points. _Added 2026-11-06 (owner): "Time, s" alone did not say which time._

## 9. Gates

Gate eligibility goes through `IProjectAccessPolicy` (`ELN.Model/unit_ProjectAccessPolicy.pas`). Its current gate methods take a `THypothesis` and the `THypothesisGate` enum (`ELN.Domain/unit_Hypothesis.pas:29`).

**Owner decisions:** a standalone series needs no plan approval. A series plan is approved only as part of a hypothesis, in the same decision as the proposal (§10). A plan change needs approval only when the series is used by an Approved hypothesis whose author cannot pass **approve proposal** on own work.

- **One new series gate: approve plan change.** It covers a range extension and a series linked after the hypothesis was approved. Add a separate policy method with facts (project id, hypothesis author id). _Assistant's call:_ it shares the scope and project grant of **approve proposal**. There is no change to `THypothesisGate`, the stored approval policy JSON, or the grant flags, so existing policies still parse.
- **Community** (`ELN.Community/unit_LocalProjectAccessPolicy.pas`): the author always passes, so no plan change ever waits. A series made through MCP still needs **Start** (§7.1). Hypothesis conclusion review is unchanged.
- **Commercial:** see the addendum.
- **Range rule (approval required):** a new slot inside the approved range of every factor is allowed at once and writes a `SeriesPlanChange` notice. A slot outside the range of any factor needs an approve-plan-change request. Existing slots continue while it waits; only the new slot is blocked.
- **MCP:** no tool passes a series gate. MCP may create a `Draft` series, edit its plan, and read tables. Desktop and MCP use one writer, `TSeriesModel`. The MCP host sets `CreatedVia = MCP` through its tool context, and the model refuses **Start** and every gate when the caller is MCP. New tools go in `ELN.MCPServer` (Community). Any Commercial MCP server is decided at the pin bump.

## 10. Hypothesis link (phase 3)

- A hypothesis can use one or more series (`HypothesisSeries`). The hypothesis author links a series while the hypothesis is Proposed or Approved. A link made after approval, when approval is required, stays pending until **approve plan change** passes; no runs attach while it is pending. Unlinking does not detach runs; the user removes them by hand.
- **Runs:** the series puts its valid members on the hypothesis as `THypothesisRun` rows through the existing run code, so derived states, key value and seal keep working:
  - while the hypothesis is Approved: each valid member is attached as Run when linked or when added to the series, in the same transaction;
  - while it is Proposed: nothing is attached; at proposal approval, all valid members are attached as Run;
  - when it is InReview or final: nothing is attached;
  - a deposition that is already attached keeps its existing row and role.
  _Assistant's call._
- A failed member is not detached automatically. It stays a run and shows as failed in the Runs tab, so the record shows the failed attempt.
- **Series as evidence:** new tables, not new columns on `THypothesisEvidence` (its `ItemId` is required and it holds one item). `HypothesisSeriesEvidence` (`HypothesisId`, `SeriesId`, `Note`, `CitedBy`, `CitedDate`) and `HypothesisSeriesEvidenceCell` (evidence id, deposition item id, value type id, source key, value id, value snapshot). The evidence view flags cells that changed later, as for value evidence today. Submit accepts series evidence as the "at least one evidence" condition.
- **Seal:** `BuildHypothesisContent` (`ELN.Model/unit_HypothesisHash.pas:43`) gets an extra input for series evidence and appends its lines **only when there are any**. The content of every existing hypothesis stays byte-identical, so existing seals stay valid. Test this.
- **No freeze on the series:** see §7.1. The seal covers the cited snapshot; later series changes show as evidence-change warnings.
- **One decision (owner):** approving the hypothesis proposal also approves the plan of every series it uses. It sets `ApprovedMin`/`ApprovedMax` of each factor to the current planned range and writes a `SeriesPlanChange` row. The gate panel shows the linked series plans (factors, ranges, slots) next to the proposal, so the approver sees what is approved.

## 11. Phases

|Phase|Content|Done when|
|---|---|---|
|1|`Series`, `SeriesMember`, `SeriesColumn`; Series view (list + table + plot); add existing depositions; export; read-only MCP tools (`list_series`, `get_series_table`)|A real past series gives the same table and plot that the owner made by hand in Origin|
|2|Plan-first flow (§8.7): plan editor, factors, fixed conditions, responses, slots, make from slot, link existing to slot (single and by value), mark failed, confirm planned values, slot states, deviation flags; removal of free membership and **Add to series...**; MCP tools to create a Draft series and edit its plan|A new calibration series is planned, made from slots, and adapted with added points, with no hand transcription|
|3|Series gates through the policy, `SeriesPlanChange` notices, `HypothesisSeries`, auto runs, series evidence, seal extension|A hypothesis uses a series, cites its table and is accepted with a valid seal; Community needs no plan approval|
|4|Taguchi: orthogonal-array slot generator (L4, L8, L9, L16, L18, L27), array vs added points, main effects + S/N view, confirmation run; ANOVA later; interactions out|Separate design update before work starts|

## 12. UI placement

- **Series view:** a new card in `frame_ContentViewer`, next to the hypotheses card. Opened from the project panel (**Series...**, as **Hypotheses...**). Left: series list with status and progress (for example "4/6 measured"). Right tabs: **Table** (one row per plan point) and **Plot**; **History** comes in phase 3. The plan is edited in a dialog that **New series** and **Edit plan...** open. Row actions (make, link, mark failed, unlink, confirm, remove point) are in the table's context menu, so the toolbar keeps only series-level commands.
- **Item tree:** context menu **Link to plan point...** on root items (replaces phase 1 **Add to series...**) and **Confirm planned values** on items that hold planned values. The item detail shows the series and point of a deposition, for example `Series: Ti rate (200 W)`.
- Controls are defined in DFM, follow the project Delphi rules, and use existing patterns from `frame_Hypotheses`.

## 13. Owner decisions (2026-11-04)

- **Q1.** A standalone series (for example a calibration by a User) needs no plan approval. Only a series used by a hypothesis is approved, through that hypothesis.
- **Q2.** Planned values carry the planned mark until confirmed (§8.5).
- **Q3.** One decision approves the hypothesis proposal and the plans of its series (§10).
- **Q4.** A Commercial PowerUser keeps passing gates on own work, including conclusion acceptance.

## 14. Left to the builder

- Exact DFM layout, column widths, icons, empty-state text.
- Query shape for descendant values, within the fixed-statement rule.
- Clipboard and CSV details beyond §8.3.
- Recycle bin: a member whose item is in the recycle bin shows as "deleted" and is not in the table. Purge removes the member row and writes a history line. Do not remove it silently.
- Tests: synthetic SQLite fixtures, in the Community test projects (`DesktopRegressionTests`). Cover the column split, the range rule, MCP Draft-only creation and seal byte-identity for existing hypotheses.
