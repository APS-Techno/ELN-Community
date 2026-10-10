unit unit_ActionTypeModel;

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
  unit_ActionType,
  unit_ItemTypes,
  unit_FileType,
  unit_FileTypeLink,
  unit_Item,
  unit_EquipmentType,
  unit_ELNDB_Dictionary,
  unit_TimeHelper;

type

  TActionTypeModel = class(TELNModel)
    private
      FDic: TActionTypeDictionary;
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure CreateDefaultData;
      procedure AddType(const Name: string; Kind: TActionKind;
                        AItemType: TItemType; Equip: TEquipmentType);
      function GetType(const ID: integer): TActionType;
      function GetTypeByTitle(const Title: string): TActionType;
      function GetTypes: TActionTypes;
      function GetTypesByItemType(AItemType: TItemType): TActionTypes;
      procedure AddFileTypeLink(AActionType: TActionType; AFileType: TFileType);
      procedure RemoveFileTypeLink(AActionType: TActionType; AFileType: TFileType);
      function GetFileTypes(ActionTypeID: Integer): TFileTypes;
      function GetFileTypeLinks(ActionTypeID: Integer): TFileTypeLinks;
      function CanDelete(ID: Integer): string;
  end;

implementation


procedure TActionTypeModel.AddType(const Name: string; Kind: TActionKind;
                                   AItemType: TItemType; Equip: TEquipmentType);
var
  AType: TActionType;
begin
  AType := TActionType.Create;

  AType.Kind := Kind;
  AType.ItemType := AItemType;
  AType.Title := Name;
  AType.EquipmentType := Equip;
  AType.CreatedDate := UTCNow;
  AType.CreatedBy := 1;
  FManager.Save(AType);
end;

constructor TActionTypeModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TActionTypeDictionary.Create;
end;

procedure TActionTypeModel.CreateDefaultData;
begin
  AddType('Depostion', TActionKind.Synthesys, TItemType.Synthesis, FManager.Find<TEquipmentType>(2));
  AddType('XRD', TActionKind.Testing, TItemType.Characterization, FManager.Find<TEquipmentType>(3));
  AddType('XPS', TActionKind.Testing, TItemType.Characterization, nil);
  AddType('SEM', TActionKind.Testing, TItemType.Characterization, FManager.Find<TEquipmentType>(4));
  AddType('TEM', TActionKind.Testing, TItemType.Characterization, nil);
  AddType('Raman', TActionKind.Testing, TItemType.Characterization, nil);
  AddType('3D Profiling', TActionKind.Testing, TItemType.Characterization, FManager.Find<TEquipmentType>(6));
  AddType('Indentation', TActionKind.Testing, TItemType.Testing, nil);
  AddType('Tribotest', TActionKind.Testing, TItemType.Testing, FManager.Find<TEquipmentType>(5));

  AddType('Transmittance', TActionKind.Measurement, TItemType.Measurement, nil);
  AddType('Wettability', TActionKind.Measurement, TItemType.Measurement, nil);

  AddType('XRR Simulation', TActionKind.Simulation, TItemType.Computing, FManager.Find<TEquipmentType>(1));
  AddType('MD Simulation', TActionKind.Simulation, TItemType.Computing, FManager.Find<TEquipmentType>(1));
  AddType('FEM Simulation', TActionKind.Simulation, TItemType.Computing, FManager.Find<TEquipmentType>(1));
end;

destructor TActionTypeModel.Destroy;
begin

  inherited;
end;

function TActionTypeModel.GetType(const ID: integer): TActionType;
begin
  Result := FManager.Find<TActionType>(ID);
end;

function TActionTypeModel.GetTypeByTitle(const Title: string): TActionType;
var
  List: TActionTypes;
  AT: TActionType;
begin
  Result := nil;
  List := FManager.Find<TActionType>.List;
  for AT in List do
    if SameText(AT.Title, Title) then
      Exit(AT);
end;

function TActionTypeModel.GetTypes: TActionTypes;
begin
  Result := FManager.Find<TActionType>.List;
end;

function TActionTypeModel.GetTypesByItemType(AItemType: TItemType): TActionTypes;
begin
  Result := FManager.Find<TActionType>
    .Where(FDic.ItemType = Ord(AItemType))
    .List;
end;

procedure TActionTypeModel.AddFileTypeLink(AActionType: TActionType;
  AFileType: TFileType);
var
  Link: TFileTypeLink;
begin
  Link := TFileTypeLink.Create;
  Link.ActionType := AActionType;
  Link.FileType := AFileType;
  Link.CreatedDate := UTCNow;
  Link.CreatedBy := 1;
  FManager.Save(Link);
  FManager.Flush;
end;

function TActionTypeModel.GetFileTypes(ActionTypeID: Integer): TFileTypes;
var
  Links: TFileTypeLinks;
  Link: TFileTypeLink;
  Dic: TFileTypeLinkDictionary;
begin
  Result := TFileTypes.Create;
  Dic := TFileTypeLinkDictionary.Create;
  try
    Links := FManager.Find<TFileTypeLink>
      .Where(Dic.ActionType.Id = ActionTypeID)
      .List;
    for Link in Links do
      Result.Add(Link.FileType);
  finally
    Dic.Free;
  end;
end;

function TActionTypeModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

procedure TActionTypeModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TActionType>);
  FDataSet.Open;
end;

procedure TActionTypeModel.RemoveFileTypeLink(AActionType: TActionType;
  AFileType: TFileType);
var
  Links: TFileTypeLinks;
  Link: TFileTypeLink;
  Dic: TFileTypeLinkDictionary;
begin
  Dic := TFileTypeLinkDictionary.Create;
  try
    Links := FManager.Find<TFileTypeLink>
      .Where((Dic.ActionType.Id = AActionType.Id) and (Dic.FileType_.Id = AFileType.Id))
      .List;
    for Link in Links do
      FManager.Remove(Link);
    FManager.Flush;
  finally
    Dic.Free;
  end;
end;

function TActionTypeModel.GetFileTypeLinks(ActionTypeID: Integer): TFileTypeLinks;
var
  Dic: TFileTypeLinkDictionary;
begin
  Dic := TFileTypeLinkDictionary.Create;
  try
    Result := FManager.Find<TFileTypeLink>
      .Where(Dic.ActionType.Id = ActionTypeID)
      .List;
  finally
    Dic.Free;
  end;
end;

function TActionTypeModel.CanDelete(ID: Integer): string;
var
  ItemDic: TItemDictionary;
  LinkDic: TFileTypeLinkDictionary;
  ItemCount, LinkCount: Integer;
begin
  Result := '';
  ItemDic := TItemDictionary.Create;
  LinkDic := TFileTypeLinkDictionary.Create;
  try
    ItemCount := FManager.Find<TItem>.Where(ItemDic.ActionType.Id = ID).List.Count;
    LinkCount := FManager.Find<TFileTypeLink>.Where(LinkDic.ActionType.Id = ID).List.Count;
    if (ItemCount > 0) or (LinkCount > 0) then
      Result := Format('Cannot delete: used by %d item(s) and %d file type link(s).', [ItemCount, LinkCount]);
  finally
    ItemDic.Free;
    LinkDic.Free;
  end;
end;

end.
