unit unit_AuditLogModel;

interface

uses
  SysUtils,
  System.Generics.Collections,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  unit_TELNModel,
  unit_AuditLog,
  unit_ELNDB_Dictionary;

type
  TAuditLogModel = class(TELNModel)
  private
    FDic: TAuditLogDictionary;
    FManager: TObjectManager;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    procedure OpenDataSet; override;

    function GetLogs(DateFrom, DateTo: TDateTime;
      EntityType: Integer; Operation: Integer;
      UserId: Integer): TAuditLogs;
  end;

implementation


constructor TAuditLogModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TAuditLogDictionary.Create;
end;

destructor TAuditLogModel.Destroy;
begin
  FDic.Free;
  inherited;
end;

procedure TAuditLogModel.OpenDataSet;
begin
end;

function TAuditLogModel.GetLogs(DateFrom, DateTo: TDateTime;
  EntityType: Integer; Operation: Integer;
  UserId: Integer): TAuditLogs;
var
  Criteria: TCriteria;
begin
  Criteria := FManager.Find<TAuditLog>
    .Where(FDic.Timestamp >= DateFrom)
    .Where(FDic.Timestamp <= DateTo + 1);

  if EntityType >= 0 then
    Criteria.Where(FDic.EntityType = EntityType);

  if Operation >= 0 then
    Criteria.Where(FDic.Operation = Operation);

  if UserId > 0 then
    Criteria.Where(FDic.UserId = UserId);

  Result := Criteria
    .OrderBy(FDic.Timestamp, False)
    .List<TAuditLog>;
end;

end.
