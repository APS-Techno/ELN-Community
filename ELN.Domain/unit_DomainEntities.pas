unit unit_DomainEntities;

{
  The one list of every Aurelius entity in ELN.Domain.

  Aurelius builds its default mapping from the RTTI of the entity classes
  LINKED INTO THE RUNNING EXE; a unit's own "RegisterEntity" only runs if some
  linked unit uses that unit. So without this list the set of tables a host
  knows - and creates in TDatabaseManager.UpdateDatabase - depends on what the
  host happens to link. The 2026-09-27 v8->v9 dry run: the desktop linked no
  unit that names THypothesisStatusChange, so it created three of the four
  v9 tables and reported ClientLog / SubmissionIdempotency as "Removed".

  ELN.DB\ConnectionModule (desktop, MCP server, tests) and
  ELN.WebAPI\unit_DBContext use this unit, so every host maps the same shared
  set (the WebAPI additionally maps its own two tables, see below).
  ELN.Tests\test_DomainEntities scans ELN.Domain\*.pas for [Entity] classes
  and fails if one is neither listed here nor deliberately excluded: a new
  entity goes into BOTH the uses clause and DomainEntityClasses below, or
  into that test's exclusion list with a reason. (Scan limits: top-level
  ELN.Domain\*.pas only, and [Entity] / [Entity, ...] must be an attribute
  line of its own before the "TName = class" declaration.)

  Deliberately NOT listed - WebAPI-owned tables whose DDL is hand-written in
  the WebAPI runbook, with constraints the mapping does not carry
  (uk_key_user, fk_clientlog_user); only the WebAPI maps them:
    TClientLog              (unit_ClientLog)
    TSubmissionIdempotency  (unit_SubmissionIdempotency)
  Dry run #2 (2026-09-27): once the desktop mapped them, its schema update
  dropped both hand-written constraints.

  Entities only - no model units (keeps the linkage rules in
  test_HypothesisLinkage trivially satisfied).
}

interface

/// <summary>Every shared entity class in ELN.Domain (the WebAPI-owned ones
/// are excluded, see above). Naming them here links them into every host
/// that uses this unit.</summary>
function DomainEntityClasses: TArray<TClass>;

implementation

uses
  Aurelius.Mapping.Attributes,
  unit_ActionType,
  unit_AuditLog,
  unit_AuditRule,
  unit_Comment,
  unit_DBSetting,
  unit_Equipment,
  unit_EquipmentType,
  unit_ExperimentTemplate,
  unit_Favorite,
  unit_FileType,
  unit_FileTypeLink,
  unit_Hypothesis,
  unit_HypothesisEvidence,
  unit_HypothesisRun,
  unit_HypothesisStatusChange,
  unit_Item,
  unit_ItemLink,
  unit_LabEntry,
  unit_LinkType,
  unit_Project,
  unit_ProjectGroup,
  unit_ProjectPermission,
  unit_Protocol,
  unit_ProtocolStatusChange,
  unit_Signature,
  unit_Tag,
  unit_Template,
  unit_User,
  unit_UserDevice,
  unit_UserRole,
  unit_UsersHistory,
  unit_UserTreeState,
  unit_ValueType,
  unit_ViewerState;

function DomainEntityClasses: TArray<TClass>;
begin
  Result := [
    TActionType,
    TAuditLog,
    TAuditRule, TAuditRuleFile, TAuditRuleValue,
    TComment,
    TDBSetting,
    TEquipment,
    TEquipmentType,
    TExperimentTemplate,
    TFavorite,
    TFileType,
    TFileTypeLink,
    THypothesis,
    THypothesisEvidence,
    THypothesisRun,
    THypothesisStatusChange,
    unit_Item.TItem, unit_Item.TFile, unit_Item.TValue,
    TItemLink,
    TLabEntry,
    TLinkType,
    TProject, TFolder,
    TProjectGroup,
    TProjectPermission,
    TProtocol,
    TProtocolStatusChange,
    TSignature,
    TTag, TItemTag,
    TTemplate, TTemplateEquipmentType, TTemplateEquipment,
    TUser,
    TUserDevice,
    TUserRole,
    TUsersHistory,
    TUserTreeState,
    TValueType,
    TViewerState
  ];
end;

procedure RegisterDomainEntities;
var
  C: TClass;
begin
  for C in DomainEntityClasses do
    RegisterEntity(C);
end;

initialization
  RegisterDomainEntities;

end.
