unit unit_EquipmentTypeModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  System.Generics.Collections,
  unit_TELNModel,
  unit_EquipmentType,
  unit_Equipment,
  unit_ActionType,
  unit_ELNDB_Dictionary,
  unit_TimeHelper;

type

  TEquipmentTypeModel = class(TELNModel)
    private
      FDic: TEquipmentTypeDictionary;
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure AddType(const EType, Description: string);
      function GetType(const ID: integer): TEquipmentType;
      procedure CreateDefaultData;
      function CanDelete(ID: Integer): string;
  end;

implementation


procedure TEquipmentTypeModel.AddType(const EType, Description: string);
var
  AType: TEquipmentType;
begin
  AType := TEquipmentType.Create;

  AType.Type_ := EType;
  AType.Description := Description;
  AType.CreatedDate := UTCNow;
  AType.CreatedBy := 1;

  FManager.Save(AType);
end;

constructor TEquipmentTypeModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TEquipmentTypeDictionary.Create;
end;

destructor TEquipmentTypeModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

procedure TEquipmentTypeModel.CreateDefaultData;
begin
  AddType('Software','');
  AddType('Sputter','Magnetron sputtering system');
  AddType('Diffractometer','');
  AddType('SEM','');
  AddType('Tribotester','');
  AddType('3D Profiler','');
end;

function TEquipmentTypeModel.GetType(const ID: integer): TEquipmentType;
begin
  Result := FManager.Find<TEquipmentType>(ID);
end;

function TEquipmentTypeModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

procedure TEquipmentTypeModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TEquipmentType>);
  FDataSet.Open;
end;

function TEquipmentTypeModel.CanDelete(ID: Integer): string;
var
  ATDic: TActionTypeDictionary;
  AllEquip: TEquipments;
  Equip: TEquipment;
  EquipCount, ATCount: Integer;
begin
  Result := '';

  // In-memory filter — dictionary nav broken due to field name typo in TEquipment
  EquipCount := 0;
  AllEquip := FManager.Find<TEquipment>.List;
  for Equip in AllEquip do
    if Assigned(Equip.EquipmentType) and (Equip.EquipmentType.Id = ID) then
      Inc(EquipCount);

  ATDic := TActionTypeDictionary.Create;
  try
    ATCount := FManager.Find<TActionType>.Where(ATDic.Equipmenttypeid.Id = ID).List.Count;
  finally
    ATDic.Free;
  end;

  if (EquipCount > 0) or (ATCount > 0) then
    Result := Format('Cannot delete: used by %d equipment(s) and %d action type(s).', [EquipCount, ATCount]);
end;

end.
