unit editor_ActionTypes;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, EditorBase, Data.DB, Vcl.StdCtrls,
  Vcl.Buttons, RzDBNav, Vcl.Grids, Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask,
  Vcl.DBCtrls, Vcl.CheckLst, System.Generics.Collections,
  unit_ActionType;

type
  TedActionTypes = class(TfrmEditorBase)
    lblTitle: TLabel;
    lblKind: TLabel;
    lblItemType: TLabel;
    lblEquipmentType: TLabel;
    lblEquipment: TLabel;
    lblDescription: TLabel;
    lblFileTypes: TLabel;
    edTitle: TDBEdit;
    cbKind: TComboBox;
    cbItemType: TComboBox;
    cbEquipmentType: TComboBox;
    cbEquipment: TComboBox;
    edDescription: TDBEdit;
    clbFileTypes: TCheckListBox;
    procedure cbKindChange(Sender: TObject);
    procedure cbItemTypeChange(Sender: TObject);
    procedure cbEquipmentTypeChange(Sender: TObject);
    procedure cbEquipmentChange(Sender: TObject);
    procedure clbFileTypesClickCheck(Sender: TObject);
  private
    FEquipTypeIds: TList<Integer>;
    FEquipIds: TList<Integer>;
    FFileTypeIds: TList<Integer>;
    FAllFileTypeNames: TStringList;  
    FAllFileTypeIds: TList<Integer>; // full list: IDs (parallel)
    FFilterEdit: TEdit;
    procedure DataSetBeforeDelete(DataSet: TDataSet);
    procedure DataSetAfterInsert(DataSet: TDataSet);
    procedure SyncCombos(Sender: TObject; Field: TField);
    procedure RefreshEquipmentCombo(AT: TActionType);
    procedure RefreshFileTypeChecks;
    procedure ApplyFileTypeFilter(Sender: TObject);
    procedure KindGetText(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure ItemTypeGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  protected
    procedure LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>); override;
  public
    destructor Destroy; override;
    procedure ShowEditor(ADataSet, AEquipTypeLookup, AFileTypeLookup: TDataSet);
  end;

var
  edActionTypes: TedActionTypes;

implementation

uses
  Aurelius.Bind.Dataset,
  unit_Equipment,
  unit_ItemTypes,
  unit_FileType,
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

destructor TedActionTypes.Destroy;
begin
  FEquipTypeIds.Free;
  FEquipIds.Free;
  FFileTypeIds.Free;
  FAllFileTypeNames.Free;
  FAllFileTypeIds.Free;
  inherited;
end;

procedure TedActionTypes.ShowEditor(ADataSet, AEquipTypeLookup, AFileTypeLookup: TDataSet);
begin
  cbKind.Items.Clear;
  cbKind.Items.Add('Synthesys');
  cbKind.Items.Add('Testing');
  cbKind.Items.Add('Measurement');
  cbKind.Items.Add('Analysis');
  cbKind.Items.Add('Simulation');
  cbKind.Items.Add('Other');

  cbItemType.Items.Clear;
  cbItemType.Items.Add('Synthesis');
  cbItemType.Items.Add('Treatment');
  cbItemType.Items.Add('Measurement');
  cbItemType.Items.Add('Testing');
  cbItemType.Items.Add('Characterization');
  cbItemType.Items.Add('Computing');
  cbItemType.Items.Add('Specimen');
  cbItemType.Items.Add('Model');
  cbItemType.Items.Add('Other');

  if FEquipTypeIds = nil then
    FEquipTypeIds := TList<Integer>.Create
  else
    FEquipTypeIds.Clear;
  cbEquipmentType.Items.Clear;
  cbEquipmentType.Items.Add('(none)');
  FEquipTypeIds.Add(0);

  AEquipTypeLookup.DisableControls;
  try
    AEquipTypeLookup.First;
    while not AEquipTypeLookup.Eof do
    begin
      cbEquipmentType.Items.Add(AEquipTypeLookup.FieldByName('Type_').AsString);
      FEquipTypeIds.Add(AEquipTypeLookup.FieldByName('Id').AsInteger);
      AEquipTypeLookup.Next;
    end;
    AEquipTypeLookup.First;
  finally
    AEquipTypeLookup.EnableControls;
  end;

  if FEquipIds = nil then
    FEquipIds := TList<Integer>.Create
  else
    FEquipIds.Clear;

  if FAllFileTypeNames = nil then
    FAllFileTypeNames := TStringList.Create
  else
    FAllFileTypeNames.Clear;
  if FAllFileTypeIds = nil then
    FAllFileTypeIds := TList<Integer>.Create
  else
    FAllFileTypeIds.Clear;
  if FFileTypeIds = nil then
    FFileTypeIds := TList<Integer>.Create
  else
    FFileTypeIds.Clear;

  AFileTypeLookup.DisableControls;
  try
    AFileTypeLookup.First;
    while not AFileTypeLookup.Eof do
    begin
      FAllFileTypeNames.Add(AFileTypeLookup.FieldByName('Ext').AsString + ' - ' +
        AFileTypeLookup.FieldByName('Description').AsString);
      FAllFileTypeIds.Add(AFileTypeLookup.FieldByName('Id').AsInteger);
      AFileTypeLookup.Next;
    end;
    AFileTypeLookup.First;
  finally
    AFileTypeLookup.EnableControls;
  end;

  if not Assigned(FFilterEdit) then
  begin
    FFilterEdit := TEdit.Create(Self);
    FFilterEdit.Parent := clbFileTypes.Parent;
    FFilterEdit.Left := clbFileTypes.Left;
    FFilterEdit.Top := clbFileTypes.Top;
    FFilterEdit.Width := clbFileTypes.Width;
    FFilterEdit.Height := 23;
    FFilterEdit.TextHint := 'Filter by extension...';
    FFilterEdit.OnChange := ApplyFileTypeFilter;
    clbFileTypes.Top := clbFileTypes.Top + 25;
    clbFileTypes.Height := clbFileTypes.Height - 25;
  end;
  FFilterEdit.Text := '';

  ApplyFileTypeFilter(nil);

  DataSource.OnDataChange := SyncCombos;
  DataSource.DataSet := ADataSet;
  ADataSet.BeforeDelete := DataSetBeforeDelete;
  ADataSet.AfterInsert := DataSetAfterInsert;
  ADataSet.FieldByName('Kind').OnGetText := KindGetText;
  ADataSet.FieldByName('ItemType').OnGetText := ItemTypeGetText;
  ShowModal;
  ADataSet.BeforeDelete := nil;
  ADataSet.AfterInsert := nil;
  DataSource.DataSet := nil;
end;

procedure TedActionTypes.DataSetAfterInsert(DataSet: TDataSet);
begin
  DataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
end;

procedure TedActionTypes.DataSetBeforeDelete(DataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.ActionTypes.CanDelete(DataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

procedure TedActionTypes.SyncCombos(Sender: TObject; Field: TField);
var
  AT: TActionType;
  i: Integer;
begin
  cbKind.ItemIndex := -1;
  cbItemType.ItemIndex := -1;
  cbEquipmentType.ItemIndex := 0;

  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active or
     (DataSource.DataSet.RecordCount = 0) then
    Exit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if not Assigned(AT) then
    Exit;

  cbKind.ItemIndex := Ord(AT.Kind);

  cbItemType.ItemIndex := Ord(AT.ItemType);

  if Assigned(AT.EquipmentType) then
    for i := 0 to FEquipTypeIds.Count - 1 do
      if FEquipTypeIds[i] = AT.EquipmentType.Id then
      begin
        cbEquipmentType.ItemIndex := i;
        Break;
      end;

  RefreshEquipmentCombo(AT);

  RefreshFileTypeChecks;
end;

procedure TedActionTypes.RefreshEquipmentCombo(AT: TActionType);
var
  Equips: TEquipments;
  Equip: TEquipment;
  i: Integer;
begin
  cbEquipment.Items.Clear;
  FEquipIds.Clear;
  cbEquipment.Enabled := False;

  if not Assigned(AT) or not Assigned(AT.EquipmentType) then
    Exit;

  Equips := Model.Equipments.GetEquipmentsByType(AT.EquipmentType.Id);
  try
    if Equips.Count = 0 then
      Exit;

    cbEquipment.Enabled := True;
    cbEquipment.Items.Add('(none)');
    FEquipIds.Add(0);

    for Equip in Equips do
    begin
      if Equip.Manufacturer <> '' then
        cbEquipment.Items.Add(Equip.Model + ' (' + Equip.Manufacturer + ')')
      else
        cbEquipment.Items.Add(Equip.Model);
      FEquipIds.Add(Equip.Id);
    end;

    cbEquipment.ItemIndex := 0;
    if Assigned(AT.Equipment) then
      for i := 0 to FEquipIds.Count - 1 do
        if FEquipIds[i] = AT.Equipment.Id then
        begin
          cbEquipment.ItemIndex := i;
          Break;
        end;
  finally
    Equips.Free;
  end;
end;

procedure TedActionTypes.cbEquipmentChange(Sender: TObject);
var
  AT: TActionType;
  EquipId: Integer;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active then Exit;
  if (cbEquipment.ItemIndex < 0) or (cbEquipment.ItemIndex >= FEquipIds.Count) then Exit;

  // Capture before Edit — Edit triggers SyncCombos which rebuilds the combo
  EquipId := FEquipIds[cbEquipment.ItemIndex];

  if not (DataSource.DataSet.State in [dsEdit, dsInsert]) then
    DataSource.DataSet.Edit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if Assigned(AT) then
  begin
    if EquipId = 0 then
      AT.Equipment := nil
    else
      AT.Equipment := Model.Equipments.GetEquipment(EquipId);

    // Association fields aren't tracked by TAureliusDataset — flush explicitly
    DataSource.DataSet.Post;
    TAureliusDataset(DataSource.DataSet).Manager.Flush;
  end;
end;

procedure TedActionTypes.ApplyFileTypeFilter(Sender: TObject);
var
  FilterText: string;
  I: Integer;
begin
  if Assigned(FFilterEdit) then
    FilterText := LowerCase(FFilterEdit.Text)
  else
    FilterText := '';

  clbFileTypes.Items.BeginUpdate;
  try
    clbFileTypes.Items.Clear;
    FFileTypeIds.Clear;

    for I := 0 to FAllFileTypeNames.Count - 1 do
    begin
      if (FilterText = '') or (Pos(FilterText, LowerCase(FAllFileTypeNames[I])) > 0) then
      begin
        clbFileTypes.Items.Add(FAllFileTypeNames[I]);
        FFileTypeIds.Add(FAllFileTypeIds[I]);
      end;
    end;
  finally
    clbFileTypes.Items.EndUpdate;
  end;

  RefreshFileTypeChecks;
end;

procedure TedActionTypes.RefreshFileTypeChecks;
var
  AT: TActionType;
  LinkedTypes: TFileTypes;
  FT: TFileType;
  i: Integer;
  LinkedIds: TList<Integer>;
begin
  for i := 0 to clbFileTypes.Count - 1 do
    clbFileTypes.Checked[i] := False;

  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active or
     (DataSource.DataSet.RecordCount = 0) then
    Exit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if not Assigned(AT) or (AT.Id = 0) then
    Exit;

  LinkedTypes := Model.ActionTypes.GetFileTypes(AT.Id);
  LinkedIds := TList<Integer>.Create;
  try
    for FT in LinkedTypes do
      LinkedIds.Add(FT.Id);

    for i := 0 to FFileTypeIds.Count - 1 do
      clbFileTypes.Checked[i] := LinkedIds.Contains(FFileTypeIds[i]);
  finally
    LinkedIds.Free;
  end;
end;

const
  ActionKindNames: array[0..5] of string =
    ('Synthesys', 'Testing', 'Measurement', 'Analysis', 'Simulation', 'Other');
  ItemTypeNames: array[0..8] of string =
    ('Synthesis', 'Treatment', 'Measurement', 'Testing', 'Characterization',
     'Computing', 'Specimen', 'Model', 'Other');

procedure TedActionTypes.KindGetText(Sender: TField; var Text: string; DisplayText: Boolean);
var
  V: Integer;
begin
  V := Sender.AsInteger;
  if (V >= Low(ActionKindNames)) and (V <= High(ActionKindNames)) then
    Text := ActionKindNames[V]
  else
    Text := IntToStr(V);
end;

procedure TedActionTypes.ItemTypeGetText(Sender: TField; var Text: string; DisplayText: Boolean);
var
  V: Integer;
begin
  V := Sender.AsInteger;
  if (V >= Low(ItemTypeNames)) and (V <= High(ItemTypeNames)) then
    Text := ItemTypeNames[V]
  else
    Text := IntToStr(V);
end;

procedure TedActionTypes.LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>);
var
  DS: TDataSet;
  AT: TActionType;
  i: Integer;
begin
  // Expected CSV columns: Kind, ItemType, Title, EquipmentType, Description
  if Length(Fields) < 3 then
    Exit;

  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  DS.Append;
  DS.FieldByName('CreatedDate').AsDateTime := UTCNow;
  DS.FieldByName('Kind').AsInteger := 0;      
  DS.FieldByName('ItemType').AsInteger := 0;  

  if (Length(Fields) > 0) and (Fields[0] <> '') then
    for i := Low(ActionKindNames) to High(ActionKindNames) do
      if SameText(ActionKindNames[i], Fields[0]) then
      begin
        DS.FieldByName('Kind').AsInteger := i;
        Break;
      end;

  if (Length(Fields) > 1) and (Fields[1] <> '') then
    for i := Low(ItemTypeNames) to High(ItemTypeNames) do
      if SameText(ItemTypeNames[i], Fields[1]) then
      begin
        DS.FieldByName('ItemType').AsInteger := i;
        Break;
      end;

  if Length(Fields) > 2 then
    DS.FieldByName('Title').AsString := Fields[2];

  AT := TAureliusDataset(DS).Current<TActionType>;

  if (Length(Fields) > 3) and (Fields[3] <> '') and Assigned(AT) then
    for i := 1 to cbEquipmentType.Items.Count - 1 do
      if SameText(cbEquipmentType.Items[i], Fields[3]) then
      begin
        AT.EquipmentType := Model.EquipmentTypes.GetType(FEquipTypeIds[i]);
        Break;
      end;

  if Length(Fields) > 4 then
    DS.FieldByName('Description').AsString := Fields[4];

  DS.Post;
end;

procedure TedActionTypes.cbKindChange(Sender: TObject);
var
  AT: TActionType;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active then Exit;
  if cbKind.ItemIndex < 0 then Exit;

  if not (DataSource.DataSet.State in [dsEdit, dsInsert]) then
    DataSource.DataSet.Edit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if Assigned(AT) then
  begin
    AT.Kind := TActionKind(cbKind.ItemIndex);
    DataSource.DataSet.FieldByName('Kind').AsInteger := cbKind.ItemIndex;
  end;
end;

procedure TedActionTypes.cbItemTypeChange(Sender: TObject);
var
  AT: TActionType;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active then Exit;
  if cbItemType.ItemIndex < 0 then Exit;

  if not (DataSource.DataSet.State in [dsEdit, dsInsert]) then
    DataSource.DataSet.Edit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if Assigned(AT) then
  begin
    AT.ItemType := TItemType(cbItemType.ItemIndex);
    DataSource.DataSet.FieldByName('ItemType').AsInteger := cbItemType.ItemIndex;
  end;
end;

procedure TedActionTypes.cbEquipmentTypeChange(Sender: TObject);
var
  AT: TActionType;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active then Exit;
  if cbEquipmentType.ItemIndex < 0 then Exit;

  if not (DataSource.DataSet.State in [dsEdit, dsInsert]) then
    DataSource.DataSet.Edit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if Assigned(AT) then
  begin
    if cbEquipmentType.ItemIndex = 0 then
    begin
      AT.EquipmentType := nil;
      AT.Equipment := nil;
    end
    else
      AT.EquipmentType := Model.EquipmentTypes.GetType(FEquipTypeIds[cbEquipmentType.ItemIndex]);

    RefreshEquipmentCombo(AT);
  end;
end;

procedure TedActionTypes.clbFileTypesClickCheck(Sender: TObject);
var
  AT: TActionType;
  Idx: Integer;
  FT: TFileType;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active or
     (DataSource.DataSet.RecordCount = 0) then
    Exit;

  AT := TAureliusDataset(DataSource.DataSet).Current<TActionType>;
  if not Assigned(AT) or (AT.Id = 0) then
    Exit;

  Idx := clbFileTypes.ItemIndex;
  if (Idx < 0) or (Idx >= FFileTypeIds.Count) then
    Exit;

  FT := Model.FileTypes.GetFileType(FFileTypeIds[Idx]);
  if not Assigned(FT) then
    Exit;

  if clbFileTypes.Checked[Idx] then
    Model.ActionTypes.AddFileTypeLink(AT, FT)
  else
    Model.ActionTypes.RemoveFileTypeLink(AT, FT);
end;

end.
