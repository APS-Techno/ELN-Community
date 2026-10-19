unit editor_ReaderValueMappings;

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls,
  unit_ReaderValueMapping, unit_ValueType;

type
  TReaderValueMappingsEditor = class(TForm)
    lbMappings: TListBox;
    lblReader: TLabel;
    lblKey: TLabel;
    lblUnits: TLabel;
    lblType: TLabel;
    lblFactor: TLabel;
    lblLabel: TLabel;
    lblPattern: TLabel;
    edReader: TEdit;
    edKey: TEdit;
    edUnits: TEdit;
    cbType: TComboBox;
    edFactor: TEdit;
    edLabel: TEdit;
    btnNew: TButton;
    btnSave: TButton;
    btnDelete: TButton;
    btnClose: TButton;
    procedure MappingClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  private
    FRows: TList<TReaderValueMapping>;
    FTypes: TList<TValueType>;
    FCurrentId: Integer;
    procedure Reload;
    procedure CheckPermission;
  public
    destructor Destroy; override;
    class procedure Execute;
  end;

implementation

uses
  System.SysUtils, Vcl.Dialogs, unit_DataModel, unit_ReaderValueMappingModel;

{$R *.dfm}

procedure TReaderValueMappingsEditor.CheckPermission;
begin
  if not Model.Access.CanEditReferenceData(Model.Manager, Model.User) then
    raise EInvalidOperation.Create('Reference data editing is not permitted');
end;

class procedure TReaderValueMappingsEditor.Execute;
var
  Editor: TReaderValueMappingsEditor;
  VT: TValueType;
begin
  Editor := TReaderValueMappingsEditor.Create(Application);
  try
    Editor.CheckPermission;
    Editor.FTypes := Model.ValueTypes.GetTypes;
    for VT in Editor.FTypes do
      Editor.cbType.Items.Add(VT.Title + ' (' + VT.Units + ')');
    Editor.Reload;
    Editor.NewClick(nil);
    Editor.ShowModal;
  finally
    Editor.Free;
  end;
end;

destructor TReaderValueMappingsEditor.Destroy;
begin
  FRows.Free;
  FTypes.Free;
  inherited;
end;

procedure TReaderValueMappingsEditor.Reload;
var
  Row: TReaderValueMapping;
begin
  FreeAndNil(FRows);
  FRows := Model.Manager.Find<TReaderValueMapping>.List;
  lbMappings.Items.Clear;
  for Row in FRows do
    lbMappings.Items.Add(Row.ReaderId + ' | ' + Row.KeyPattern + ' [' +
      Row.ReaderUnits + '] -> ' + Row.ValueType.Title + ' (' +
      Row.ValueType.Units + ') x ' + FloatToStr(Row.Factor));
end;

procedure TReaderValueMappingsEditor.MappingClick(Sender: TObject);
var
  Row: TReaderValueMapping;
  I: Integer;
begin
  if lbMappings.ItemIndex < 0 then Exit;
  Row := FRows[lbMappings.ItemIndex];
  FCurrentId := Row.Id;
  edReader.Text := Row.ReaderId;
  edKey.Text := Row.KeyPattern;
  edUnits.Text := Row.ReaderUnits;
  edFactor.Text := FloatToStr(Row.Factor);
  edLabel.Text := Row.LabelText;
  cbType.ItemIndex := -1;
  for I := 0 to FTypes.Count - 1 do
    if FTypes[I].Id = Row.ValueType.Id then
      cbType.ItemIndex := I;
  btnDelete.Enabled := True;
end;

procedure TReaderValueMappingsEditor.NewClick(Sender: TObject);
begin
  FCurrentId := 0;
  lbMappings.ItemIndex := -1;
  edReader.Clear;
  edKey.Clear;
  edUnits.Clear;
  edFactor.Text := '1';
  edLabel.Clear;
  cbType.ItemIndex := -1;
  btnDelete.Enabled := False;
end;

procedure TReaderValueMappingsEditor.SaveClick(Sender: TObject);
var
  Candidate, Row: TReaderValueMapping;
  Resolver: TReaderValueMappingModel;
begin
  CheckPermission;
  Candidate := TReaderValueMapping.Create;
  try
    Candidate.Id := FCurrentId;
    Candidate.ReaderId := Trim(edReader.Text);
    Candidate.KeyPattern := Trim(edKey.Text);
    Candidate.ReaderUnits := edUnits.Text;
    Candidate.Factor := StrToFloat(edFactor.Text);
    Candidate.LabelText := edLabel.Text;
    if cbType.ItemIndex >= 0 then
      Candidate.ValueType := FTypes[cbType.ItemIndex];
    Resolver := TReaderValueMappingModel.Create(Model.Manager);
    try
      Resolver.Validate(Candidate);
    finally
      Resolver.Free;
    end;
    if FCurrentId = 0 then
      Row := TReaderValueMapping.Create
    else
      Row := Model.Manager.Find<TReaderValueMapping>(FCurrentId);
    Row.ReaderId := Candidate.ReaderId;
    Row.KeyPattern := Candidate.KeyPattern;
    Row.ReaderUnits := Candidate.ReaderUnits;
    Row.Factor := Candidate.Factor;
    Row.LabelText := Candidate.LabelText;
    Row.ValueType := Candidate.ValueType;
    if FCurrentId = 0 then
      Model.Manager.Save(Row);
    Model.Manager.Flush;
    Reload;
    NewClick(nil);
  finally
    Candidate.Free;
  end;
end;

procedure TReaderValueMappingsEditor.DeleteClick(Sender: TObject);
var
  Row: TReaderValueMapping;
begin
  CheckPermission;
  if FCurrentId = 0 then Exit;
  if MessageDlg('Delete this mapping? Stored values keep their original conversion.',
    mtConfirmation, [mbYes, mbNo], 0, mbNo) <> mrYes then Exit;
  Row := Model.Manager.Find<TReaderValueMapping>(FCurrentId);
  Model.Manager.Remove(Row);
  Model.Manager.Flush;
  Reload;
  NewClick(nil);
end;

end.
