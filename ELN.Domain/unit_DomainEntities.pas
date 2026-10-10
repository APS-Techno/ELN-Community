unit unit_DomainEntities;

{
  Aurelius registers only linked entity units. Add every shared entity to
  both the uses clause and DomainEntityClasses so host mappings do not vary
  with incidental linkage.

  TClientLog and TSubmissionIdempotency are WebAPI-owned and excluded here:
  their hand-written constraints are not represented in these mappings.
  Keep this unit entity-only to preserve the MCP human-gate boundary.
}

interface

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
