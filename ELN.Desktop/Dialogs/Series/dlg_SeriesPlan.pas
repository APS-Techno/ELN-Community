unit dlg_SeriesPlan;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  RzPanel, RzCommon,
  Aurelius.Engine.ObjectManager,
  unit_SeriesTable;

type
  TdlgSeriesPlan = class(TForm)
    pnlGeneral: TRzPanel;
    lblGeneral: TLabel;
    lblTitle: TLabel;
    edTitle: TEdit;
    lblPurpose: TLabel;
    memPurpose: TMemo;
    lblFolder: TLabel;
    cbFolder: TComboBox;
    pnlFactors: TRzPanel;
    lblFactors: TLabel;
    lblFactorNote: TLabel;
    pnlFactorButtons: TPanel;
    btnFactorAdd: TButton;
    btnFactorEdit: TButton;
    btnFactorRemove: TButton;
    lvFactors: TListView;
    pnlLevels: TRzPanel;
    lblLevelsHint: TLabel;
    lblLevelsA: TLabel;
    edLevelsA: TEdit;
    lblLevelsB: TLabel;
    edLevelsB: TEdit;
    pnlFixed: TRzPanel;
    lblFixed: TLabel;
    pnlFixedButtons: TPanel;
    btnFixedAdd: TButton;
    btnFixedEdit: TButton;
    btnFixedRemove: TButton;
    lvFixed: TListView;
    pnlResponses: TRzPanel;
    lblResponses: TLabel;
    pnlResponseButtons: TPanel;
    btnResponseAdd: TButton;
    btnResponseEdit: TButton;
    btnResponseRemove: TButton;
    lvResponses: TListView;
    pnlBottom: TRzPanel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure AddClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnOKClick(Sender: TObject);
  private
    FManager: TObjectManager;
    FProjectId: Integer;
    FHasPoints: Boolean;
    FPlan: TSeriesPlan;
    FFolderIds: TList<Integer>;
    function TypeText(AValueTypeId: Integer; const AEntryLabel: string): string;
    function FactorUnits: TArray<string>;
    function RangeText(const AFactor: TSeriesFactorSpec): string;
    function ListFor(AKind: Integer): TListView;
    function UsedTypeIds(AKind, AExceptIndex: Integer): TArray<Integer>;
    procedure LoadFolders(ASelected: Integer);
    procedure AddFolders(AParent, ADepth: Integer; AFolders: TList<TObject>);
    procedure FillLists;
    procedure UpdateButtons;
    procedure UpdateLevelsUi;
    function LevelsText: string;
    function CheckInput: Boolean;
  public
    destructor Destroy; override;
    class function Execute(AManager: TObjectManager; AProjectId: Integer;
      var ATitle, APurpose: string; var APlan: TSeriesPlan;
      var ALevelsText: string; AHasPoints: Boolean): Boolean; static;
  end;

implementation

{$R *.dfm}

uses
  System.Generics.Defaults,
  unit_Project,
  unit_ValueType,
  unit_SeriesPlanInput,
  dlg_SeriesPlanEntry;

const
  KIND_FACTOR = 0;
  KIND_FIXED = 1;
  KIND_RESPONSE = 2;
  MAX_FOLDER_DEPTH = 32;
  LEVELS_PANEL_BASE = 46;
  LEVELS_ROW_HEIGHT = 50;

destructor TdlgSeriesPlan.Destroy;
begin
  FFolderIds.Free;
  inherited;
end;

function TdlgSeriesPlan.TypeText(AValueTypeId: Integer;
  const AEntryLabel: string): string;
var
  T: TValueType;
begin
  T := FManager.Find<TValueType>(AValueTypeId);
  if T = nil then
    Exit(SeriesEntryCaption(Format('Value type %d', [AValueTypeId]), AEntryLabel));
  Result := SeriesEntryCaption(T.Title, AEntryLabel);
  if T.Units <> '' then
    Result := Result + ', ' + T.Units;
end;

function TdlgSeriesPlan.FactorUnits: TArray<string>;
var
  I: Integer;
  T: TValueType;
begin
  SetLength(Result, Length(FPlan.Factors));
  for I := 0 to High(Result) do
  begin
    T := FManager.Find<TValueType>(FPlan.Factors[I].ValueTypeId);
    if T <> nil then
      Result[I] := T.Units;
  end;
end;

function TdlgSeriesPlan.RangeText(const AFactor: TSeriesFactorSpec): string;
begin
  if AFactor.RangeMin.HasValue and AFactor.RangeMax.HasValue then
    Result := Format('%s to %s', [SeriesNumberText(AFactor.RangeMin.Value),
      SeriesNumberText(AFactor.RangeMax.Value)])
  else if AFactor.RangeMin.HasValue then
    Result := 'from ' + SeriesNumberText(AFactor.RangeMin.Value)
  else if AFactor.RangeMax.HasValue then
    Result := 'up to ' + SeriesNumberText(AFactor.RangeMax.Value)
  else
    Result := 'no limit';
end;

function TdlgSeriesPlan.ListFor(AKind: Integer): TListView;
begin
  case AKind of
    KIND_FACTOR: Result := lvFactors;
    KIND_FIXED: Result := lvFixed;
  else
    Result := lvResponses;
  end;
end;

function TdlgSeriesPlan.UsedTypeIds(AKind, AExceptIndex: Integer): TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  if AKind = KIND_RESPONSE then
  begin
    for I := 0 to High(FPlan.Responses) do
      if I <> AExceptIndex then
        Result := Result + [FPlan.Responses[I].ValueTypeId];
    Exit;
  end;
  for I := 0 to High(FPlan.Factors) do
    if (AKind <> KIND_FACTOR) or (I <> AExceptIndex) then
      Result := Result + [FPlan.Factors[I].ValueTypeId];
  for I := 0 to High(FPlan.Fixed) do
    if (AKind <> KIND_FIXED) or (I <> AExceptIndex) then
      Result := Result + [FPlan.Fixed[I].ValueTypeId];
end;

procedure TdlgSeriesPlan.AddFolders(AParent, ADepth: Integer;
  AFolders: TList<TObject>);
var
  F: TObject;
  Folder: TFolder;
begin
  if ADepth > MAX_FOLDER_DEPTH then
    Exit;
  for F in AFolders do
  begin
    Folder := TFolder(F);
    if Folder.ParentFolderID <> AParent then
      Continue;
    cbFolder.Items.Add(StringOfChar(' ', ADepth * 3) + Folder.Title);
    FFolderIds.Add(Folder.Id);
    AddFolders(Folder.Id, ADepth + 1, AFolders);
  end;
end;

procedure TdlgSeriesPlan.LoadFolders(ASelected: Integer);
var
  Project: TProject;
  Sorted: TList<TObject>;
  Folder: TFolder;
  I: Integer;
begin
  FFolderIds := TList<Integer>.Create;
  cbFolder.Items.Add('(project root)');
  FFolderIds.Add(0);
  Project := FManager.Find<TProject>(FProjectId);
  if Project <> nil then
  begin
    Sorted := TList<TObject>.Create;
    try
      for Folder in Project.Folders do
        Sorted.Add(Folder);
      Sorted.Sort(TComparer<TObject>.Construct(
        function(const A, B: TObject): Integer
        begin
          Result := TFolder(A).SortOrder - TFolder(B).SortOrder;
          if Result = 0 then
            Result := TFolder(A).Id - TFolder(B).Id;
        end));
      AddFolders(0, 0, Sorted);
    finally
      Sorted.Free;
    end;
  end;
  cbFolder.ItemIndex := 0;
  for I := 0 to FFolderIds.Count - 1 do
    if FFolderIds[I] = ASelected then
      cbFolder.ItemIndex := I;
end;

procedure TdlgSeriesPlan.FillLists;
var
  Item: TListItem;
  F: TSeriesFactorSpec;
  X: TSeriesFixedSpec;
  R: TSeriesResponseSpec;
begin
  lvFactors.Items.BeginUpdate;
  lvFixed.Items.BeginUpdate;
  lvResponses.Items.BeginUpdate;
  try
    lvFactors.Items.Clear;
    lvFixed.Items.Clear;
    lvResponses.Items.Clear;
    for F in FPlan.Factors do
    begin
      Item := lvFactors.Items.Add;
      Item.Caption := TypeText(F.ValueTypeId, '');
      Item.SubItems.Add(F.EntryLabel);
      Item.SubItems.Add(RangeText(F));
    end;
    for X in FPlan.Fixed do
    begin
      Item := lvFixed.Items.Add;
      Item.Caption := TypeText(X.ValueTypeId, '');
      Item.SubItems.Add(X.EntryLabel);
      Item.SubItems.Add(SeriesNumberText(X.Value));
      if X.Tol > 0 then
        Item.SubItems.Add(SeriesNumberText(X.Tol))
      else
        Item.SubItems.Add('');
    end;
    for R in FPlan.Responses do
    begin
      Item := lvResponses.Items.Add;
      Item.Caption := TypeText(R.ValueTypeId, '');
      Item.SubItems.Add(R.EntryLabel);
    end;
  finally
    lvResponses.Items.EndUpdate;
    lvFixed.Items.EndUpdate;
    lvFactors.Items.EndUpdate;
  end;
  UpdateButtons;
  UpdateLevelsUi;
end;

procedure TdlgSeriesPlan.UpdateButtons;
var
  FactorsEditable: Boolean;
begin
  FactorsEditable := not FHasPoints;
  btnFactorAdd.Enabled := FactorsEditable and (Length(FPlan.Factors) < 2);
  btnFactorEdit.Enabled := lvFactors.ItemIndex >= 0;
  btnFactorRemove.Enabled := FactorsEditable and (lvFactors.ItemIndex >= 0);
  lblFactorNote.Visible := FHasPoints;
  btnFixedEdit.Enabled := lvFixed.ItemIndex >= 0;
  btnFixedRemove.Enabled := lvFixed.ItemIndex >= 0;
  btnResponseEdit.Enabled := lvResponses.ItemIndex >= 0;
  btnResponseRemove.Enabled := lvResponses.ItemIndex >= 0;
end;

procedure TdlgSeriesPlan.UpdateLevelsUi;
var
  Count: Integer;
  Names: array[0..1] of string;
  I: Integer;
begin
  Count := 0;
  for I := 0 to High(FPlan.Factors) do
    if I <= 1 then
      Names[I] := TypeText(FPlan.Factors[I].ValueTypeId, FPlan.Factors[I].EntryLabel);
  case Length(FPlan.Factors) of
    0:
      lblLevelsHint.Caption := 'Add a factor to enter its levels.';
    1:
      if FHasPoints then
        lblLevelsHint.Caption := 'This series has points. Use Add point... in the ' +
          'series view to add more.'
      else
      begin
        Count := 1;
        lblLevelsHint.Caption := 'Levels make one point each. Separate them with ' +
          'semicolons, for example 100; 200; 300.';
      end;
    2:
      begin
        Count := 2;
        lblLevelsHint.Caption := 'Fill grid: enter the levels of each factor. ' +
          'Every combination becomes a point. Combinations that already exist are skipped.';
      end;
  else
    lblLevelsHint.Caption := 'Use Add point... in the series view to add points.';
  end;
  lblLevelsA.Caption := 'Levels of ' + Names[0];
  lblLevelsB.Caption := 'Levels of ' + Names[1];
  pnlLevels.DisableAlign;
  try
    pnlLevels.Height := LEVELS_PANEL_BASE + Count * LEVELS_ROW_HEIGHT;
    lblLevelsA.Visible := Count >= 1;
    edLevelsA.Visible := Count >= 1;
    lblLevelsB.Visible := Count >= 2;
    edLevelsB.Visible := Count >= 2;
    lblLevelsA.Top := lblLevelsHint.BoundsRect.Bottom + 1;
    edLevelsA.Top := lblLevelsA.BoundsRect.Bottom + 1;
    lblLevelsB.Top := edLevelsA.BoundsRect.Bottom + 1;
    edLevelsB.Top := lblLevelsB.BoundsRect.Bottom + 1;
  finally
    pnlLevels.EnableAlign;
  end;
end;

function TdlgSeriesPlan.LevelsText: string;
begin
  case Length(FPlan.Factors) of
    1:
      if FHasPoints then
        Result := ''
      else
        Result := edLevelsA.Text;
    2: Result := JoinLevelLists([edLevelsA.Text, edLevelsB.Text]);
  else
    Result := '';
  end;
end;

procedure TdlgSeriesPlan.ListSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TdlgSeriesPlan.ListDblClick(Sender: TObject);
begin
  EditClick(Sender);
end;

procedure TdlgSeriesPlan.AddClick(Sender: TObject);
var
  Kind: Integer;
  Factor: TSeriesFactorSpec;
  Fixed: TSeriesFixedSpec;
  Response: TSeriesResponseSpec;
begin
  Kind := (Sender as TComponent).Tag;
  case Kind of
    KIND_FACTOR:
      begin
        if FHasPoints or (Length(FPlan.Factors) >= 2) then
          Exit;
        Factor := Default(TSeriesFactorSpec);
        if TdlgSeriesPlanEntry.ExecuteFactor(FManager, UsedTypeIds(Kind, -1), False,
          Factor) then
          FPlan.Factors := FPlan.Factors + [Factor];
      end;
    KIND_FIXED:
      begin
        Fixed := Default(TSeriesFixedSpec);
        if TdlgSeriesPlanEntry.ExecuteFixed(FManager, UsedTypeIds(Kind, -1), Fixed) then
          FPlan.Fixed := FPlan.Fixed + [Fixed];
      end;
  else
    Response := Default(TSeriesResponseSpec);
    if TdlgSeriesPlanEntry.ExecuteResponse(FManager, UsedTypeIds(Kind, -1), Response) then
      FPlan.Responses := FPlan.Responses + [Response];
  end;
  FillLists;
end;

procedure TdlgSeriesPlan.EditClick(Sender: TObject);
var
  Kind, Index: Integer;
  List: TListView;
begin
  Kind := (Sender as TComponent).Tag;
  List := ListFor(Kind);
  Index := List.ItemIndex;
  if Index < 0 then
    Exit;
  case Kind of
    KIND_FACTOR:
      TdlgSeriesPlanEntry.ExecuteFactor(FManager, UsedTypeIds(Kind, Index),
        FHasPoints, FPlan.Factors[Index]);
    KIND_FIXED:
      TdlgSeriesPlanEntry.ExecuteFixed(FManager, UsedTypeIds(Kind, Index),
        FPlan.Fixed[Index]);
  else
    TdlgSeriesPlanEntry.ExecuteResponse(FManager, UsedTypeIds(Kind, Index),
      FPlan.Responses[Index]);
  end;
  FillLists;
  if Index < List.Items.Count then
    List.ItemIndex := Index;
end;

procedure TdlgSeriesPlan.RemoveClick(Sender: TObject);
var
  Kind, Index: Integer;
begin
  Kind := (Sender as TComponent).Tag;
  Index := ListFor(Kind).ItemIndex;
  if Index < 0 then
    Exit;
  case Kind of
    KIND_FACTOR:
      begin
        if FHasPoints then
          Exit;
        Delete(FPlan.Factors, Index, 1);
      end;
    KIND_FIXED: Delete(FPlan.Fixed, Index, 1);
  else
    Delete(FPlan.Responses, Index, 1);
  end;
  FillLists;
end;

function TdlgSeriesPlan.CheckInput: Boolean;
var
  Points: TArray<TSeriesPoint>;
  Error: string;
  Title: string;
begin
  Result := False;
  Title := Trim(edTitle.Text);
  if Title = '' then
  begin
    MessageDlg('A title is required.', mtWarning, [mbOK], 0);
    edTitle.SetFocus;
    Exit;
  end;
  if not BuildPlanPoints(LevelsText, FactorUnits, nil, FormatSettings,
    Points, Error) then
  begin
    MessageDlg(Error, mtWarning, [mbOK], 0);
    if edLevelsA.Visible then
      edLevelsA.SetFocus;
    Exit;
  end;
  Result := True;
end;

procedure TdlgSeriesPlan.btnOKClick(Sender: TObject);
begin
  if CheckInput then
    ModalResult := mrOk;
end;

class function TdlgSeriesPlan.Execute(AManager: TObjectManager;
  AProjectId: Integer; var ATitle, APurpose: string; var APlan: TSeriesPlan;
  var ALevelsText: string; AHasPoints: Boolean): Boolean;
var
  Dlg: TdlgSeriesPlan;
  Segments: TArray<string>;
begin
  Dlg := TdlgSeriesPlan.Create(Application);
  try
    Dlg.FManager := AManager;
    Dlg.FProjectId := AProjectId;
    Dlg.FHasPoints := AHasPoints;
    Dlg.FPlan := APlan;
    Dlg.edTitle.Text := ATitle;
    Dlg.memPurpose.Text := APurpose;
    Dlg.LoadFolders(APlan.TargetFolderId);
    Segments := ALevelsText.Split([LEVEL_LIST_SEPARATOR]);
    if Length(Segments) > 0 then
      Dlg.edLevelsA.Text := Segments[0];
    if Length(Segments) > 1 then
      Dlg.edLevelsB.Text := Segments[1];
    Dlg.FillLists;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      ATitle := Trim(Dlg.edTitle.Text);
      APurpose := Dlg.memPurpose.Text;
      APlan := Dlg.FPlan;
      APlan.TargetFolderId := Dlg.FFolderIds[Dlg.cbFolder.ItemIndex];
      ALevelsText := Dlg.LevelsText;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
