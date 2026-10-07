unit unit_EquipmentModel;

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
  unit_Equipment,
  unit_EquipmentType,
  unit_ActionType,
  unit_ELNDB_Dictionary,
  unit_TimeHelper;

type

  TEquipmentModel = class(TELNModel)
    private
      FDic: TEquipmentDictionary;
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure CreateDefaultData;
      procedure AddEquipment(const EType: TEquipmentType; Model, Manufacturer, Location: string);

      function GetEquipment(const ID: integer): TEquipment;
      function GetEquipments: TEquipments;
      function GetEquipmentsByType(EqTypeId: Integer): TEquipments;
      function CanDelete(ID: Integer): string;
  end;


implementation

{ TEquipmentModel }

procedure TEquipmentModel.AddEquipment(const EType: TEquipmentType; Model, Manufacturer, Location: string);
var
  Equipment: TEquipment;
begin
  Equipment := TEquipment.Create;

  Equipment.EquipmentType := EType;
  Equipment.Model := Model;
  Equipment.Manufacturer := Manufacturer;
  Equipment.Location := Location;
  Equipment.CreatedDate := UTCNow;
  Equipment.CreatedBy := 1;

  FManager.Save(Equipment);
end;

constructor TEquipmentModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TEquipmentDictionary.Create;
end;

procedure TEquipmentModel.CreateDefaultData;
begin
  AddEquipment(FManager.Find<TEquipmentType>(1), 'X-Ray Calc 3', 'Self', 'Workstation');
  AddEquipment(FManager.Find<TEquipmentType>(2), 'CSMIC Sputter', 'SVAC', 'C310B');
  AddEquipment(FManager.Find<TEquipmentType>(6), '3D Profiler', 'Filmetrics', 'C312');
  AddEquipment(FManager.Find<TEquipmentType>(3), 'D8 Discover', 'Bruker', 'Ningbo');
end;

destructor TEquipmentModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TEquipmentModel.GetEquipment(const ID: integer): TEquipment;
begin
  Result := FManager.Find<TEquipment>(ID);
end;

function TEquipmentModel.GetEquipments: TEquipments;
begin
  Result := FManager.Find<TEquipment>.List;
end;

function TEquipmentModel.GetEquipmentsByType(EqTypeId: Integer): TEquipments;
var
  AllEquipments: TEquipments;
  Equip: TEquipment;
begin
  Result := TEquipments.Create;
  AllEquipments := FManager.Find<TEquipment>.List;
  for Equip in AllEquipments do
    if Assigned(Equip.EquipmentType) and (Equip.EquipmentType.Id = EqTypeId) then
      Result.Add(Equip);
end;

function TEquipmentModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

procedure TEquipmentModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TEquipment>);
  FDataSet.Open;
end;

function TEquipmentModel.CanDelete(ID: Integer): string;
var
  AllTypes: TActionTypes;
  AT: TActionType;
  Count: Integer;
begin
  Result := '';
  Count := 0;
  AllTypes := FManager.Find<TActionType>.List;
  for AT in AllTypes do
    if Assigned(AT.Equipment) and (AT.Equipment.Id = ID) then
      Inc(Count);
  if Count > 0 then
    Result := Format('Cannot delete: used by %d action type(s).', [Count]);
end;

end.
