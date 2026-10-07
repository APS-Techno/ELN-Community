unit editor_Equipment;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, EditorBase, Data.DB, Vcl.StdCtrls,
  Vcl.Buttons, RzDBNav, Vcl.Grids, Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask,
  Vcl.DBCtrls, System.Generics.Collections;

type
  TedEquipment = class(TfrmEditorBase)
    lblModel: TLabel;
    lblManufacturer: TLabel;
    lblLocation: TLabel;
    lblType: TLabel;
    lblBookingUrl: TLabel;
    lblInfoUrl: TLabel;
    lblDescription: TLabel;
    edModel: TDBEdit;
    edManufacturer: TDBEdit;
    edLocation: TDBEdit;
    edBookingUrl: TDBEdit;
    edInfoUrl: TDBEdit;
    edDescription: TDBEdit;
    cbEquipmentType: TComboBox;
    procedure cbEquipmentTypeChange(Sender: TObject);
  private
    FTypeIds: TList<Integer>;
    procedure DataSetAfterInsert(DataSet: TDataSet);
    procedure DataSetBeforeDelete(DataSet: TDataSet);
    procedure SyncComboBox(Sender: TObject; Field: TField);
  protected
    procedure LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>); override;
  public
    destructor Destroy; override;
    procedure ShowEditor(ADataSet, ALookupDataSet: TDataSet);
  end;

var
  edEquipment: TedEquipment;

implementation

uses
  Aurelius.Bind.Dataset,
  unit_Equipment,
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

destructor TedEquipment.Destroy;
begin
  FTypeIds.Free;
  inherited;
end;

procedure TedEquipment.ShowEditor(ADataSet, ALookupDataSet: TDataSet);
begin
  // Populate type combobox from lookup dataset
  if FTypeIds = nil then
    FTypeIds := TList<Integer>.Create
  else
    FTypeIds.Clear;
  cbEquipmentType.Items.Clear;

  ALookupDataSet.DisableControls;
  try
    ALookupDataSet.First;
    while not ALookupDataSet.Eof do
    begin
      cbEquipmentType.Items.Add(ALookupDataSet.FieldByName('Type_').AsString);
      FTypeIds.Add(ALookupDataSet.FieldByName('Id').AsInteger);
      ALookupDataSet.Next;
    end;
    ALookupDataSet.First;
  finally
    ALookupDataSet.EnableControls;
  end;

  DataSource.OnDataChange := SyncComboBox;
  DataSource.DataSet := ADataSet;
  ADataSet.AfterInsert := DataSetAfterInsert;
  ADataSet.BeforeDelete := DataSetBeforeDelete;
  ShowModal;
  ADataSet.AfterInsert := nil;
  ADataSet.BeforeDelete := nil;
  DataSource.DataSet := nil;
end;

procedure TedEquipment.DataSetAfterInsert(DataSet: TDataSet);
begin
  DataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
end;

procedure TedEquipment.DataSetBeforeDelete(DataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.Equipments.CanDelete(DataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

procedure TedEquipment.SyncComboBox(Sender: TObject; Field: TField);
var
  Equip: TEquipment;
  i: Integer;
begin
  cbEquipmentType.ItemIndex := -1;
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active or
     (DataSource.DataSet.RecordCount = 0) then
    Exit;

  Equip := TAureliusDataset(DataSource.DataSet).Current<TEquipment>;
  if Assigned(Equip) and Assigned(Equip.EquipmentType) then
    for i := 0 to FTypeIds.Count - 1 do
      if FTypeIds[i] = Equip.EquipmentType.Id then
      begin
        cbEquipmentType.ItemIndex := i;
        Break;
      end;
end;

procedure TedEquipment.LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>);
var
  DS: TDataSet;
  Equip: TEquipment;
  TypeName: string;
  i: Integer;
begin
  // Expected CSV columns: EquipmentType, Model, Manufacturer, Location, BookingUrl, InfoUrl, Description
  if Length(Fields) < 3 then
    Exit;

  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  DS.Append;
  DS.FieldByName('CreatedDate').AsDateTime := UTCNow;
  Equip := TAureliusDataset(DS).Current<TEquipment>;

  // Map EquipmentType text to entity
  if (Length(Fields) > 0) and (Fields[0] <> '') then
  begin
    TypeName := Fields[0];
    for i := 0 to cbEquipmentType.Items.Count - 1 do
      if SameText(cbEquipmentType.Items[i], TypeName) then
      begin
        if Assigned(Equip) then
          Equip.EquipmentType := Model.EquipmentTypes.GetType(FTypeIds[i]);
        Break;
      end;
  end;

  // String fields by index
  if Length(Fields) > 1 then
    DS.FieldByName('Model').AsString := Fields[1];
  if Length(Fields) > 2 then
    DS.FieldByName('Manufacturer').AsString := Fields[2];
  if Length(Fields) > 3 then
    DS.FieldByName('Location').AsString := Fields[3];
  if Length(Fields) > 4 then
    DS.FieldByName('BookingURL').AsString := Fields[4];
  if Length(Fields) > 5 then
    DS.FieldByName('InfoURL').AsString := Fields[5];
  if Length(Fields) > 6 then
    DS.FieldByName('Description').AsString := Fields[6];

  DS.Post;
end;

procedure TedEquipment.cbEquipmentTypeChange(Sender: TObject);
var
  Equip: TEquipment;
begin
  if (DataSource.DataSet = nil) or not DataSource.DataSet.Active then Exit;
  if cbEquipmentType.ItemIndex < 0 then Exit;

  if not (DataSource.DataSet.State in [dsEdit, dsInsert]) then
    DataSource.DataSet.Edit;

  Equip := TAureliusDataset(DataSource.DataSet).Current<TEquipment>;
  if Assigned(Equip) then
    Equip.EquipmentType := Model.EquipmentTypes.GetType(FTypeIds[cbEquipmentType.ItemIndex]);
end;

end.
