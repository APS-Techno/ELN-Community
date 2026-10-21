unit unit_ActionDialogVM;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  unit_ItemTypes, unit_Item, unit_ActionType, unit_Equipment, unit_EquipmentType,
  unit_ValueType, unit_ActionTypeModel, unit_EquipmentModel, unit_ItemModel;

type
  TValueFields = record
    TypeId: Integer;
    RecType: TRecType;
    Value: Double;
    Tol: Double;
    Description: string;
    class function Read(V: TValue): TValueFields; static;
    function SameAs(const Other: TValueFields): Boolean;
  end;
  TValueRow = record
    Quantity: string;
    Value: string;
    Kind: string;
    Note: string;
  end;

  TActionDialogVM = class
  private
    FActionTypeModel: TActionTypeModel;
    FEquipmentModel: TEquipmentModel;
    FItemModel: TItemModel;
    FUserId: Integer;

    FAllowedLevels: TItemLevels;
    FLevel: TItemLevel;
    FItemTypes: TArray<TItemType>;
    FSelectedItemTypeIndex: Integer;

    FAllActionTypes: TActionTypes;
    FActionTypes: TActionTypes;
    FSelectedActionTypeIndex: Integer;

    FEquipments: TEquipments;
    FSelectedEquipmentIndex: Integer;

    FTitle: string;
    FDescription: string;
    FProperties: string;

    FItem: TItem;
    FOwnItem: Boolean;
    FIsEditMode: Boolean;
    FValuesDisplay: TArray<string>;
    FValueRows: TArray<TValueRow>;

    FOnChanged: TNotifyEvent;

    procedure FilterItemTypes;
    procedure FilterActionTypes;
    procedure FilterEquipments;
    procedure DoChanged;
    procedure RefreshValuesDisplay;
    function BuildValueRow(Val: TValue): TValueRow;
    function FormatValueLine(Val: TValue): string;
  public
    constructor Create(
      AActionTypeModel: TActionTypeModel;
      AEquipmentModel: TEquipmentModel;
      AItemModel: TItemModel;
      AUserId: Integer);
    destructor Destroy; override;

    procedure LoadForNew(AllowedLevels: TItemLevels);
    procedure LoadForEdit(Item: TItem; AllowedLevels: TItemLevels);

    procedure SetLevel(Value: TItemLevel);
    procedure SetItemTypeIndex(Index: Integer);
    procedure SetActionTypeIndex(Index: Integer);

    procedure SetEquipmentIndex(Index: Integer);

    procedure AddValue(AValueType: TValueType; ARecType: TRecType;
      AValue, ATol: Double; const ADesc: string);
    procedure DeleteValue(Index: Integer);
    procedure ValueEdited(Value: TValue; const Before: TValueFields);

    procedure AddActionType(const ATitle: string; AKind: TActionKind);
    procedure AddEquipment(const AModel, AManufacturer, ALocation: string);

    procedure ApplyTo(Item: TItem);

    function GetSelectedItemType: TItemType;
    function GetSelectedActionType: TActionType;

    function ShowValues: Boolean;
    function CanSave: Boolean;
    function CanAddActionType: Boolean;
    function CanAddEquipment: Boolean;
    function ShowLevelSelector: Boolean;

    property AllowedLevels: TItemLevels read FAllowedLevels;
    property Level: TItemLevel read FLevel;
    property ItemTypes: TArray<TItemType> read FItemTypes;
    property SelectedItemTypeIndex: Integer read FSelectedItemTypeIndex;
    property ActionTypes: TActionTypes read FActionTypes;
    property SelectedActionTypeIndex: Integer read FSelectedActionTypeIndex;
    property Equipments: TEquipments read FEquipments;
    property SelectedEquipmentIndex: Integer read FSelectedEquipmentIndex;
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property Properties: string read FProperties write FProperties;
    property IsEditMode: Boolean read FIsEditMode;
    property ValuesDisplay: TArray<string> read FValuesDisplay;
    property ValueRows: TArray<TValueRow> read FValueRows;
    property Item: TItem read FItem;

    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  unit_ValueTypeModel,
  unit_ValueSource,
  unit_TimeHelper;

class function TValueFields.Read(V: TValue): TValueFields;
begin
  if Assigned(V.ValueType) then
    Result.TypeId := V.ValueType.Id
  else
    Result.TypeId := 0;
  Result.RecType := V.RecType;
  Result.Value := V.Value;
  Result.Tol := V.Tol;
  Result.Description := V.Description;
end;

function TValueFields.SameAs(const Other: TValueFields): Boolean;
begin
  Result := (TypeId = Other.TypeId) and (RecType = Other.RecType) and
    (Value = Other.Value) and (Tol = Other.Tol) and
    (Description = Other.Description);
end;


constructor TActionDialogVM.Create(
  AActionTypeModel: TActionTypeModel;
  AEquipmentModel: TEquipmentModel;
  AItemModel: TItemModel;
  AUserId: Integer);
begin
  inherited Create;
  FActionTypeModel := AActionTypeModel;
  FEquipmentModel := AEquipmentModel;
  FItemModel := AItemModel;
  FUserId := AUserId;
  FActionTypes := TActionTypes.Create;
  FEquipments := TEquipments.Create;
  FSelectedItemTypeIndex := -1;
  FSelectedActionTypeIndex := -1;
  FSelectedEquipmentIndex := -1;
end;

destructor TActionDialogVM.Destroy;
begin
  if FOwnItem then
    FreeAndNil(FItem);
  FreeAndNil(FActionTypes);
  FreeAndNil(FEquipments);
  inherited;
end;

procedure TActionDialogVM.DoChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;


procedure TActionDialogVM.FilterItemTypes;
var
  ItemType: TItemType;
  Count: Integer;
begin
  SetLength(FItemTypes, 0);
  Count := 0;
  for ItemType := Low(TItemType) to High(TItemType) do
    if ItemType in [TItemType.Synthesis, TItemType.Treatment,
                    TItemType.Measurement, TItemType.Testing,
                    TItemType.Computing, TItemType.Characterization] then
    begin
      SetLength(FItemTypes, Count + 1);
      FItemTypes[Count] := ItemType;
      Inc(Count);
    end;

  if Length(FItemTypes) > 0 then
    FSelectedItemTypeIndex := 0
  else
    FSelectedItemTypeIndex := -1;

  FilterActionTypes;
end;

procedure TActionDialogVM.FilterActionTypes;
var
  AType: TActionType;
  SelItemType: TItemType;
begin
  FreeAndNil(FActionTypes);
  FActionTypes := TActionTypes.Create;
  FSelectedActionTypeIndex := -1;

  if (FSelectedItemTypeIndex < 0) or (FSelectedItemTypeIndex > High(FItemTypes)) then
  begin
    FilterEquipments;
    Exit;
  end;

  SelItemType := FItemTypes[FSelectedItemTypeIndex];

  FAllActionTypes := FActionTypeModel.GetTypes;
  for AType in FAllActionTypes do
    if AType.ItemType = SelItemType then
      FActionTypes.Add(AType);

  FilterEquipments;
end;

procedure TActionDialogVM.FilterEquipments;
var
  SelActionType: TActionType;
  AllEquip: TEquipments;
  I: Integer;
begin
  FreeAndNil(FEquipments);
  FEquipments := TEquipments.Create;
  FSelectedEquipmentIndex := -1;

  if (FSelectedActionTypeIndex < 0) or
     (FSelectedActionTypeIndex >= FActionTypes.Count) then
    Exit;

  SelActionType := FActionTypes[FSelectedActionTypeIndex];
  if not Assigned(SelActionType.EquipmentType) then
    Exit;

  AllEquip := FEquipmentModel.GetEquipmentsByType(SelActionType.EquipmentType.Id);
  for I := 0 to AllEquip.Count - 1 do
    FEquipments.Add(AllEquip[I]);
end;


procedure TActionDialogVM.LoadForNew(AllowedLevels: TItemLevels);
begin
  FIsEditMode := False;
  FAllowedLevels := AllowedLevels;
  FItem := TItem.Create;
  FOwnItem := True;
  FTitle := '';
  FDescription := '';
  FProperties := '';

  if TItemLevel.Proc in AllowedLevels then
    FLevel := TItemLevel.Proc
  else if TItemLevel.Action in AllowedLevels then
    FLevel := TItemLevel.Action;

  FilterItemTypes;
  DoChanged;
end;

procedure TActionDialogVM.LoadForEdit(Item: TItem; AllowedLevels: TItemLevels);
var
  I: Integer;
begin
  FIsEditMode := True;
  FAllowedLevels := AllowedLevels;
  FItem := Item;
  FLevel := Item.Level;
  FTitle := Item.Title;
  FDescription := Item.Description;
  FProperties := Item.Properties;

  FilterItemTypes;

  FSelectedItemTypeIndex := -1;
  for I := 0 to High(FItemTypes) do
    if FItemTypes[I] = Item.Type_ then
    begin
      FSelectedItemTypeIndex := I;
      Break;
    end;

  FilterActionTypes;

  FSelectedActionTypeIndex := -1;
  if Assigned(Item.ActionType) then
    for I := 0 to FActionTypes.Count - 1 do
      if FActionTypes[I].Id = Item.ActionType.Id then
      begin
        FSelectedActionTypeIndex := I;
        Break;
      end;

  FilterEquipments;

  FSelectedEquipmentIndex := -1;
  if Assigned(Item.Equipment) then
    for I := 0 to FEquipments.Count - 1 do
      if FEquipments[I].Id = Item.Equipment.Id then
      begin
        FSelectedEquipmentIndex := I;
        Break;
      end;

  RefreshValuesDisplay;
  DoChanged;
end;


procedure TActionDialogVM.SetLevel(Value: TItemLevel);
begin
  FLevel := Value;
  FilterItemTypes;
  DoChanged;
end;

procedure TActionDialogVM.SetItemTypeIndex(Index: Integer);
begin
  FSelectedItemTypeIndex := Index;
  FilterActionTypes;
  DoChanged;
end;

procedure TActionDialogVM.SetActionTypeIndex(Index: Integer);
var
  SelAT: TActionType;
  I: Integer;
begin
  FSelectedActionTypeIndex := Index;
  FilterEquipments;

  FSelectedEquipmentIndex := -1;
  if (FSelectedActionTypeIndex >= 0) and (FSelectedActionTypeIndex < FActionTypes.Count) then
  begin
    SelAT := FActionTypes[FSelectedActionTypeIndex];
    if Assigned(SelAT.Equipment) then
      for I := 0 to FEquipments.Count - 1 do
        if FEquipments[I].Id = SelAT.Equipment.Id then
        begin
          FSelectedEquipmentIndex := I;
          Break;
        end;

    if (FSelectedEquipmentIndex < 0) and (FEquipments.Count > 0) then
      FSelectedEquipmentIndex := 0;

    if FTitle = '' then
      FTitle := SelAT.Title;
  end;

  DoChanged;
end;

procedure TActionDialogVM.SetEquipmentIndex(Index: Integer);
begin
  FSelectedEquipmentIndex := Index;
end;


procedure TActionDialogVM.AddValue(AValueType: TValueType; ARecType: TRecType;
  AValue, ATol: Double; const ADesc: string);
var
  V: TValue;
begin
  if not Assigned(FItem) then Exit;

  if FIsEditMode then
    FItemModel.AddValue(AValueType, ARecType, AValue, FUserId, FItem, ATol,
      ADesc, TValueSourceInfo.Manual)
  else
  begin
    V := TValue.Create;
    V.ValueType := AValueType;
    V.RecType := ARecType;
    V.Value := AValue;
    V.Tol := ATol;
    V.Description := ADesc;
    V.Item := FItem;
    ApplySource(V, TValueSourceInfo.Manual);
    FItem.Values.Add(V);
  end;

  RefreshValuesDisplay;
  DoChanged;
end;

procedure TActionDialogVM.DeleteValue(Index: Integer);
begin
  if not Assigned(FItem) then Exit;
  if (Index < 0) or (Index >= FItem.Values.Count) then Exit;

  if FIsEditMode then
    FItemModel.RemoveValue(FItem.Values[Index], FItem, FUserId)
  else
    FItem.Values.Delete(Index);

  RefreshValuesDisplay;
  DoChanged;
end;
procedure TActionDialogVM.ValueEdited(Value: TValue; const Before: TValueFields);
begin
  if not Assigned(FItem) then Exit;
  if FIsEditMode then
  begin
    if not Before.SameAs(TValueFields.Read(Value)) then
    begin
      Value.ModifiedDate := UTCNow;
      Value.ModifiedBy := FUserId;
    end;
    if not FItemModel.UpdateItem(FItem, FUserId) then Exit;
  end;
  RefreshValuesDisplay;
  DoChanged;
end;



procedure TActionDialogVM.AddActionType(const ATitle: string; AKind: TActionKind);
var
  SelItemType: TItemType;
  I: Integer;
begin
  if FSelectedItemTypeIndex < 0 then Exit;
  SelItemType := FItemTypes[FSelectedItemTypeIndex];

  FActionTypeModel.AddType(ATitle, AKind, SelItemType, nil);

  FilterActionTypes;

  for I := 0 to FActionTypes.Count - 1 do
    if FActionTypes[I].Title = ATitle then
    begin
      FSelectedActionTypeIndex := I;
      FilterEquipments;
      Break;
    end;

  DoChanged;
end;

procedure TActionDialogVM.AddEquipment(const AModel, AManufacturer, ALocation: string);
var
  SelActionType: TActionType;
  I: Integer;
begin
  if FSelectedActionTypeIndex < 0 then Exit;
  SelActionType := FActionTypes[FSelectedActionTypeIndex];
  if not Assigned(SelActionType.EquipmentType) then Exit;

  FEquipmentModel.AddEquipment(SelActionType.EquipmentType, AModel, AManufacturer, ALocation);

  var AllEquip := FEquipmentModel.GetEquipmentsByType(SelActionType.EquipmentType.Id);
  for I := 0 to AllEquip.Count - 1 do
    if AllEquip[I].Model = AModel then
    begin
      FEquipments.Add(AllEquip[I]);
      FSelectedEquipmentIndex := FEquipments.Count - 1;
      Break;
    end;

  DoChanged;
end;


procedure TActionDialogVM.ApplyTo(Item: TItem);
var
  Value: TValue;
begin
  Item.Level := FLevel;

  if (FSelectedItemTypeIndex >= 0) and (FSelectedItemTypeIndex <= High(FItemTypes)) then
    Item.Type_ := FItemTypes[FSelectedItemTypeIndex];

  Item.Title := FTitle;
  Item.Description := FDescription;

  if (FSelectedActionTypeIndex >= 0) and (FSelectedActionTypeIndex < FActionTypes.Count) then
    Item.ActionType := FActionTypes[FSelectedActionTypeIndex]
  else
    Item.ActionType := nil;

  if (FSelectedEquipmentIndex >= 0) and (FSelectedEquipmentIndex < FEquipments.Count) then
    Item.Equipment := FEquipments[FSelectedEquipmentIndex]
  else
    Item.Equipment := nil;

  Item.Properties := FProperties;

  if not FIsEditMode and Assigned(FItem) then
    while FItem.Values.Count > 0 do
    begin
      Value := FItem.Values.Extract(FItem.Values[0]);
      Value.Item := Item;
      Item.Values.Add(Value);
    end;
end;


function TActionDialogVM.GetSelectedItemType: TItemType;
begin
  if (FSelectedItemTypeIndex >= 0) and (FSelectedItemTypeIndex <= High(FItemTypes)) then
    Result := FItemTypes[FSelectedItemTypeIndex]
  else
    Result := TItemType.Other;
end;

function TActionDialogVM.GetSelectedActionType: TActionType;
begin
  if (FSelectedActionTypeIndex >= 0) and (FSelectedActionTypeIndex < FActionTypes.Count) then
    Result := FActionTypes[FSelectedActionTypeIndex]
  else
    Result := nil;
end;


function TActionDialogVM.ShowValues: Boolean;
begin
  Result := True;
end;

function TActionDialogVM.CanSave: Boolean;
begin
  Result := Trim(FTitle) <> '';
end;

function TActionDialogVM.CanAddActionType: Boolean;
begin
  Result := FSelectedItemTypeIndex >= 0;
end;

function TActionDialogVM.CanAddEquipment: Boolean;
begin
  Result := (FSelectedActionTypeIndex >= 0) and
            (FSelectedActionTypeIndex < FActionTypes.Count) and
            Assigned(FActionTypes[FSelectedActionTypeIndex].EquipmentType);
end;

function TActionDialogVM.ShowLevelSelector: Boolean;
begin
  Result := True;
end;


function TActionDialogVM.BuildValueRow(Val: TValue): TValueRow;
begin
  Result.Quantity := Val.ValueType.Symbol;
  Result.Value := FormatSIValue(Val.Value, Val.ValueType.Units);
  case Val.RecType of
    EXP_CONDITION: Result.Kind := 'Condition';
    TEST_RESULT:   Result.Kind := 'Result';
  else
    Result.Kind := '';
  end;
  Result.Note := Val.Description;
end;

function TActionDialogVM.FormatValueLine(Val: TValue): string;
var
  Row: TValueRow;
begin
  Row := BuildValueRow(Val);
  Result := Row.Quantity + ' = ' + Row.Value + ' [' + Row.Kind + ']';
  if Row.Note <> '' then
    Result := Result + '  '#$2014' ' + Row.Note;
end;

procedure TActionDialogVM.RefreshValuesDisplay;
var
  I: Integer;
begin
  if not Assigned(FItem) then
  begin
    SetLength(FValuesDisplay, 0);
    SetLength(FValueRows, 0);
    Exit;
  end;
  SetLength(FValuesDisplay, FItem.Values.Count);
  SetLength(FValueRows, FItem.Values.Count);
  for I := 0 to FItem.Values.Count - 1 do
  begin
    FValuesDisplay[I] := FormatValueLine(FItem.Values[I]);
    FValueRows[I] := BuildValueRow(FItem.Values[I]);
  end;
end;


end.
