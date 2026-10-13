unit frame_XRCViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.Grids, Vcl.StdCtrls,
  VCLTee.TeEngine, VCLTee.Series, Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzStatus,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_XRCProject;

type
  TRowKind = (rkStackHeader, rkLayer, rkSubstrate);

  TSeriesList = array of TFastLineSeries;

  TframeXRCViewer = class(TFrame)
    Chart: TChart;
    PanelStructure: TPanel;
    LabelHeader: TLabel;
    GridStructure: TStringGrid;
    StatusBar: TRzStatusBar;
    RzStatusPane1: TRzStatusPane;
    StatusX: TRzStatusPane;
    RzStatusPane2: TRzStatusPane;
    StatusY: TRzStatusPane;
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GridStructureDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
  private
    FSeriesList: TSeriesList;
    FProject: TXRCProject;
    FRowKinds: array of TRowKind;

    procedure ApplyAxis;
    procedure PopulateStructureGrid;
    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadCurves(const FileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  unit_ELNPreviewUtils,
  unit_ELNThemeHelper,
  unit_XRCProjectOutput;

{$R *.dfm}

constructor TframeXRCViewer.Create(AOwner: TComponent);
begin
  inherited;
  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnDblClick := ChartDblClick;
end;

procedure TframeXRCViewer.ChartMouseMove(Sender: TObject; Shift: TShiftState;
    X, Y: Integer);
var
  xv, yv: single;
  R: TRect;
begin
  if Chart.SeriesList.Count = 0 then Exit;

  xv := Chart.Series[0].XScreenToValue(X);
  yv := Chart.Series[0].YScreenToValue(Y);
  StatusX.Caption := FloatToStrF(xv, ffFixed, 4, 3);
  if yv < 0.01 then
    StatusY.Caption := FloatToStrF(yv, ffExponent, 3, 2)
  else
    StatusY.Caption := FloatToStrF(yv, ffFixed, 4, 3);

  R := Chart.Legend.RectLegend;

  if (X > R.Left) and (X < R.Right) and (Y > R.Top) and (Y < R.Bottom) then
    Chart.Cursor := crArrow
  else
    Chart.Cursor := crCross;
end;

procedure TframeXRCViewer.LoadCurves(const FileName: string);
var
  I, K: Integer;
  Series: TFastLineSeries;
begin
  Chart.SeriesList.Clear;
  SetLength(FSeriesList, 0);
  Chart.AutoRepaint := False;
  try
    FProject := LoadXRCProject(FileName);
    SetLength(FSeriesList, Length(FProject.Curves));
    for I := 0 to High(FProject.Curves) do
    begin
      Series := TFastLineSeries.Create(Chart);
      Series.ParentChart := Chart;
      Series.LinePen.Width := 3;
      if FProject.Curves[I].Title <> '' then
        Series.Title := FProject.Curves[I].Title
      else
        Series.Title := FProject.Curves[I].FileName;
      Series.BeginUpdate;
      for K := 0 to High(FProject.Curves[I].X) do
        Series.AddXY(FProject.Curves[I].X[K], FProject.Curves[I].Y[K]);
      Series.EndUpdate;
      FSeriesList[I] := Series;
    end;
    ApplyAxis;
    PopulateStructureGrid;
    Chart.Legend.Visible := not FProject.Model.Valid;
    ApplyChartTheme(Chart);
  finally
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;
end;

function TframeXRCViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
begin
  Result := nil;
  if Chart.SeriesList.Count = 0 then
    Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    Chart.Draw(Large.Canvas, Rect(0, 0, 800, 600));
    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

procedure TframeXRCViewer.ApplyAxis;
begin
  if not FProject.Calculation.Present then
    Exit;
  Chart.LeftAxis.Logarithmic := FProject.ChartLogScale;
  Chart.LeftAxis.Maximum := 1;
  if not Chart.LeftAxis.Logarithmic then
  begin
    Chart.LeftAxis.AxisValuesFormat := '0.000';
    Chart.LeftAxis.Minimum := 0;
  end
  else
  begin
    Chart.LeftAxis.AxisValuesFormat := '0x10E-0';
    Chart.LeftAxis.Minimum := FProject.ChartMinLimit;
  end;
end;

procedure TframeXRCViewer.PopulateStructureGrid;
var
  Row, S, L, TotalRows, W: Integer;
begin
  if not FProject.Model.Valid then
  begin
    PanelStructure.Visible := False;
    Exit;
  end;

  TotalRows := 1;
  for S := 0 to High(FProject.Model.Stacks) do
    TotalRows := TotalRows + 1 + Length(FProject.Model.Stacks[S].Layers);
  Inc(TotalRows);

  GridStructure.RowCount := TotalRows;
  GridStructure.ColCount := 4;
  SetLength(FRowKinds, TotalRows);

  W := GridStructure.ClientWidth;
  if W < 100 then W := 480;
  GridStructure.ColWidths[0] := W * 26 div 100;
  GridStructure.ColWidths[1] := W * 21 div 100;
  GridStructure.ColWidths[2] := W * 21 div 100;
  GridStructure.ColWidths[3] := W - GridStructure.ColWidths[0]
    - GridStructure.ColWidths[1] - GridStructure.ColWidths[2] - 4;

  GridStructure.Cells[0, 0] := 'Material';
  GridStructure.Cells[1, 0] := 'H (' + #197 + ')';
  GridStructure.Cells[2, 0] := #963 + ' (' + #197 + ')';
  GridStructure.Cells[3, 0] := #961 + ' (g/cm' + #179 + ')';

  Row := 1;
  for S := 0 to High(FProject.Model.Stacks) do
  begin
    if FProject.Model.Stacks[S].N > 1 then
      GridStructure.Cells[0, Row] := Format('%s  ' + #215 + '%d',
        [FProject.Model.Stacks[S].Title, FProject.Model.Stacks[S].N])
    else
      GridStructure.Cells[0, Row] := FProject.Model.Stacks[S].Title;
    GridStructure.Cells[1, Row] := '';
    GridStructure.Cells[2, Row] := '';
    GridStructure.Cells[3, Row] := '';
    FRowKinds[Row] := rkStackHeader;
    Inc(Row);

    for L := 0 to High(FProject.Model.Stacks[S].Layers) do
    begin
      GridStructure.Cells[0, Row] := '  ' + FProject.Model.Stacks[S].Layers[L].Material;
      GridStructure.Cells[1, Row] := FormatFloat('0.00', FProject.Model.Stacks[S].Layers[L].Value[xpThickness]);
      GridStructure.Cells[2, Row] := FormatFloat('0.00', FProject.Model.Stacks[S].Layers[L].Value[xpRoughness]);
      if FProject.Model.Stacks[S].Layers[L].Value[xpDensity] > 0.001 then
        GridStructure.Cells[3, Row] := FormatFloat('0.00', FProject.Model.Stacks[S].Layers[L].Value[xpDensity])
      else
        GridStructure.Cells[3, Row] := #8212;
      FRowKinds[Row] := rkLayer;
      Inc(Row);
    end;
  end;

  GridStructure.Cells[0, Row] := '  ' + FProject.Model.SubsMaterial + ' (sub)';
  GridStructure.Cells[1, Row] := #8212;
  GridStructure.Cells[2, Row] := FormatFloat('0.00', FProject.Model.SubsSigma);
  GridStructure.Cells[3, Row] := FormatFloat('0.00', FProject.Model.SubsRho);
  FRowKinds[Row] := rkSubstrate;

  PanelStructure.Height := LabelHeader.Height + LabelHeader.Margins.Top
    + LabelHeader.Margins.Bottom + GridStructure.Margins.Top
    + GridStructure.Margins.Bottom
    + TotalRows * (GridStructure.DefaultRowHeight + 1);
  PanelStructure.Parent := Chart;
  PanelStructure.Left := Chart.ClientWidth - PanelStructure.Width - Chart.ClientWidth div 50;
  PanelStructure.Top := Chart.ClientHeight div 50;

  PanelStructure.StyleElements := PanelStructure.StyleElements - [seClient];
  PanelStructure.ParentBackground := False;
  if IsDarkTheme then
    PanelStructure.Color := ThemePanelColor
  else
    PanelStructure.Color := $F0F0F0;
  LabelHeader.Font.Color := ThemeTextColor;
  PanelStructure.Visible := True;
  PanelStructure.BringToFront;
end;

procedure TframeXRCViewer.GridStructureDrawCell(Sender: TObject; ACol,
  ARow: Integer; Rect: TRect; State: TGridDrawState);
var
  Grid: TStringGrid;
  S: string;
  TextRect, LastRect: TRect;
  Flags: Cardinal;
begin
  Grid := TStringGrid(Sender);
  Grid.Canvas.Font.Assign(Grid.Font);

  if ARow = 0 then
  begin
    Grid.Canvas.Brush.Color := ThemePanelColor;
    Grid.Canvas.Font.Style := [fsBold];
    Grid.Canvas.Font.Color := ThemeTextColor;
  end
  else if (ARow < Length(FRowKinds)) and (FRowKinds[ARow] = rkStackHeader) then
  begin
    if IsDarkTheme then
      Grid.Canvas.Brush.Color := $443300
    else
      Grid.Canvas.Brush.Color := $FFE8CC;
    Grid.Canvas.Font.Style := [fsBold];
    Grid.Canvas.Font.Color := ThemeTextColor;
  end
  else if (ARow < Length(FRowKinds)) and (FRowKinds[ARow] = rkSubstrate) then
  begin
    if IsDarkTheme then
      Grid.Canvas.Brush.Color := $333344
    else
      Grid.Canvas.Brush.Color := $F0F0FF;
    Grid.Canvas.Font.Style := [];
    Grid.Canvas.Font.Color := ThemeTextColor;
  end
  else
  begin
    Grid.Canvas.Brush.Color := ThemeWallColor;
    Grid.Canvas.Font.Style := [];
    Grid.Canvas.Font.Color := ThemeTextColor;
  end;

  if (ARow > 0) and (ARow < Length(FRowKinds))
    and (FRowKinds[ARow] = rkStackHeader) then
  begin
    if ACol > 0 then Exit;

    TextRect := Rect;
    LastRect := Grid.CellRect(Grid.ColCount - 1, ARow);
    if LastRect.Right > TextRect.Right then
      TextRect.Right := LastRect.Right;
    Grid.Canvas.FillRect(TextRect);

    S := Grid.Cells[0, ARow];
    InflateRect(TextRect, -4, -2);
    DrawText(Grid.Canvas.Handle, PChar(S), Length(S), TextRect,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
    Exit;
  end;

  Grid.Canvas.FillRect(Rect);

  S := Grid.Cells[ACol, ARow];
  if S = '' then Exit;

  TextRect := Rect;
  InflateRect(TextRect, -4, -2);

  Flags := DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS;
  if (ACol > 0) and (ARow > 0) then
    Flags := Flags or DT_RIGHT
  else
    Flags := Flags or DT_LEFT;

  DrawText(Grid.Canvas.Handle, PChar(S), Length(S), TextRect, Flags);
end;

procedure TframeXRCViewer.ChartMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  Factor, RangeX, RangeY, CenterX, CenterY: Double;
begin
  if WheelDelta > 0 then
    Factor := 0.8
  else
    Factor := 1.25;

  RangeX := Chart.BottomAxis.Maximum - Chart.BottomAxis.Minimum;
  RangeY := Chart.LeftAxis.Maximum - Chart.LeftAxis.Minimum;
  CenterX := (Chart.BottomAxis.Maximum + Chart.BottomAxis.Minimum) / 2;
  CenterY := (Chart.LeftAxis.Maximum + Chart.LeftAxis.Minimum) / 2;

  Chart.BottomAxis.SetMinMax(
    CenterX - RangeX * Factor / 2,
    CenterX + RangeX * Factor / 2);
  Chart.LeftAxis.SetMinMax(
    CenterY - RangeY * Factor / 2,
    CenterY + RangeY * Factor / 2);

  Handled := True;
end;

procedure TframeXRCViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;

function TframeXRCViewer.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := BuildXRCKeyValues(FProject);
end;

function TframeXRCViewer.GetDetailedInfo: string;
begin
  if FProject.Model.Valid then
    Result := BuildXRCDetailedInfo(FProject)
  else
    Result := '';
end;

end.
