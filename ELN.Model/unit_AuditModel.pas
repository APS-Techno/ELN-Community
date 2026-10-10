unit unit_AuditModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_AuditRule,
  unit_Item,
  unit_Project,
  unit_ELNDB_Dictionary;

type
  TAuditCategory = (acHealth, acRule);

  TAuditViolation = record
    Category: TAuditCategory;
    RuleTitle: string;
    RuleSeverity: TAuditSeverity;
    ItemId: Integer;
    ItemTitle: string;
    ProjectId: Integer;
    FolderId: Integer;
    ProjectPath: string;
    MissingFiles: string;
    MissingValues: string;
  end;

  TAuditReport = class
  public
    TargetTitle: string;
    Violations: TList<TAuditViolation>;
    TotalItemsChecked: Integer;
    TotalRulesApplied: Integer;
    RunDate: TDateTime;
    constructor Create;
    destructor Destroy; override;
  end;

  TAuditModel = class
  private
    FManager: TObjectManager;
    FItemDic: TItemDictionary;
    function BuildProjectPath(ProjectId, FolderId: Integer): string;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    function GetAllRules: TAuditRules;
    function GetRule(Id: Integer): TAuditRule;
    procedure SaveRule(Rule: TAuditRule);
    procedure DeleteRule(Rule: TAuditRule);
    function RuleExistsFor(ActionTypeId, EquipmentId: Integer;
      ExcludeRuleId: Integer = 0): Boolean;
    function RunAudit(ProjectId, FolderId: Integer): TAuditReport;
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_ItemTypes,
  unit_TimeHelper;


constructor TAuditReport.Create;
begin
  inherited Create;
  Violations := TList<TAuditViolation>.Create;
end;

destructor TAuditReport.Destroy;
begin
  FreeAndNil(Violations);
  inherited;
end;


constructor TAuditModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FItemDic := TItemDictionary.Create;
end;

destructor TAuditModel.Destroy;
begin
  FItemDic.Free;
  inherited;
end;

function TAuditModel.GetAllRules: TAuditRules;
begin
  Result := FManager.Find<TAuditRule>
    .List;
end;

function TAuditModel.GetRule(Id: Integer): TAuditRule;
begin
  Result := FManager.Find<TAuditRule>(Id);
end;

procedure TAuditModel.SaveRule(Rule: TAuditRule);
begin
  if Rule.Id = 0 then
    FManager.Save(Rule);
  FManager.Flush;
end;

procedure TAuditModel.DeleteRule(Rule: TAuditRule);
begin
  FManager.Remove(Rule);
  FManager.Flush;
end;

function TAuditModel.RuleExistsFor(ActionTypeId, EquipmentId: Integer;
  ExcludeRuleId: Integer): Boolean;
var
  Rules: TAuditRules;
begin
  Rules := FManager.Find<TAuditRule>
    .Where(
      (Linq['ActionType.Id'] = ActionTypeId) and
      (Linq['Equipment.Id'] = EquipmentId) and
      (Linq['Id'] <> ExcludeRuleId))
    .List;
  try
    Result := Rules.Count > 0;
  finally
    Rules.Free;
  end;
end;

function TAuditModel.BuildProjectPath(ProjectId, FolderId: Integer): string;
var
  Proj: TProject;
  Folder: TFolder;
begin
  Result := '';
  Proj := FManager.Find<TProject>(ProjectId);
  if Assigned(Proj) then
  begin
    Result := Proj.Title;
    if FolderId > 0 then
    begin
      Folder := FManager.Find<TFolder>(FolderId);
      if Assigned(Folder) then
        Result := Result + ' > ' + Folder.Title;
    end;
  end;
end;


function TAuditModel.RunAudit(ProjectId, FolderId: Integer): TAuditReport;
var
  Rules: TAuditRules;
  Rule: TAuditRule;
  Items: TList<TItem>;
  Item: TItem;
  RuleMap: TObjectDictionary<string, TList<TAuditRule>>;
  Key: string;
  MatchedRules: TList<TAuditRule>;
  RuleFile: TAuditRuleFile;
  RuleValue: TAuditRuleValue;
  F: TFile;
  V: TValue;
  ItemFileTypeIds: TDictionary<Integer, Boolean>;
  ItemValueTypeIds: TDictionary<Integer, Boolean>;
  MissingFiles, MissingValues: string;
  Violation: TAuditViolation;
  UniqueKeys: TDictionary<string, Boolean>;
  WhereExpr: TLinqExpression;
begin
  Result := TAuditReport.Create;
  Result.RunDate := UTCNow;

  WhereExpr :=
    (FItemDic.ProjectID = ProjectId) and
    (FItemDic.IsDeleted = False);
  if FolderId > 0 then
    WhereExpr := WhereExpr and (FItemDic.FolderID = FolderId);
  Items := FManager.Find<TItem>
    .Where(WhereExpr)
    .List;
  try
    Result.TotalItemsChecked := Items.Count;
    Result.TargetTitle := BuildProjectPath(ProjectId, FolderId);

    for Item in Items do
    begin
      if not (Item.Level in [TItemLevel.Proc, TItemLevel.Action]) then
        Continue;

      if Item.Values.Count = 0 then
      begin
        Violation := Default(TAuditViolation);
        Violation.Category := acHealth;
        Violation.RuleTitle := 'Missing values';
        Violation.RuleSeverity := asWarning;
        Violation.ItemId := Item.Id;
        Violation.ItemTitle := Item.Title;
        Violation.ProjectId := Item.ProjectID;
        Violation.FolderId := Item.FolderID;
        Violation.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);
        Violation.MissingValues := '(none)';
        Result.Violations.Add(Violation);
      end;

      if (Item.Level = TItemLevel.Action) and (Item.Files.Count = 0) then
      begin
        Violation := Default(TAuditViolation);
        Violation.Category := acHealth;
        Violation.RuleTitle := 'Missing files';
        Violation.RuleSeverity := asWarning;
        Violation.ItemId := Item.Id;
        Violation.ItemTitle := Item.Title;
        Violation.ProjectId := Item.ProjectID;
        Violation.FolderId := Item.FolderID;
        Violation.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);
        Violation.MissingFiles := '(none)';
        Result.Violations.Add(Violation);
      end;
    end;

    RuleMap := nil;
    Rules := FManager.Find<TAuditRule>
      .Where(Linq['IsActive'] = True)
      .List;
    try
      if Rules.Count > 0 then
      begin
        RuleMap := TObjectDictionary<string, TList<TAuditRule>>.Create([doOwnsValues]);
        UniqueKeys := TDictionary<string, Boolean>.Create;
        try
          for Rule in Rules do
          begin
            if (Rule.ActionType = nil) or (Rule.Equipment = nil) then
              Continue;
            Key := Format('%d|%d', [Rule.ActionType.Id, Rule.Equipment.Id]);
            if not RuleMap.TryGetValue(Key, MatchedRules) then
            begin
              MatchedRules := TList<TAuditRule>.Create;
              RuleMap.Add(Key, MatchedRules);
            end;
            MatchedRules.Add(Rule);
            if not UniqueKeys.ContainsKey(IntToStr(Rule.Id)) then
              UniqueKeys.Add(IntToStr(Rule.Id), True);
          end;
          Result.TotalRulesApplied := UniqueKeys.Count;
        finally
          UniqueKeys.Free;
        end;

        for Item in Items do
        begin
          if (Item.ActionType = nil) or (Item.Equipment = nil) then
            Continue;

          Key := Format('%d|%d', [Item.ActionType.Id, Item.Equipment.Id]);
          if not RuleMap.TryGetValue(Key, MatchedRules) then
            Continue;

          ItemFileTypeIds := TDictionary<Integer, Boolean>.Create;
          try
            for F in Item.Files do
            begin
              if Assigned(F.FileType) then
                ItemFileTypeIds.AddOrSetValue(F.FileType.Id, True);
            end;

            ItemValueTypeIds := TDictionary<Integer, Boolean>.Create;
            try
              for V in Item.Values do
              begin
                if Assigned(V.ValueType) then
                  ItemValueTypeIds.AddOrSetValue(V.ValueType.Id, True);
              end;

              for Rule in MatchedRules do
              begin
                MissingFiles := '';
                MissingValues := '';

                for RuleFile in Rule.RequiredFiles do
                begin
                  if Assigned(RuleFile.FileType) then
                  begin
                    if not ItemFileTypeIds.ContainsKey(RuleFile.FileType.Id) then
                    begin
                      if MissingFiles <> '' then
                        MissingFiles := MissingFiles + ', ';
                      MissingFiles := MissingFiles + RuleFile.FileType.Description;
                    end;
                  end;
                end;

                for RuleValue in Rule.RequiredValues do
                begin
                  if Assigned(RuleValue.ValueType) then
                  begin
                    if not ItemValueTypeIds.ContainsKey(RuleValue.ValueType.Id) then
                    begin
                      if MissingValues <> '' then
                        MissingValues := MissingValues + ', ';
                      MissingValues := MissingValues + RuleValue.ValueType.Title;
                    end;
                  end;
                end;

                if (MissingFiles <> '') or (MissingValues <> '') then
                begin
                  Violation.Category := acRule;
                  Violation.RuleTitle := Rule.Title;
                  Violation.RuleSeverity := Rule.Severity;
                  Violation.ItemId := Item.Id;
                  Violation.ItemTitle := Item.Title;
                  Violation.ProjectId := Item.ProjectID;
                  Violation.FolderId := Item.FolderID;
                  Violation.ProjectPath := BuildProjectPath(Item.ProjectID, Item.FolderID);
                  Violation.MissingFiles := MissingFiles;
                  Violation.MissingValues := MissingValues;
                  Result.Violations.Add(Violation);
                end;
              end;
            finally
              ItemValueTypeIds.Free;
            end;
          finally
            ItemFileTypeIds.Free;
          end;
        end;
      end;
    finally
      RuleMap.Free;
      Rules.Free;
    end;
  finally
    Items.Free;
  end;
end;

end.
