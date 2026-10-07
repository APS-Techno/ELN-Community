unit editor_ValueTypes;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, EditorBase, Data.DB, Vcl.StdCtrls,
  Vcl.Buttons, RzDBNav, Vcl.Grids, Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask,
  Vcl.DBCtrls, System.Generics.Collections,
  unit_ValueTypeCategories;

type
  TedValueTypes = class(TfrmEditorBase)
    edSymbol: TDBEdit;
    edTitle: TDBEdit;
    edUnits: TDBEdit;
    cbCategory: TComboBox;
    edDescription: TDBEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    pnlCategories: TPanel;
    lblCategoryHdr: TLabel;
    lbCategories: TListBox;
    pnlCatButtons: TPanel;
    btnCatAdd: TButton;
    btnCatRename: TButton;
    btnCatMove: TButton;
    pnlDetail: TPanel;
    procedure cbCategoryChange(Sender: TObject);
    procedure lbCategoriesClick(Sender: TObject);
    procedure btnCatAddClick(Sender: TObject);
    procedure btnCatRenameClick(Sender: TObject);
    procedure btnCatMoveClick(Sender: TObject);
  private
    FCategoryMap: TDictionary<string, Integer>;
    FNextCatID: Integer;
    FLayoutDone: Boolean;
    procedure SetupLayout;
    procedure GreekPickerClick(Sender: TObject);
    procedure CreateGreekButton(AParent: TWinControl; AEdit: TDBEdit; ALeft, ATag: Integer);
    procedure DataSetFilterRecord(DataSet: TDataSet; var Accept: Boolean);
    procedure DataSetBeforeDelete(ADataSet: TDataSet);
    procedure DataSetAfterInsert(ADataSet: TDataSet);
    procedure BuildCategoryMap;
    procedure CatIDGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  protected
    procedure LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>); override;
  public
    destructor Destroy; override;
    procedure Show(DataSet: TDataSet); reintroduce;
  end;

var
  edValueTypes: TedValueTypes;

implementation

uses
  Aurelius.Bind.Dataset,
  unit_DataModel,
  dlg_GreekPicker,
  unit_TimeHelper;

{$R *.dfm}

{ TedValueTypes }

destructor TedValueTypes.Destroy;
begin
  FCategoryMap.Free;
  inherited;
end;

procedure TedValueTypes.SetupLayout;
var
  I: Integer;
begin
  if FLayoutDone then
    Exit;
  FLayoutDone := True;

  // Widen dialog to fit left panel
  Width := Width + pnlCategories.Width + MulDiv(8, CurrentPPI, 96);

  // Hide old category combo and its label
  cbCategory.Visible := False;
  Label4.Visible := False;

  // Populate category listbox
  lbCategories.Items.Add('All');
  for I := 0 to ValueTypeCategories.Count - 1 do
    lbCategories.Items.Add(ValueTypeCategories[I]);
  lbCategories.ItemIndex := 0;

  // Reparent existing controls into detail panel
  Label1.Parent := pnlDetail;
  Label2.Parent := pnlDetail;
  Label3.Parent := pnlDetail;
  Label5.Parent := pnlDetail;
  edSymbol.Parent := pnlDetail;
  edTitle.Parent := pnlDetail;
  edUnits.Parent := pnlDetail;
  edDescription.Parent := pnlDetail;
  RzDBNavigator1.Parent := pnlDetail;
  DBGrid1.Parent := pnlDetail;

  // Shift Title label and edit right, narrow the edit to make room for α button
  I := MulDiv(30, CurrentPPI, 96);
  Label2.Left := Label2.Left + I;
  edTitle.Left := edTitle.Left + I;
  edTitle.Width := edTitle.Width - I;

  // Greek picker buttons next to Symbol and Units
  CreateGreekButton(pnlDetail, edSymbol,
    edSymbol.BoundsRect.Right + MulDiv(2, CurrentPPI, 96), 0);
  CreateGreekButton(pnlDetail, edUnits,
    edUnits.BoundsRect.Right + MulDiv(2, CurrentPPI, 96), 1);
end;

procedure TedValueTypes.CreateGreekButton(AParent: TWinControl;
  AEdit: TDBEdit; ALeft, ATag: Integer);
var
  Btn: TSpeedButton;
begin
  Btn := TSpeedButton.Create(Self);
  Btn.Parent := AParent;
  Btn.SetBounds(
    ALeft,
    AEdit.Top,
    MulDiv(22, CurrentPPI, 96),
    AEdit.Height);
  Btn.Caption := #$03B1;
  Btn.Flat := True;
  Btn.Font.Name := 'Segoe UI';
  Btn.Tag := ATag;
  Btn.OnClick := GreekPickerClick;
end;

procedure TedValueTypes.Show(DataSet: TDataSet);
begin
  SetupLayout;

  DataSource.DataSet := DataSet;
  DataSet.BeforeDelete := DataSetBeforeDelete;
  DataSet.AfterInsert := DataSetAfterInsert;
  DataSet.OnFilterRecord := DataSetFilterRecord;

  if DataSet.FindField('CatID') <> nil then
    DataSet.FieldByName('CatID').OnGetText := CatIDGetText;

  ShowModal;

  DataSet.Filtered := False;
  DataSet.OnFilterRecord := nil;
  DataSet.BeforeDelete := nil;
  DataSet.AfterInsert := nil;
  DataSource.DataSet := nil;
end;

procedure TedValueTypes.lbCategoriesClick(Sender: TObject);
var
  DS: TDataSet;
begin
  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  if lbCategories.ItemIndex <= 0 then
    DS.Filtered := False
  else
  begin
    DS.Filtered := False;
    DS.Filtered := True;
  end;
end;

procedure TedValueTypes.DataSetFilterRecord(DataSet: TDataSet; var Accept: Boolean);
begin
  if not Assigned(lbCategories) or (lbCategories.ItemIndex <= 0) then
    Accept := True
  else
    Accept := DataSet.FieldByName('CatID').AsInteger = (lbCategories.ItemIndex - 1);
end;

procedure TedValueTypes.GreekPickerClick(Sender: TObject);
var
  Ch: string;
  Ed: TDBEdit;
  DS: TDataSet;
  SaveSel: Integer;
begin
  if TSpeedButton(Sender).Tag = 0 then
    Ed := edSymbol
  else
    Ed := edUnits;

  SaveSel := Ed.SelStart + Ed.SelLength;

  Ch := TdlgGreekPicker.Pick(TControl(Sender));
  if Ch = '' then
    Exit;

  DS := Ed.DataSource.DataSet;
  if Assigned(DS) and DS.Active and not (DS.State in [dsEdit, dsInsert]) then
    DS.Edit;

  Ed.SetFocus;
  Ed.SelStart := SaveSel;
  Ed.SelLength := 0;
  Ed.SelText := Ch;
end;

procedure TedValueTypes.DataSetAfterInsert(ADataSet: TDataSet);
var
  CatIdx: Integer;
begin
  ADataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
  if Assigned(lbCategories) then
  begin
    CatIdx := lbCategories.ItemIndex;
    if CatIdx > 0 then
      ADataSet.FieldByName('CatID').AsInteger := CatIdx - 1
    else
      ADataSet.FieldByName('CatID').AsInteger := 5; // "Other"
  end;
end;

procedure TedValueTypes.DataSetBeforeDelete(ADataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.ValueTypes.CanDelete(ADataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

procedure TedValueTypes.cbCategoryChange(Sender: TObject);
begin
  // Kept for DFM compatibility — category is now set via the left listbox
end;

procedure TedValueTypes.CatIDGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  if Sender.IsNull then
    Text := ''
  else
    Text := CategoryNameByID(Sender.AsInteger);
end;

procedure TedValueTypes.BuildCategoryMap;
var
  DS: TDataSet;
  CatID: Integer;
  Bm: TBookmark;
begin
  FCategoryMap := TDictionary<string, Integer>.Create;
  FNextCatID := ValueTypeCategories.Count;

  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  Bm := DS.Bookmark;
  DS.DisableControls;
  try
    DS.First;
    while not DS.Eof do
    begin
      CatID := DS.FieldByName('CatID').AsInteger;
      if CatID >= FNextCatID then
        FNextCatID := CatID + 1;
      DS.Next;
    end;
    DS.Bookmark := Bm;
  finally
    DS.EnableControls;
  end;
end;

procedure TedValueTypes.btnCatAddClick(Sender: TObject);
var
  Name: string;
begin
  Name := '';
  if not InputQuery('New Category', 'Category name:', Name) then
    Exit;
  Name := Trim(Name);
  if Name = '' then
    Exit;
  if CategoryIDByName(Name) >= 0 then
  begin
    ShowMessage('Category already exists.');
    Exit;
  end;

  AddCategory(Name);
  Model.ValueTypes.SaveCategories;

  lbCategories.Items.Add(Name);
end;

procedure TedValueTypes.btnCatRenameClick(Sender: TObject);
var
  CatIdx: Integer;
  Name: string;
begin
  CatIdx := lbCategories.ItemIndex;
  if CatIdx <= 0 then  // 0 = "All"
    Exit;

  Name := lbCategories.Items[CatIdx];
  if not InputQuery('Rename Category', 'Category name:', Name) then
    Exit;
  Name := Trim(Name);
  if Name = '' then
    Exit;

  RenameCategory(CatIdx - 1, Name);
  Model.ValueTypes.SaveCategories;
  lbCategories.Items[CatIdx] := Name;
end;

procedure TedValueTypes.btnCatMoveClick(Sender: TObject);
var
  DS: TDataSet;
  Dlg: TForm;
  LB: TListBox;
  I, VTID, CurCatID, NewCatID: Integer;
begin
  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active or DS.IsEmpty then
    Exit;

  VTID := DS.FieldByName('Id').AsInteger;
  CurCatID := DS.FieldByName('CatID').AsInteger;

  Dlg := TForm.Create(Self);
  try
    Dlg.Caption := 'Move to Category';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.Width := 220;
    Dlg.Height := 300;

    LB := TListBox.Create(Dlg);
    LB.Parent := Dlg;
    LB.Align := alClient;
    LB.AlignWithMargins := True;
    for I := 0 to ValueTypeCategories.Count - 1 do
      LB.Items.Add(ValueTypeCategories[I]);
    if (CurCatID >= 0) and (CurCatID < LB.Items.Count) then
      LB.ItemIndex := CurCatID;

    with TButton.Create(Dlg) do
    begin
      Parent := Dlg;
      Align := alBottom;
      Caption := 'OK';
      ModalResult := mrOK;
    end;

    if Dlg.ShowModal <> mrOK then
      Exit;

    NewCatID := LB.ItemIndex;
    if (NewCatID < 0) or (NewCatID = CurCatID) then
      Exit;
  finally
    Dlg.Free;
  end;

  Model.ValueTypes.MoveToCategory(VTID, NewCatID);

  // Refresh grid
  DS.Filtered := False;
  if lbCategories.ItemIndex > 0 then
    DS.Filtered := True;
end;

procedure TedValueTypes.LoadCSVRow(const Fields: TArray<string>; const FieldNames: TArray<string>);
var
  DS: TDataSet;
  CatName: string;
  CatID: Integer;
begin
  if Length(Fields) < 3 then
    Exit;

  if not Assigned(FCategoryMap) then
    BuildCategoryMap;

  DS := DataSource.DataSet;
  if not Assigned(DS) or not DS.Active then
    Exit;

  DS.Append;
  DS.FieldByName('CreatedDate').AsDateTime := UTCNow;
  DS.FieldByName('Symbol').AsString := Fields[0];
  DS.FieldByName('Title').AsString := Fields[1];
  if Length(Fields) > 2 then
    DS.FieldByName('Units').AsString := Fields[2];

  if (Length(Fields) > 3) and (Fields[3] <> '') then
  begin
    CatName := Fields[3];
    CatID := CategoryIDByName(CatName);

    if CatID < 0 then
    begin
      if not FCategoryMap.TryGetValue(CatName, CatID) then
      begin
        CatID := FNextCatID;
        FCategoryMap.Add(CatName, CatID);
        Inc(FNextCatID);
      end;
    end;

    DS.FieldByName('CatID').AsInteger := CatID;
  end;

  if Length(Fields) > 4 then
    DS.FieldByName('Description').AsString := Fields[4];

  DS.Post;
end;

end.
