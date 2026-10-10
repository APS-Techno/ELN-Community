unit EditorBase;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Data.DB, Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset, Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, RzPanel,
  Vcl.Grids, Vcl.DBGrids, RzDBNav;

type
  TfrmEditorBase = class(TForm)
    RzPanel1: TRzPanel;
    RzPanel2: TRzPanel;
    btnSave: TBitBtn;
    DataSource: TDataSource;
    DBGrid1: TDBGrid;
    RzDBNavigator1: TRzDBNavigator;
    btnLoadCSV: TBitBtn;
    dlgOpenCSV: TOpenDialog;
    procedure btnLoadCSVClick(Sender: TObject);
  private
    function DetectDelimiter(const Line: string): Char;
    function SplitCSVLine(const Line: string; Delimiter: Char): TArray<string>;
    function GetEditableFieldNames: TArray<string>;
  protected
    procedure LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>); virtual;
  public
    procedure Show(DataSet: TDataSet);
  end;

var
  frmEditorBase: TfrmEditorBase;

implementation

uses
  Aurelius.Engine.ObjectManager,
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}


procedure TfrmEditorBase.Show(DataSet: TDataSet);
begin
  DataSource.DataSet := DataSet;
  ShowModal;
end;

function TfrmEditorBase.DetectDelimiter(const Line: string): Char;
begin
  if Pos(';', Line) > 0 then
    Result := ';'
  else
    Result := ',';
end;

function TfrmEditorBase.SplitCSVLine(const Line: string; Delimiter: Char): TArray<string>;
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := Delimiter;
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Line;
    SetLength(Result, Parts.Count);
    for I := 0 to Parts.Count - 1 do
      Result[I] := Trim(Parts[I]);
  finally
    Parts.Free;
  end;
end;

function TfrmEditorBase.GetEditableFieldNames: TArray<string>;
var
  List: TStringList;
  I: Integer;
  Col: TColumn;
  FieldName: string;
begin
  List := TStringList.Create;
  try
    if DBGrid1.Columns.Count > 0 then
    begin
      for I := 0 to DBGrid1.Columns.Count - 1 do
      begin
        Col := DBGrid1.Columns[I];
        FieldName := Col.FieldName;
        if SameText(FieldName, 'Id') or
           SameText(FieldName, 'CreatedDate') or
           SameText(FieldName, 'ModifiedDate') or
           SameText(FieldName, 'CreatedBy') or
           SameText(FieldName, 'ModifiedBy') then
          Continue;
        List.Add(FieldName);
      end;
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

procedure TfrmEditorBase.LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>);
var
  DS: TDataSet;
  I, MaxIdx: Integer;
begin
  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  DS.Append;
  if DS.FindField('CreatedDate') <> nil then
    DS.FieldByName('CreatedDate').AsDateTime := UTCNow;
  MaxIdx := Length(FieldNames) - 1;
  if Length(Fields) - 1 < MaxIdx then
    MaxIdx := Length(Fields) - 1;

  for I := 0 to MaxIdx do
  begin
    if (FieldNames[I] <> '') and (Fields[I] <> '') then
      DS.FieldByName(FieldNames[I]).AsString := Fields[I];
  end;
  DS.Post;
end;

procedure TfrmEditorBase.btnLoadCSVClick(Sender: TObject);
var
  Lines: TStringList;
  Delimiter: Char;
  I, Imported, StartLine: Integer;
  FieldNames: TArray<string>;
  Fields: TArray<string>;
  FirstField: string;
begin
  if not dlgOpenCSV.Execute then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(dlgOpenCSV.FileName);
    if Lines.Count = 0 then
    begin
      MessageDlg('CSV file is empty.', mtWarning, [mbOK], 0);
      Exit;
    end;

    Delimiter := DetectDelimiter(Lines[0]);
    FieldNames := GetEditableFieldNames;

    StartLine := 0;
    if Lines.Count > 1 then
    begin
      Fields := SplitCSVLine(Lines[0], Delimiter);
      if Length(Fields) > 0 then
      begin
        FirstField := Fields[0];
        if (FirstField <> '') and not CharInSet(FirstField[1], ['0'..'9']) then
        begin
          StartLine := 1;
        end;
      end;
    end;

    Imported := 0;
    for I := StartLine to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      Fields := SplitCSVLine(Lines[I], Delimiter);
      LoadCSVRow(Fields, FieldNames);
      Inc(Imported);
    end;

    if (Imported > 0) and (DataSource.DataSet is TAureliusDataset) then
      TAureliusDataset(DataSource.DataSet).Manager.Flush;

    MessageDlg(Format('Imported %d rows.', [Imported]), mtInformation, [mbOK], 0);
  finally
    Lines.Free;
  end;
end;

end.
