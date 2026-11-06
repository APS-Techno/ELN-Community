unit frame_Series;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.CheckLst, Vcl.Menus,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.BaseTree, VirtualTrees.AncestorVCL,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.Header,
  VCLTee.TeEngine, VCLTee.TeeProcs, VCLTee.Chart, VCLTee.Series,
  RzPanel,
  unit_TreeLook,
  unit_SeriesVM;

type
  TSeriesNavigateItemEvent = procedure(Sender: TObject; ProjectId, FolderId,
    ItemId: Integer) of object;

  TPlotPoint = record
    X, Y, Tol: Double;
  end;

  TframeSeries = class(TFrame)
    pnlToolbar: TRzPanel;
    lblProject: TLabel;
    flpButtons: TFlowPanel;
    btnNew: TButton;
    btnEdit: TButton;
    btnAddPoint: TButton;
    btnStatus: TButton;
    btnAbandon: TButton;
    chkShowFailed: TCheckBox;
    btnRefresh: TButton;
    btnCopy: TButton;
    btnSaveCsv: TButton;
    btnRemoveExcluded: TButton;
    pnlStatus: TRzPanel;
    lblStatus: TLabel;
    vstSeries: TVirtualStringTree;
    splMain: TSplitter;
    pcMain: TPageControl;
    tsTable: TTabSheet;
    lblEmpty: TLabel;
    vstTable: TVirtualStringTree;
    tsPlot: TTabSheet;
    pnlPlotOptions: TRzPanel;
    lblX: TLabel;
    cbX: TComboBox;
    lblGroup: TLabel;
    cbGroup: TComboBox;
    chkTrend: TCheckBox;
    lblY: TLabel;
    lblPlotNote: TLabel;
    clbY: TCheckListBox;
    pnlPlot: TRzPanel;
    chtPlot: TChart;
    serGroup1: TLineSeries;
    serGroup2: TLineSeries;
    serGroup3: TLineSeries;
    serGroup4: TLineSeries;
    serGroup5: TLineSeries;
    serGroup6: TLineSeries;
    serGroup7: TLineSeries;
    serGroup8: TLineSeries;
    serTrend: TLineSeries;
    pmRole: TPopupMenu;
    miRoleShown: TMenuItem;
    miRoleHidden: TMenuItem;
    miRoleVaried: TMenuItem;
    miRoleResponse: TMenuItem;
    pmRow: TPopupMenu;
    miMake: TMenuItem;
    miLink: TMenuItem;
    miOpen: TMenuItem;
    miConfirm: TMenuItem;
    miFail: TMenuItem;
    miUnlink: TMenuItem;
    miRemovePoint: TMenuItem;
    dlgSave: TFileSaveDialog;
    procedure btnNewClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnAddPointClick(Sender: TObject);
    procedure btnStatusClick(Sender: TObject);
    procedure btnAbandonClick(Sender: TObject);
    procedure btnRemoveExcludedClick(Sender: TObject);
    procedure chkShowFailedClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveCsvClick(Sender: TObject);
    procedure vstSeriesGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstSeriesGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstSeriesFocusChanged(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex);
    procedure vstTableGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstTableGetHint(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var LineBreakStyle: TVTTooltipLineBreakStyle;
      var HintText: string);
    procedure vstTablePaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    procedure vstTableFocusChanged(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex);
    procedure vstTableHeaderMouseUp(Sender: TVTHeader; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure vstTableMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure vstTableNodeDblClick(Sender: TBaseVirtualTree;
      const HitInfo: THitInfo);
    procedure miRoleClick(Sender: TObject);
    procedure miMakeClick(Sender: TObject);
    procedure miLinkClick(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure miConfirmClick(Sender: TObject);
    procedure miFailClick(Sender: TObject);
    procedure miUnlinkClick(Sender: TObject);
    procedure miRemovePointClick(Sender: TObject);
    procedure pcMainChange(Sender: TObject);
    procedure PlotOptionChange(Sender: TObject);
    procedure chtPlotAfterDraw(Sender: TObject);
    procedure TreeBeforeCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellPaintMode: TVTCellPaintMode;
      CellRect: TRect; var ContentRect: TRect);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
  private
    FVM: TSeriesVM;
    FSeriesLook, FTableLook: TTreeLook;
    FPool: array[0..7] of TLineSeries;
    FBars: array[0..7] of TArray<TPlotPoint>;
    FXCols, FYCols, FGroupCols: TArray<Integer>;
    FXKeys, FYKeys, FGroupKeys: TArray<string>;
    FPlotSeriesId: Integer;
    FMenuColumn: Integer;
    FFilling: Boolean;
    FSelecting: Boolean;
    FOnNavigateItem: TSeriesNavigateItemEvent;
    FOnItemsChanged: TNotifyEvent;
    function LookOf(ATree: TBaseVirtualTree): TTreeLook;
    procedure EnsureVM;
    procedure VMChanged(Sender: TObject);
    procedure FillSeries;
    procedure FillTable;
    procedure FillPlotOptions;
    procedure RebuildPlot;
    procedure UpdateControls;
    procedure ShowError(const AMessage: string);
    function SelectedStatusIs(const AStates: array of Integer): Boolean;
    procedure NavigateTo(AItemId: Integer);
    function ColumnCaption(AIndex: Integer): string;
    function FocusedRow: Integer;
    function PrepareRowMenu(ARow: Integer): Boolean;
    procedure MakeDepositionFor(ASlotId: Integer);
    procedure ItemsChanged;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenProject(AProjectId: Integer; ASeriesId: Integer = 0);
    procedure ResetSession;
    property OnNavigateItem: TSeriesNavigateItemEvent read FOnNavigateItem
      write FOnNavigateItem;
    property OnItemsChanged: TNotifyEvent read FOnItemsChanged write FOnItemsChanged;
  end;

implementation

{$R *.dfm}

uses
  System.Math, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Clipbrd,
  dm_TreeImages,
  unit_TreeBadges,
  unit_ELNThemeHelper,
  unit_Project,
  unit_Item,
  unit_ItemTypes,
  unit_ActionType,
  unit_Equipment,
  unit_Series,
  unit_SeriesColumn,
  unit_SeriesTable,
  unit_SeriesModel,
  unit_SeriesPlanInput,
  unit_DataModel,
  dlg_Action,
  dlg_ItemPicker,
  dlg_SeriesPlan;

const
  EMDASH = #$2014;
  WARNING_GLYPH = #$26A0;
  MAX_GROUPS = 8;
  FIRST_DATA_COLUMN = 2;

function StatusText(AStatus: TSeriesStatus): string;
begin
  case AStatus of
    ssDraft: Result := 'Draft';
    ssActive: Result := 'Active';
    ssClosed: Result := 'Closed';
    ssAbandoned: Result := 'Abandoned';
  else
    Result := '';
  end;
end;

function HitText(const AHit: TSeriesHit): string;
begin
  Result := SeriesNumberText(AHit.Value);
  if AHit.Tol > 0 then
    Result := Result + ' ' + #$00B1 + ' ' + SeriesNumberText(AHit.Tol);
  if AHit.Planned then
    Result := Result + ' (planned)';
end;

function IsPlannedOnly(const ACell: TSeriesCell): Boolean;
var
  H: TSeriesHit;
begin
  Result := Length(ACell.Hits) > 0;
  for H in ACell.Hits do
    if not H.Planned then
      Exit(False);
end;

function CellText(const ACell: TSeriesCell): string;
var
  H: TSeriesHit;
begin
  if ACell.HasPlanned then
    Exit(SeriesNumberText(ACell.PlannedValue));
  if ACell.IsMissing then
    Exit(EMDASH);
  Result := '';
  for H in ACell.Hits do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + HitText(H);
  end;
  if ACell.IsAmbiguous or ACell.Deviation then
    Result := Result + ' ' + WARNING_GLYPH;
end;

function ColumnKey(const AColumn: TSeriesTableColumn): string;
begin
  Result := Format('%d|%d|%s', [Ord(AColumn.RecType), AColumn.ValueTypeId,
    AColumn.SourceKey]);
end;

constructor TframeSeries.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPool[0] := serGroup1;
  FPool[1] := serGroup2;
  FPool[2] := serGroup3;
  FPool[3] := serGroup4;
  FPool[4] := serGroup5;
  FPool[5] := serGroup6;
  FPool[6] := serGroup7;
  FPool[7] := serGroup8;
  pcMain.ActivePage := tsTable;
  ApplyChartTheme(chtPlot);
  FSeriesLook := TTreeLook.Create(vstSeries,
    function(Node: PVirtualNode): TColor
    begin
      Result := TreeRowBackground(vstSeries, nil);
    end,
    function(Node: PVirtualNode): Boolean
    begin
      Result := False;
    end,
    nil, True);
  FTableLook := TTreeLook.Create(vstTable,
    function(Node: PVirtualNode): TColor
    begin
      Result := TreeRowBackground(vstTable, nil);
    end,
    function(Node: PVirtualNode): Boolean
    begin
      Result := False;
    end,
    nil, True);
  UpdateControls;
end;

destructor TframeSeries.Destroy;
begin
  FTableLook.Free;
  FSeriesLook.Free;
  FreeAndNil(FVM);
  inherited;
end;

function TframeSeries.LookOf(ATree: TBaseVirtualTree): TTreeLook;
begin
  if ATree = vstSeries then
    Result := FSeriesLook
  else
    Result := FTableLook;
end;

procedure TframeSeries.TreeBeforeCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
begin
  LookOf(Sender).BeforeCellPaint(TargetCanvas, Node, CellPaintMode, CellRect,
    ContentRect);
end;

procedure TframeSeries.TreeAfterCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex; CellRect: TRect);
begin
  LookOf(Sender).AfterCellPaint(TargetCanvas, Node, Column, CellRect);
end;

procedure TframeSeries.EnsureVM;
begin
  if FVM = nil then
  begin
    FVM := TSeriesVM.Create(Model.Manager, Model.User, Model.Access);
    FVM.OnChanged := VMChanged;
  end;
end;

procedure TframeSeries.ResetSession;
var
  I: Integer;
begin
  FreeAndNil(FVM);
  FPlotSeriesId := 0;
  FSeriesLook.ClearHover;
  FTableLook.ClearHover;
  vstSeries.Clear;
  vstTable.Clear;
  vstTable.Header.Columns.Clear;
  for I := 0 to MAX_GROUPS - 1 do
  begin
    FPool[I].Clear;
    FPool[I].Active := False;
    FBars[I] := nil;
  end;
  serTrend.Clear;
  cbX.Items.Clear;
  cbGroup.Items.Clear;
  clbY.Items.Clear;
  FXCols := nil;
  FYCols := nil;
  FGroupCols := nil;
  FXKeys := nil;
  FYKeys := nil;
  FGroupKeys := nil;
  lblProject.Caption := 'Series';
  lblStatus.Caption := '';
  lblPlotNote.Caption := '';
  UpdateControls;
end;

procedure TframeSeries.OpenProject(AProjectId, ASeriesId: Integer);
var
  P: TProject;
begin
  EnsureVM;
  P := Model.Manager.Find<TProject>(AProjectId);
  if Assigned(P) then
    lblProject.Caption := 'Series in ' + P.Title
  else
    lblProject.Caption := 'Series';
  lblProject.Hint := lblProject.Caption;
  try
    FVM.OpenProject(AProjectId, ASeriesId);
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.ShowError(const AMessage: string);
begin
  MessageDlg(AMessage, mtWarning, [mbOK], 0);
end;

procedure TframeSeries.VMChanged(Sender: TObject);
begin
  if FSelecting then
    vstSeries.Invalidate
  else
    FillSeries;
  FillTable;
  FillPlotOptions;
  RebuildPlot;
  UpdateControls;
end;

procedure TframeSeries.FillSeries;
var
  Node: PVirtualNode;
begin
  FFilling := True;
  vstSeries.BeginUpdate;
  try
    FSeriesLook.ClearHover;
    vstSeries.Clear;
    vstSeries.RootNodeCount := Length(FVM.Series);
    if FVM.SelectedIndex >= 0 then
    begin
      Node := vstSeries.GetFirst;
      while Assigned(Node) and (Integer(Node.Index) <> FVM.SelectedIndex) do
        Node := vstSeries.GetNext(Node);
      if Assigned(Node) then
      begin
        vstSeries.FocusedNode := Node;
        vstSeries.Selected[Node] := True;
      end;
    end;
  finally
    vstSeries.EndUpdate;
    FFilling := False;
  end;
end;

function TframeSeries.ColumnCaption(AIndex: Integer): string;
var
  C: TSeriesTableColumn;
begin
  C := FVM.Table.Columns[AIndex];
  Result := C.Caption;
  if C.Units <> '' then
    Result := Result + ', ' + C.Units;
  case C.Role of
    scrHidden: Result := Result + ' (hidden)';
    scrVaried: Result := Result + ' (varied)';
    scrResponse: Result := Result + ' (response)';
    scrFixed: Result := Result + ' (fixed)';
  end;
end;

procedure TframeSeries.FillTable;
var
  I: Integer;
  Col: TVirtualTreeColumn;
begin
  vstTable.BeginUpdate;
  try
    FTableLook.ClearHover;
    vstTable.Clear;
    vstTable.Header.Columns.Clear;
    Col := vstTable.Header.Columns.Add;
    Col.Text := 'Point';
    Col.Width := 160;
    Col := vstTable.Header.Columns.Add;
    Col.Text := 'State';
    Col.Width := 90;
    for I := 0 to High(FVM.Table.Columns) do
    begin
      Col := vstTable.Header.Columns.Add;
      Col.Text := ColumnCaption(I);
      Col.Hint := Col.Text;
      Col.Width := 130;
    end;
    vstTable.RootNodeCount := Length(FVM.Table.Rows);
  finally
    vstTable.EndUpdate;
  end;
end;

procedure TframeSeries.FillPlotOptions;
var
  I: Integer;
  PrevX, PrevGroup, Key: string;
  PrevY: TDictionary<string, Boolean>;
  SameSeries, Checked: Boolean;
  DefaultX, Pick: Integer;
  C: TSeriesTableColumn;
begin
  PrevX := '';
  PrevGroup := '';
  SameSeries := (FVM.SelectedIndex >= 0) and
    (FVM.Series[FVM.SelectedIndex].Id = FPlotSeriesId);
  PrevY := TDictionary<string, Boolean>.Create;
  try
    if SameSeries then
    begin
      if (cbX.ItemIndex >= 0) and (cbX.ItemIndex <= High(FXKeys)) then
        PrevX := FXKeys[cbX.ItemIndex];
      if (cbGroup.ItemIndex > 0) and (cbGroup.ItemIndex <= High(FGroupKeys)) then
        PrevGroup := FGroupKeys[cbGroup.ItemIndex];
    end;
    for I := 0 to High(FYKeys) do
      if SameSeries and (I < clbY.Items.Count) then
        PrevY.AddOrSetValue(FYKeys[I], clbY.Checked[I]);

    FFilling := True;
    try
      cbX.Items.Clear;
      cbGroup.Items.Clear;
      clbY.Items.Clear;
      FXCols := nil;
      FYCols := nil;
      FXKeys := nil;
      FYKeys := nil;
      FGroupKeys := [''];
      FGroupCols := [-1];
      cbGroup.Items.Add('(none)');
      DefaultX := -1;
      Pick := -1;
      for I := 0 to High(FVM.Table.Columns) do
      begin
        C := FVM.Table.Columns[I];
        if C.Role = scrHidden then
          Continue;
        Key := ColumnKey(C);
        if C.RecType = EXP_CONDITION then
        begin
          FXCols := FXCols + [I];
          FXKeys := FXKeys + [Key];
          cbX.Items.Add(ColumnCaption(I));
          FGroupCols := FGroupCols + [I];
          FGroupKeys := FGroupKeys + [Key];
          cbGroup.Items.Add(ColumnCaption(I));
          if (Key = PrevX) then
            Pick := cbX.Items.Count - 1;
          if (C.Role = scrVaried) and (DefaultX < 0) then
            DefaultX := cbX.Items.Count - 1;
        end
        else
        begin
          FYCols := FYCols + [I];
          FYKeys := FYKeys + [Key];
          clbY.Items.Add(ColumnCaption(I));
          if not PrevY.TryGetValue(Key, Checked) then
            Checked := C.Role = scrResponse;
          clbY.Checked[clbY.Items.Count - 1] := Checked;
        end;
      end;
      if Pick < 0 then
        Pick := DefaultX;
      if (Pick < 0) and (cbX.Items.Count > 0) then
        Pick := 0;
      cbX.ItemIndex := Pick;
      cbGroup.ItemIndex := 0;
      if PrevGroup <> '' then
        for I := 1 to High(FGroupCols) do
          if FGroupKeys[I] = PrevGroup then
            cbGroup.ItemIndex := I;
    finally
      FFilling := False;
    end;
  finally
    PrevY.Free;
  end;
  if FVM.SelectedIndex >= 0 then
    FPlotSeriesId := FVM.Series[FVM.SelectedIndex].Id
  else
    FPlotSeriesId := 0;
end;

procedure TframeSeries.RebuildPlot;
type
  TPointList = TList<TPlotPoint>;
var
  I, R, N, Used, XCol, GCol, YCol, Waiting: Integer;
  Groups: TList<Double>;
  Lists: array[0..MAX_GROUPS - 1] of TPointList;
  Titles: array[0..MAX_GROUPS - 1] of string;
  Notes: TStringList;
  X, Y, Tol, G, GV: Double;
  P: TPlotPoint;
  YCols, NoteCols: TArray<Integer>;
  SumX, SumY, SumXY, SumX2, Denom, Slope, Intercept, XMin, XMax: Double;
  Cmp: IComparer<TPlotPoint>;
  Pts: TArray<TPlotPoint>;
begin
  for I := 0 to MAX_GROUPS - 1 do
  begin
    FPool[I].Clear;
    FPool[I].Active := False;
    FBars[I] := nil;
    Lists[I] := nil;
  end;
  serTrend.Clear;
  serTrend.Active := False;
  lblPlotNote.Caption := '';
  chtPlot.Title.Text.Text := '';
  chtPlot.BottomAxis.Title.Caption := '';
  chtPlot.LeftAxis.Title.Caption := '';
  chkTrend.Enabled := False;
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  chtPlot.Title.Text.Text := FVM.Series[FVM.SelectedIndex].Title;
  if cbX.ItemIndex < 0 then
  begin
    lblPlotNote.Caption := 'This series has no condition column to plot against.';
    Exit;
  end;
  XCol := FXCols[cbX.ItemIndex];
  GCol := -1;
  YCol := -1;
  if (cbGroup.ItemIndex > 0) and (cbGroup.ItemIndex <= High(FGroupCols)) then
    GCol := FGroupCols[cbGroup.ItemIndex];
  YCols := nil;
  for I := 0 to clbY.Items.Count - 1 do
    if clbY.Checked[I] then
      YCols := YCols + [FYCols[I]];
  if Length(YCols) = 0 then
  begin
    lblPlotNote.Caption := 'Tick a result column to plot.';
    Exit;
  end;

  Notes := TStringList.Create;
  Groups := TList<Double>.Create;
  try
    NoteCols := [XCol];
    if GCol >= 0 then
      NoteCols := NoteCols + [GCol, YCols[0]]
    else
      NoteCols := NoteCols + YCols;
    Waiting := FVM.PointsWaiting(NoteCols);
    if Waiting > 0 then
      Notes.Add(Format('%d point(s) wait for confirmed values.', [Waiting]));
    for I := 0 to MAX_GROUPS - 1 do
      Lists[I] := TPointList.Create;
    try
      if GCol >= 0 then
      begin
        YCol := YCols[0];
        if Length(YCols) > 1 then
          Notes.Add('Grouping plots the first ticked result column.');
        for R := 0 to High(FVM.Table.Rows) do
          if FVM.PlotValue(R, GCol, G, Tol) and (Groups.IndexOf(G) < 0) then
            Groups.Add(G);
        Groups.Sort;
        if Groups.Count > MAX_GROUPS then
          Notes.Add('Showing the first 8 groups.');
        N := Min(Groups.Count, MAX_GROUPS);
        for I := 0 to N - 1 do
          Titles[I] := FVM.Table.Columns[GCol].Caption + ' = ' + SeriesNumberText(Groups[I]);
        for R := 0 to High(FVM.Table.Rows) do
        begin
          if not (FVM.PlotValue(R, GCol, GV, Tol) and FVM.PlotValue(R, XCol, X, Tol) and
            FVM.PlotValue(R, YCol, Y, Tol)) then
            Continue;
          for I := 0 to N - 1 do
            if Groups[I] = GV then
            begin
              P.X := X;
              P.Y := Y;
              P.Tol := Tol;
              Lists[I].Add(P);
            end;
        end;
      end
      else
      begin
        N := Min(Length(YCols), MAX_GROUPS);
        if Length(YCols) > MAX_GROUPS then
          Notes.Add('Showing the first 8 curves.');
        for I := 0 to N - 1 do
        begin
          Titles[I] := FVM.Table.Columns[YCols[I]].Caption;
          for R := 0 to High(FVM.Table.Rows) do
            if FVM.PlotValue(R, XCol, X, Tol) and FVM.PlotValue(R, YCols[I], Y, Tol) then
            begin
              P.X := X;
              P.Y := Y;
              P.Tol := Tol;
              Lists[I].Add(P);
            end;
        end;
      end;

      Cmp := TComparer<TPlotPoint>.Construct(
        function(const A, B: TPlotPoint): Integer
        begin
          Result := CompareValue(A.X, B.X);
        end);
      Used := 0;
      Pts := nil;
      for I := 0 to N - 1 do
      begin
        Lists[I].Sort(Cmp);
        FPool[I].Title := Titles[I];
        for P in Lists[I] do
          FPool[I].AddXY(P.X, P.Y);
        FBars[I] := Lists[I].ToArray;
        FPool[I].Active := True;
        if Lists[I].Count > 0 then
        begin
          Inc(Used);
          Pts := FBars[I];
        end;
      end;

      chtPlot.BottomAxis.Title.Caption := ColumnCaption(XCol);
      if GCol < 0 then
      begin
        if Length(YCols) = 1 then
          chtPlot.LeftAxis.Title.Caption := ColumnCaption(YCols[0])
        else
          chtPlot.LeftAxis.Title.Caption := 'Result';
      end
      else
        chtPlot.LeftAxis.Title.Caption := ColumnCaption(YCol);

      chkTrend.Enabled := Used = 1;
      if chkTrend.Checked and (Used = 1) and (Length(Pts) >= 2) then
      begin
        SumX := 0;
        SumY := 0;
        SumXY := 0;
        SumX2 := 0;
        XMin := Pts[0].X;
        XMax := Pts[0].X;
        for P in Pts do
        begin
          SumX := SumX + P.X;
          SumY := SumY + P.Y;
          SumXY := SumXY + P.X * P.Y;
          SumX2 := SumX2 + P.X * P.X;
          if P.X < XMin then
            XMin := P.X;
          if P.X > XMax then
            XMax := P.X;
        end;
        Denom := Length(Pts) * SumX2 - SumX * SumX;
        if Abs(Denom) >= 1e-12 then
        begin
          Slope := (Length(Pts) * SumXY - SumX * SumY) / Denom;
          Intercept := (SumY - Slope * SumX) / Length(Pts);
          serTrend.AddXY(XMin, Slope * XMin + Intercept);
          serTrend.AddXY(XMax, Slope * XMax + Intercept);
          serTrend.Active := True;
        end;
      end;
      if (Used = 0) and (Notes.Count = 0) then
        Notes.Add('No row has a single value for these columns.');
      lblPlotNote.Caption := Notes.Text.Trim;
    finally
      for I := 0 to MAX_GROUPS - 1 do
        Lists[I].Free;
    end;
  finally
    Groups.Free;
    Notes.Free;
  end;
end;

procedure TframeSeries.chtPlotAfterDraw(Sender: TObject);
const
  CAP = 3;
var
  I, PX, Y1, Y2: Integer;
  P: TPlotPoint;
  Rect: TRect;
begin
  Rect := chtPlot.ChartRect;
  for I := 0 to MAX_GROUPS - 1 do
  begin
    if not FPool[I].Active then
      Continue;
    chtPlot.Canvas.Pen.Color := FPool[I].Color;
    chtPlot.Canvas.Pen.Width := 1;
    for P in FBars[I] do
    begin
      if P.Tol <= 0 then
        Continue;
      PX := FPool[I].CalcXPosValue(P.X);
      Y1 := EnsureRange(FPool[I].CalcYPosValue(P.Y + P.Tol), Rect.Top, Rect.Bottom);
      Y2 := EnsureRange(FPool[I].CalcYPosValue(P.Y - P.Tol), Rect.Top, Rect.Bottom);
      if (PX < Rect.Left) or (PX > Rect.Right) then
        Continue;
      chtPlot.Canvas.MoveTo(PX, Y1);
      chtPlot.Canvas.LineTo(PX, Y2);
      chtPlot.Canvas.MoveTo(PX - CAP, Y1);
      chtPlot.Canvas.LineTo(PX + CAP, Y1);
      chtPlot.Canvas.MoveTo(PX - CAP, Y2);
      chtPlot.Canvas.LineTo(PX + CAP, Y2);
    end;
  end;
end;

function TframeSeries.SelectedStatusIs(const AStates: array of Integer): Boolean;
var
  S: Integer;
begin
  Result := False;
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  for S in AStates do
    if Ord(FVM.Series[FVM.SelectedIndex].Status) = S then
      Exit(True);
end;

procedure TframeSeries.UpdateControls;
var
  HasSel, CanEdit, Open: Boolean;
begin
  HasSel := Assigned(FVM) and (FVM.SelectedIndex >= 0);
  CanEdit := Assigned(FVM) and FVM.CanWrite;
  Open := CanEdit and SelectedStatusIs([Ord(ssDraft), Ord(ssActive)]);
  btnNew.Enabled := CanEdit and (FVM.ProjectId <> 0);
  btnEdit.Enabled := Open;
  btnAddPoint.Enabled := Open;
  if SelectedStatusIs([Ord(ssDraft)]) then
  begin
    btnStatus.Caption := 'Start';
    btnStatus.Enabled := CanEdit;
  end
  else
  begin
    if SelectedStatusIs([Ord(ssClosed)]) then
      btnStatus.Caption := 'Reopen'
    else
      btnStatus.Caption := 'Close';
    btnStatus.Enabled := CanEdit and FVM.SelectedIsAuthor
      and SelectedStatusIs([Ord(ssActive), Ord(ssClosed)]);
  end;
  btnAbandon.Enabled := Open;
  btnCopy.Enabled := HasSel;
  btnSaveCsv.Enabled := HasSel;
  btnRefresh.Enabled := Assigned(FVM);
  chkShowFailed.Enabled := HasSel;
  if Assigned(FVM) then
    lblEmpty.Caption := FVM.EmptyText
  else
    lblEmpty.Caption := NO_SERIES_TEXT;
  lblEmpty.Visible := lblEmpty.Caption <> '';
  btnRemoveExcluded.Visible := HasSel and CanEdit
    and SelectedStatusIs([Ord(ssDraft), Ord(ssActive)])
    and (Length(FVM.Table.Excluded) > 0);
  if HasSel and (Length(FVM.Table.Excluded) > 0) then
    lblStatus.Caption := Format(
      '%d deposition(s) are in the recycle bin or another project.',
      [Length(FVM.Table.Excluded)])
  else
    lblStatus.Caption := '';
end;

procedure TframeSeries.btnNewClick(Sender: TObject);
var
  Title, Purpose, Levels: string;
  Plan: TSeriesPlan;
begin
  if FVM = nil then
    Exit;
  Title := '';
  Purpose := '';
  Levels := '';
  Plan := Default(TSeriesPlan);
  while TdlgSeriesPlan.Execute(Model.Manager, FVM.ProjectId, Title, Purpose,
    Plan, Levels, False) do
  try
    FVM.NewSeries(Title, Purpose, Plan, Levels);
    Exit;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnEditClick(Sender: TObject);
var
  Title, Purpose, Levels: string;
  Plan: TSeriesPlan;
  HasPoints: Boolean;
begin
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  Title := FVM.Series[FVM.SelectedIndex].Title;
  Purpose := FVM.Series[FVM.SelectedIndex].Purpose;
  Plan := FVM.Plan.Plan;
  HasPoints := Length(FVM.Plan.Slots) > 0;
  Levels := '';
  while TdlgSeriesPlan.Execute(Model.Manager, FVM.ProjectId, Title, Purpose,
    Plan, Levels, HasPoints) do
  try
    FVM.SavePlan(Title, Purpose, Plan, Levels);
    Exit;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnAddPointClick(Sender: TObject);
var
  Prompts, Values, Units: TArray<string>;
  Levels: TSeriesPoint;
  I: Integer;
  Valid: Boolean;
  Error: string;
  SlotId: Integer;
begin
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  Prompts := FVM.FactorLabels;
  if Length(Prompts) = 0 then
  begin
    ShowError('This series has no factor. Click Edit plan... to add one.');
    Exit;
  end;
  Units := FVM.FactorUnits;
  Prompts := Prompts + ['Reason (optional)'];
  SetLength(Values, Length(Prompts));
  while InputQuery('Add point', Prompts, Values) do
  begin
    SetLength(Levels, Length(Prompts) - 1);
    Valid := True;
    for I := 0 to High(Levels) do
      if not TryParsePlanQuantity(Values[I], Units[I], False, FormatSettings,
        Levels[I], Error) then
      begin
        ShowError(Error);
        Valid := False;
        Break;
      end;
    if not Valid then
      Continue;
    try
      SlotId := FVM.AddPoint(Levels, Trim(Values[High(Values)]));
    except
      on E: ESeriesError do
      begin
        ShowError(E.Message);
        Continue;
      end;
    end;
    if (SlotId > 0) and SelectedStatusIs([Ord(ssActive)]) then
      MakeDepositionFor(SlotId);
    Exit;
  end;
end;

procedure TframeSeries.btnStatusClick(Sender: TObject);
begin
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  try
    case FVM.Series[FVM.SelectedIndex].Status of
      ssDraft: FVM.Start;
      ssClosed: FVM.ChangeStatus(ssActive);
    else
      FVM.ChangeStatus(ssClosed);
    end;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnAbandonClick(Sender: TObject);
begin
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  if MessageDlg('Abandon "' + FVM.Series[FVM.SelectedIndex].Title +
    '"? It stays in the list as Abandoned and cannot be changed.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  try
    FVM.ChangeStatus(ssAbandoned);
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnRemoveExcludedClick(Sender: TObject);
var
  N: Integer;
begin
  if FVM = nil then
    Exit;
  N := Length(FVM.Table.Excluded);
  if N = 0 then
    Exit;
  if MessageDlg(Format('Unlink %d excluded deposition(s) from the series?', [N]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  try
    FVM.RemoveExcluded;
    ItemsChanged;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.chkShowFailedClick(Sender: TObject);
begin
  if FFilling or (FVM = nil) then
    Exit;
  try
    FVM.ShowFailed := chkShowFailed.Checked;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnRefreshClick(Sender: TObject);
begin
  if FVM = nil then
    Exit;
  try
    FVM.Reload;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.btnCopyClick(Sender: TObject);
begin
  if FVM = nil then
    Exit;
  Clipboard.AsText := FVM.ExportText(#9);
end;

procedure TframeSeries.btnSaveCsvClick(Sender: TObject);
var
  Name: string;
  C: Char;
begin
  if (FVM = nil) or (FVM.SelectedIndex < 0) then
    Exit;
  Name := '';
  for C in FVM.Series[FVM.SelectedIndex].Title do
    if TPath.IsValidFileNameChar(C) then
      Name := Name + C
    else
      Name := Name + '_';
  dlgSave.FileName := Name;
  if dlgSave.Execute then
    System.IOUtils.TFile.WriteAllText(dlgSave.FileName, FVM.ExportText(','), TEncoding.UTF8);
end;

procedure TframeSeries.vstSeriesGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(Integer);
end;

procedure TframeSeries.vstSeriesGetCellText(Sender: TCustomVirtualStringTree;
  var E: TVSTGetCellTextEventArgs);
var
  S: TSeriesSummary;
begin
  E.CellText := '';
  if (FVM = nil) or (Integer(E.Node.Index) > High(FVM.Series)) then
    Exit;
  S := FVM.Series[E.Node.Index];
  case E.Column of
    0: E.CellText := S.Title;
    1: E.CellText := StatusText(S.Status);
    2: E.CellText := TSeriesVM.ProgressText(S);
  end;
end;

procedure TframeSeries.vstSeriesFocusChanged(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex);
begin
  if FFilling or (FVM = nil) or (Node = nil) then
    Exit;
  if Integer(Node.Index) = FVM.SelectedIndex then
    Exit;
  FSelecting := True;
  try
    try
      FVM.Select(Node.Index);
    except
      on E: ESeriesError do
        ShowError(E.Message);
    end;
  finally
    FSelecting := False;
  end;
end;

procedure TframeSeries.vstTableGetCellText(Sender: TCustomVirtualStringTree;
  var E: TVSTGetCellTextEventArgs);
var
  Row: TSeriesTableRow;
begin
  E.CellText := '';
  if (FVM = nil) or (Integer(E.Node.Index) > High(FVM.Table.Rows)) then
    Exit;
  Row := FVM.Table.Rows[E.Node.Index];
  case E.Column of
    0: E.CellText := FVM.PointText(E.Node.Index);
    1: E.CellText := TSeriesVM.StateText(Row.State);
  else
    if E.Column - FIRST_DATA_COLUMN <= High(Row.Cells) then
      E.CellText := CellText(Row.Cells[E.Column - FIRST_DATA_COLUMN]);
  end;
end;

procedure TframeSeries.vstTableGetHint(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex;
  var LineBreakStyle: TVTTooltipLineBreakStyle; var HintText: string);
begin
  HintText := '';
  if (FVM = nil) or (Integer(Node.Index) > High(FVM.Table.Rows)) then
    Exit;
  if Column < FIRST_DATA_COLUMN then
    HintText := FVM.Table.Rows[Node.Index].Title
  else
    HintText := FVM.DeviationHint(Node.Index, Column - FIRST_DATA_COLUMN);
end;

procedure TframeSeries.vstTablePaintText(Sender: TBaseVirtualTree;
  const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  TextType: TVSTTextType);
var
  Row: TSeriesTableRow;
  Cell: TSeriesCell;
  Planned: Boolean;
begin
  if (FVM = nil) or (Integer(Node.Index) > High(FVM.Table.Rows)) then
    Exit;
  Row := FVM.Table.Rows[Node.Index];
  if Row.Failed then
  begin
    TargetCanvas.Font.Color := clGrayText;
    Exit;
  end;
  Planned := False;
  if Column = 1 then
    Planned := Row.State = srsPlanned
  else if (Column >= FIRST_DATA_COLUMN)
    and (Column - FIRST_DATA_COLUMN <= High(FVM.Table.Columns)) then
  begin
    if FVM.Table.Columns[Column - FIRST_DATA_COLUMN].Role = scrHidden then
    begin
      TargetCanvas.Font.Color := clGrayText;
      Exit;
    end;
    if Column - FIRST_DATA_COLUMN <= High(Row.Cells) then
    begin
      Cell := Row.Cells[Column - FIRST_DATA_COLUMN];
      Planned := Cell.HasPlanned or IsPlannedOnly(Cell);
    end;
  end;
  if Planned then
  begin
    TargetCanvas.Font.Color := clGrayText;
    TargetCanvas.Font.Style := TargetCanvas.Font.Style + [fsItalic];
  end;
end;

procedure TframeSeries.vstTableFocusChanged(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex);
begin
  UpdateControls;
end;

procedure TframeSeries.vstTableHeaderMouseUp(Sender: TVTHeader;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Col: Integer;
  Cur: TPoint;
  Role: TSeriesColumnRole;
begin
  if (Button <> mbRight) or (FVM = nil) or not FVM.CanWrite then
    Exit;
  Col := Sender.Columns.ColumnFromPosition(Point(X, Y));
  if (Col < FIRST_DATA_COLUMN) or
    (Col - FIRST_DATA_COLUMN > High(FVM.Table.Columns)) then
    Exit;
  FMenuColumn := Col;
  Role := FVM.Table.Columns[Col - FIRST_DATA_COLUMN].Role;
  miRoleShown.Checked := Role = scrShown;
  miRoleHidden.Checked := Role = scrHidden;
  miRoleVaried.Checked := Role = scrVaried;
  miRoleResponse.Checked := Role = scrResponse;
  Cur := Mouse.CursorPos;
  pmRole.Popup(Cur.X, Cur.Y);
end;

procedure TframeSeries.miRoleClick(Sender: TObject);
begin
  if (FVM = nil) or (FMenuColumn < FIRST_DATA_COLUMN) then
    Exit;
  try
    FVM.SetColumnRole(FMenuColumn - FIRST_DATA_COLUMN,
      TSeriesColumnRole((Sender as TMenuItem).Tag));
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.NavigateTo(AItemId: Integer);
var
  Item: TItem;
begin
  if (AItemId <= 0) or not Assigned(FOnNavigateItem) then
    Exit;
  Item := Model.Manager.Find<TItem>(AItemId);
  if (Item = nil) or Item.IsDeleted then
  begin
    MessageDlg('This item is no longer available.', mtInformation, [mbOK], 0);
    Exit;
  end;
  FOnNavigateItem(Self, Item.ProjectID, Item.FolderID, Item.Id);
end;

function TframeSeries.FocusedRow: Integer;
begin
  Result := -1;
  if (FVM = nil) or (vstTable.FocusedNode = nil) then
    Exit;
  if Integer(vstTable.FocusedNode.Index) <= High(FVM.Table.Rows) then
    Result := vstTable.FocusedNode.Index;
end;

function TframeSeries.PrepareRowMenu(ARow: Integer): Boolean;
var
  Actions: TSeriesRowActions;
begin
  Actions := FVM.RowActions(ARow);
  miMake.Visible := raMake in Actions;
  miLink.Visible := raLink in Actions;
  miOpen.Visible := raOpen in Actions;
  miConfirm.Visible := raConfirm in Actions;
  miFail.Visible := raFail in Actions;
  miUnlink.Visible := raUnlink in Actions;
  miRemovePoint.Visible := raRemove in Actions;
  Result := Actions <> [];
end;

procedure TframeSeries.vstTableMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Info: THitInfo;
  Pt: TPoint;
begin
  if (Button <> mbRight) or (FVM = nil) then
    Exit;
  vstTable.GetHitTestInfoAt(X, Y, True, Info);
  if (Info.HitNode = nil) or (Integer(Info.HitNode.Index) > High(FVM.Table.Rows)) then
    Exit;
  vstTable.FocusedNode := Info.HitNode;
  vstTable.Selected[Info.HitNode] := True;
  if not PrepareRowMenu(Info.HitNode.Index) then
    Exit;
  Pt := vstTable.ClientToScreen(Point(X, Y));
  pmRow.Popup(Pt.X, Pt.Y);
end;

procedure TframeSeries.vstTableNodeDblClick(Sender: TBaseVirtualTree;
  const HitInfo: THitInfo);
var
  Row: TSeriesTableRow;
  Cell: TSeriesCell;
  RowIndex, ItemId: Integer;
begin
  if (FVM = nil) or (HitInfo.HitNode = nil) or
    (Integer(HitInfo.HitNode.Index) > High(FVM.Table.Rows)) then
    Exit;
  RowIndex := HitInfo.HitNode.Index;
  Row := FVM.Table.Rows[RowIndex];
  if Row.State = srsPlanned then
  begin
    if raMake in FVM.RowActions(RowIndex) then
      MakeDepositionFor(Row.SlotId);
    Exit;
  end;
  ItemId := Row.ItemId;
  if (HitInfo.HitColumn >= FIRST_DATA_COLUMN) and
    (HitInfo.HitColumn - FIRST_DATA_COLUMN <= High(Row.Cells)) then
  begin
    Cell := Row.Cells[HitInfo.HitColumn - FIRST_DATA_COLUMN];
    if not Cell.IsMissing then
      ItemId := Cell.Hits[0].ItemId;
  end;
  NavigateTo(ItemId);
end;

procedure TframeSeries.MakeDepositionFor(ASlotId: Integer);
var
  Item: TItem;
  Draft: TSeriesDepositionDraft;
  ActionTypeId, EquipmentId: Integer;
begin
  try
    Item := TItem.Create;
    try
      Item.Type_ := TItemType.Synthesis;
      Item.Level := TItemLevel.Proc;
      Item.Title := FVM.DefaultDepositionTitle(ASlotId);
      FVM.DepositionDefaults(ActionTypeId, EquipmentId);
      if ActionTypeId > 0 then
        Item.ActionType := Model.Manager.Find<TActionType>(ActionTypeId);
      if EquipmentId > 0 then
        Item.Equipment := Model.Manager.Find<TEquipment>(EquipmentId);
      if not ShowPrefilledActionDialog(Item, [TItemLevel.Proc]) then
        Exit;
      Draft := Default(TSeriesDepositionDraft);
      Draft.Title := Item.Title;
      Draft.Description := Item.Description;
      Draft.Properties := Item.Properties;
      if Assigned(Item.ActionType) then
        Draft.ActionTypeId := Item.ActionType.Id;
      if Assigned(Item.Equipment) then
        Draft.EquipmentId := Item.Equipment.Id;
      FVM.MakeDeposition(ASlotId, Draft);
      ItemsChanged;
    finally
      Item.Free;
    end;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.ItemsChanged;
begin
  if Assigned(FOnItemsChanged) then
    FOnItemsChanged(Self);
end;

procedure TframeSeries.miMakeClick(Sender: TObject);
var
  Row: Integer;
begin
  Row := FocusedRow;
  if Row >= 0 then
    MakeDepositionFor(FVM.Table.Rows[Row].SlotId);
end;

procedure TframeSeries.miLinkClick(Sender: TObject);
var
  Row, TargetId: Integer;
  TargetTitle: string;
begin
  Row := FocusedRow;
  if Row < 0 then
    Exit;
  if not TdlgItemPicker.Execute(0, TargetId, TargetTitle) then
    Exit;
  try
    FVM.LinkExisting(FVM.Table.Rows[Row].SlotId, TargetId);
    ItemsChanged;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.miOpenClick(Sender: TObject);
var
  Row: Integer;
begin
  Row := FocusedRow;
  if Row >= 0 then
    NavigateTo(FVM.Table.Rows[Row].ItemId);
end;

procedure TframeSeries.miConfirmClick(Sender: TObject);
var
  Row: Integer;
begin
  Row := FocusedRow;
  if Row < 0 then
    Exit;
  try
    if FVM.ConfirmPlanned(FVM.Table.Rows[Row].ItemId) = 0 then
      MessageDlg('No planned values were confirmed. Click Refresh and try again.',
        mtInformation, [mbOK], 0)
    else
      ItemsChanged;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.miFailClick(Sender: TObject);
var
  Row: Integer;
  Reason: string;
begin
  Row := FocusedRow;
  if Row < 0 then
    Exit;
  Reason := '';
  while InputQuery('Mark failed', 'Why did this attempt fail?', Reason) do
  begin
    if Trim(Reason) = '' then
    begin
      ShowError('A reason is required.');
      Continue;
    end;
    try
      FVM.MarkFailed(FVM.Table.Rows[Row].ItemId, Reason);
      ItemsChanged;
    except
      on E: ESeriesError do
        ShowError(E.Message);
    end;
    Exit;
  end;
end;

procedure TframeSeries.miUnlinkClick(Sender: TObject);
var
  Row: TSeriesTableRow;
  Index: Integer;
begin
  Index := FocusedRow;
  if Index < 0 then
    Exit;
  Row := FVM.Table.Rows[Index];
  if MessageDlg('Unlink "' + Row.Title + '" from point ' + FVM.PointText(Index) +
    '? The deposition itself is not deleted.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  try
    FVM.Unlink(Row.ItemId);
    ItemsChanged;
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.miRemovePointClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := FocusedRow;
  if Index < 0 then
    Exit;
  if MessageDlg('Remove point ' + FVM.PointText(Index) + ' from the plan?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  try
    FVM.RemovePoint(FVM.Table.Rows[Index].SlotId);
  except
    on E: ESeriesError do
      ShowError(E.Message);
  end;
end;

procedure TframeSeries.pcMainChange(Sender: TObject);
begin
  if pcMain.ActivePage = tsPlot then
    chtPlot.Repaint;
end;

procedure TframeSeries.PlotOptionChange(Sender: TObject);
begin
  if FFilling or (FVM = nil) then
    Exit;
  RebuildPlot;
end;

end.
