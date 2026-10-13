unit frame_XRFXViewer;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Grids,
  VCLTee.Chart, VCLTee.Series, VCLTee.TeEngine, VCLTee.TeeProcs,
  VclTee.TeeGDIPlus,
  RzPanel, RzStatus, RzLabel,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_XRFXParser;

type
  TframeXRFXViewer = class(TFrame)
    pnlStatus: TRzPanel;
    spThetaLabel: TRzStatusPane;
    spTheta: TRzStatusPane;
    spRLabel: TRzStatusPane;
    spR: TRzStatusPane;
    spFile: TRzStatusPane;
    pnlMetrics: TRzPanel;
    chrtPeakPos: TChart;
    chrtR: TChart;
    chrtFWHM: TChart;
    chrtSNR: TChart;
    splMetrics: TSplitter;
    chrtCurves: TChart;
    pnlStructure: TRzPanel;
    lblStructureHeader: TRzLabel;
    grdStructure: TStringGrid;
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure ChartResize(Sender: TObject);
    procedure grdStructureDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure pnlMetricsResize(Sender: TObject);
  private
    FLoadedResult: TXRFXLoadedResult;
    FSubstrateRow: Integer;
    FStackHeaderRows: TArray<Integer>;
    function IsStackHeaderRow(ARow: Integer): Boolean;
    function PickMainStackIndex(const Structure: TXRFXStructure): Integer;
    procedure DisplayCurves(const Curves: TArray<TXRFXCurveData>);
    procedure DisplayStructure(const Structure: TXRFXStructure;
      const Summary: TXRFXStructureSummary);
    procedure DisplayMetrics(const M: TXRFXManifest;
      const Curves: TArray<TXRFXCurveData>);
    procedure PositionStructurePanel;
  public
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  System.Generics.Collections, System.JSON, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}


function FindPeakPosition(const Curve: TXRFXCurveData): Double;
var
  i, MaxIdx: Integer;
  MaxR: Double;
begin
  Result := 0;
  if Length(Curve.Refl) = 0 then Exit;
  MaxIdx := 0;
  MaxR := Curve.Refl[0];
  for i := 1 to High(Curve.Refl) do
    if Curve.Refl[i] > MaxR then
    begin
      MaxR := Curve.Refl[i];
      MaxIdx := i;
    end;
  if MaxIdx <= High(Curve.Theta) then
    Result := Curve.Theta[MaxIdx];
end;

function CalcSNR(const Curve: TXRFXCurveData): Double;
var
  i, TailStart, PeakIdx: Integer;
  MaxR, TailSum: Double;
  TailCount: Integer;
begin
  Result := 0;
  if Length(Curve.Refl) < 10 then Exit;

  PeakIdx := 0;
  MaxR := Curve.Refl[0];
  for i := 1 to High(Curve.Refl) do
    if Curve.Refl[i] > MaxR then
    begin
      MaxR := Curve.Refl[i];
      PeakIdx := i;
    end;

  TailStart := Length(Curve.Refl) - Length(Curve.Refl) div 5;
  if TailStart <= PeakIdx then
    TailStart := PeakIdx + (Length(Curve.Refl) - PeakIdx) div 2;
  if TailStart >= Length(Curve.Refl) then
    TailStart := Length(Curve.Refl) - 1;

  TailSum := 0;
  TailCount := 0;
  for i := TailStart to High(Curve.Refl) do
  begin
    TailSum := TailSum + Curve.Refl[i];
    Inc(TailCount);
  end;

  if (TailCount > 0) and (TailSum / TailCount > 1e-15) then
    Result := MaxR / (TailSum / TailCount);
end;

function FindCurveForElement(const Curves: TArray<TXRFXCurveData>;
  const ElementName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Curves) do
    if SameText(Curves[i].Element, ElementName) then
      Exit(i);
  Result := -1;
end;

procedure AddBarToChart(AChart: TChart; AValue: Double;
  const ALabel, AFormat: string; AColor: TColor);
var
  S: TBarSeries;
begin
  if AChart.SeriesCount = 0 then
  begin
    S := TBarSeries.Create(AChart);
    S.Marks.Visible := True;
    S.Marks.Style := smsValue;
    S.Marks.Font.Height := -11;
    S.ColorEachPoint := True;
    AChart.AddSeries(S);
  end
  else
    S := AChart.Series[0] as TBarSeries;

  S.Add(AValue, ALabel, AColor);
  S.ValueFormat := AFormat;
end;


destructor TframeXRFXViewer.Destroy;
begin
  if FLoadedResult.TempDir <> '' then
    CleanupXRFXTemp(FLoadedResult.TempDir);
  inherited;
end;

procedure TframeXRFXViewer.LoadFromFile(const FileName: string);
begin
  if FLoadedResult.TempDir <> '' then
    CleanupXRFXTemp(FLoadedResult.TempDir);

  chrtCurves.FreeAllSeries;
  pnlStructure.Visible := False;

  FLoadedResult := LoadXRFXFile(FileName);

  DisplayCurves(FLoadedResult.Curves);
  DisplayStructure(FLoadedResult.Structure, FLoadedResult.Manifest.Structure);
  DisplayMetrics(FLoadedResult.Manifest, FLoadedResult.Curves);

  ApplyChartTheme(chrtCurves);
  ApplyChartTheme(chrtPeakPos);
  ApplyChartTheme(chrtR);
  ApplyChartTheme(chrtFWHM);
  ApplyChartTheme(chrtSNR);

  spFile.Caption := ExtractFileName(FileName) +
    Format('  |  FoM: %.4f', [FLoadedResult.Manifest.FoM]);
end;


procedure TframeXRFXViewer.DisplayCurves(const Curves: TArray<TXRFXCurveData>);
var
  i, j: Integer;
  Series: TLineSeries;
begin
  chrtCurves.FreeAllSeries;

  for i := 0 to High(Curves) do
  begin
    Series := TLineSeries.Create(chrtCurves);
    Series.LinePen.Width := 2;
    Series.Title := Curves[i].Element;

    for j := 0 to High(Curves[i].Theta) do
      Series.AddXY(Curves[i].Theta[j], Curves[i].Refl[j]);

    chrtCurves.AddSeries(Series);
  end;

  chrtCurves.LeftAxis.Logarithmic := False;
  chrtCurves.LeftAxis.Automatic := True;
end;


procedure TframeXRFXViewer.DisplayStructure(const Structure: TXRFXStructure;
  const Summary: TXRFXStructureSummary);
var
  i, j, Row, TotalRows, TotalLayers, W: Integer;
begin
  TotalLayers := 0;
  for i := 0 to High(Structure.Stacks) do
    Inc(TotalLayers, Length(Structure.Stacks[i].Layers));

  if TotalLayers = 0 then
  begin
    pnlStructure.Visible := False;
    Exit;
  end;

  lblStructureHeader.Caption := Format('d=%.1f  '#947'=%.3f  N=%d',
    [Summary.D, Summary.Gamma, Summary.N]);

  TotalRows := 1 + Length(Structure.Stacks) + TotalLayers + 1;
  grdStructure.RowCount := TotalRows;
  grdStructure.ColCount := 4;
  FSubstrateRow := TotalRows - 1;
  SetLength(FStackHeaderRows, Length(Structure.Stacks));

  W := grdStructure.ClientWidth;
  if W < 100 then W := 294;
  grdStructure.ColWidths[0] := W * 28 div 100;
  grdStructure.ColWidths[1] := W * 24 div 100;
  grdStructure.ColWidths[2] := W * 24 div 100;
  grdStructure.ColWidths[3] := W - grdStructure.ColWidths[0]
    - grdStructure.ColWidths[1] - grdStructure.ColWidths[2] - 4;

  grdStructure.Cells[0, 0] := 'Material';
  grdStructure.Cells[1, 0] := 'H (' + #197 + ')';
  grdStructure.Cells[2, 0] := #963 + ' (' + #197 + ')';
  grdStructure.Cells[3, 0] := #961 + ' (g/cm' + #179 + ')';

  Row := 1;
  for i := 0 to High(Structure.Stacks) do
  begin
    FStackHeaderRows[i] := Row;
    grdStructure.Cells[0, Row] := Format('%s x %d',
      [Structure.Stacks[i].StackType, Structure.Stacks[i].N]);
    grdStructure.Cells[1, Row] := '';
    grdStructure.Cells[2, Row] := '';
    grdStructure.Cells[3, Row] := '';
    Inc(Row);
    for j := 0 to High(Structure.Stacks[i].Layers) do
    begin
      grdStructure.Cells[0, Row] := Structure.Stacks[i].Layers[j].Material;
      grdStructure.Cells[1, Row] := Format('%.2f', [Structure.Stacks[i].Layers[j].Thickness]);
      grdStructure.Cells[2, Row] := Format('%.2f', [Structure.Stacks[i].Layers[j].Roughness]);
      grdStructure.Cells[3, Row] := Format('%.2f', [Structure.Stacks[i].Layers[j].Density]);
      Inc(Row);
    end;
  end;

  Row := FSubstrateRow;
  grdStructure.Cells[0, Row] := Structure.Substrate.Material + ' (sub)';
  grdStructure.Cells[1, Row] := #8212;
  grdStructure.Cells[2, Row] := Format('%.2f', [Structure.Substrate.Roughness]);
  grdStructure.Cells[3, Row] := Format('%.2f', [Structure.Substrate.Density]);

  pnlStructure.Height := lblStructureHeader.Height + lblStructureHeader.Margins.Top
    + lblStructureHeader.Margins.Bottom + grdStructure.Margins.Top
    + grdStructure.Margins.Bottom
    + TotalRows * (grdStructure.DefaultRowHeight + 1) + 2;

  PositionStructurePanel;
  pnlStructure.Visible := True;
  pnlStructure.BringToFront;
end;

function TframeXRFXViewer.IsStackHeaderRow(ARow: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(FStackHeaderRows) do
    if FStackHeaderRows[i] = ARow then Exit(True);
  Result := False;
end;

function TframeXRFXViewer.PickMainStackIndex(const Structure: TXRFXStructure): Integer;
var
  i, BestN: Integer;
begin
  Result := -1;
  for i := 0 to High(Structure.Stacks) do
    if SameText(Structure.Stacks[i].StackType, 'ML') then
      Exit(i);

  BestN := -1;
  for i := 0 to High(Structure.Stacks) do
    if Structure.Stacks[i].N > BestN then
    begin
      BestN := Structure.Stacks[i].N;
      Result := i;
    end;
end;

procedure TframeXRFXViewer.PositionStructurePanel;
begin
  pnlStructure.Parent := chrtCurves;
  pnlStructure.Left := chrtCurves.ClientWidth - pnlStructure.Width
    - chrtCurves.ClientWidth * 4 div 100;
  pnlStructure.Top := chrtCurves.ClientHeight * 4 div 100;
end;


procedure TframeXRFXViewer.DisplayMetrics(const M: TXRFXManifest;
  const Curves: TArray<TXRFXCurveData>);
const
  BarColors: array[0..7] of TColor = (
    $CC6633, $3399CC, $33CC66, $CC3366,
    $9966CC, $66CCCC, $CCCC33, $CC9933);
var
  i, CurveIdx: Integer;
  PeakPos, SNR: Double;
  C: TColor;
begin
  chrtPeakPos.FreeAllSeries;
  chrtR.FreeAllSeries;
  chrtFWHM.FreeAllSeries;
  chrtSNR.FreeAllSeries;

  if Length(M.PerElement) = 0 then
  begin
    pnlMetrics.Visible := False;
    splMetrics.Visible := False;
    Exit;
  end;

  for i := 0 to High(M.PerElement) do
  begin
    PeakPos := 0;
    SNR := 0;
    CurveIdx := FindCurveForElement(Curves, M.PerElement[i].Line);
    if CurveIdx >= 0 then
    begin
      PeakPos := FindPeakPosition(Curves[CurveIdx]);
      SNR := CalcSNR(Curves[CurveIdx]);
    end;

    C := BarColors[i mod Length(BarColors)];

    AddBarToChart(chrtPeakPos, PeakPos, M.PerElement[i].Line, '##0.0#', C);
    AddBarToChart(chrtR, M.PerElement[i].PeakR, M.PerElement[i].Line, '#0.0000', C);
    AddBarToChart(chrtFWHM, M.PerElement[i].FWHM, M.PerElement[i].Line, '#0.000', C);
    AddBarToChart(chrtSNR, SNR, M.PerElement[i].Line, '#0.0', C);
  end;

  pnlMetrics.Visible := True;
  splMetrics.Visible := True;
end;


procedure TframeXRFXViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  xv, yv: Double;
begin
  if chrtCurves.SeriesCount = 0 then Exit;

  xv := chrtCurves.Series[0].XScreenToValue(X);
  yv := chrtCurves.Series[0].YScreenToValue(Y);

  spTheta.Caption := FloatToStrF(xv, ffFixed, 4, 3);
  if yv < 0.01 then
    spR.Caption := FloatToStrF(yv, ffExponent, 3, 2)
  else
    spR.Caption := FloatToStrF(yv, ffFixed, 4, 3);
end;

procedure TframeXRFXViewer.ChartResize(Sender: TObject);
begin
  if pnlStructure.Visible then
    PositionStructurePanel;
end;

procedure TframeXRFXViewer.grdStructureDrawCell(Sender: TObject; ACol,
  ARow: Integer; Rect: TRect; State: TGridDrawState);
var
  Grid: TStringGrid;
  S: string;
  TextRect: TRect;
  Flags: Cardinal;
begin
  Grid := TStringGrid(Sender);
  Grid.Canvas.Font.Assign(Grid.Font);

  if ARow = 0 then
  begin
    Grid.Canvas.Brush.Color := $E0E0E0;
    Grid.Canvas.Font.Style := [fsBold];
  end
  else if IsStackHeaderRow(ARow) then
  begin
    Grid.Canvas.Brush.Color := $F0F0F0;
    Grid.Canvas.Font.Style := [fsBold];
  end
  else if ARow = FSubstrateRow then
  begin
    Grid.Canvas.Brush.Color := $F0F0FF;
    Grid.Canvas.Font.Style := [];
  end
  else
  begin
    Grid.Canvas.Brush.Color := clWhite;
    Grid.Canvas.Font.Style := [];
  end;

  Grid.Canvas.FillRect(Rect);

  S := Grid.Cells[ACol, ARow];
  if S = '' then Exit;

  TextRect := Rect;
  InflateRect(TextRect, -3, -1);

  Flags := DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS;
  if (ACol > 0) and (ARow > 0) and not IsStackHeaderRow(ARow) then
    Flags := Flags or DT_RIGHT
  else
    Flags := Flags or DT_LEFT;

  DrawText(Grid.Canvas.Handle, PChar(S), Length(S), TextRect, Flags);
end;

procedure TframeXRFXViewer.pnlMetricsResize(Sender: TObject);
var
  W: Integer;
begin
  W := pnlMetrics.ClientWidth div 4;
  chrtPeakPos.Width := W;
  chrtR.Width := W;
  chrtFWHM.Width := W;
end;


function TframeXRFXViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
begin
  Result := nil;
  if chrtCurves.SeriesCount = 0 then
    Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    chrtCurves.Draw(Large.Canvas, System.Classes.Rect(0, 0, 800, 600));
    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

function TframeXRFXViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  M: TXRFXManifest;
  S: TXRFXStructure;
  I, MainIdx: Integer;
  StructName: string;
begin
  Result := nil;
  M := FLoadedResult.Manifest;
  S := FLoadedResult.Structure;
  if M.Version = 0 then
    Exit;

  StructName := '';
  MainIdx := PickMainStackIndex(S);
  if MainIdx >= 0 then
    for I := 0 to High(S.Stacks[MainIdx].Layers) do
    begin
      if I > 0 then
        StructName := StructName + '/';
      StructName := StructName + S.Stacks[MainIdx].Layers[I].Material;
    end;

  List := TList<TPluginKeyValue>.Create;
  try
    KV.IsKey := True;
    KV.Name := StructName + ' Period';
    KV.Value := M.Structure.D;
    KV.Units := 'A';
    KV.RecType := prResult;
    List.Add(KV);

    KV.Name := StructName + ' Gamma';
    KV.Value := M.Structure.Gamma;
    KV.Units := '';
    KV.RecType := prResult;
    List.Add(KV);

    KV.IsKey := False;
    KV.Name := 'Figure of Merit';
    KV.Value := M.FoM;
    KV.Units := '';
    KV.RecType := prResult;
    List.Add(KV);

    KV.Name := 'Stack Repeats';
    KV.Value := M.Structure.N;
    KV.Units := '';
    KV.RecType := prCondition;
    List.Add(KV);

    for I := 0 to High(M.PerElement) do
    begin
      KV.Name := M.PerElement[I].Line + ' Peak R';
      KV.Value := M.PerElement[I].PeakR;
      KV.Units := '';
      KV.RecType := prResult;
      List.Add(KV);

      KV.Name := M.PerElement[I].Line + ' FWHM';
      KV.Value := M.PerElement[I].FWHM;
      KV.Units := 'deg';
      KV.RecType := prResult;
      List.Add(KV);
    end;

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeXRFXViewer.GetDetailedInfo: string;
var
  J, JStackObj, JLayer, JSubs: TJSONObject;
  JStacks, JLayers, JElements, JTargets: TJSONArray;
  I, K: Integer;
  M: TXRFXManifest;
  S: TXRFXStructure;
begin
  Result := '';
  M := FLoadedResult.Manifest;
  S := FLoadedResult.Structure;
  if M.Version = 0 then
    Exit;

  J := TJSONObject.Create;
  try
    J.AddPair('version', TJSONNumber.Create(M.Version));
    J.AddPair('created', M.Created);
    J.AddPair('generator', M.Generator);
    J.AddPair('fom', JNum(M.FoM));
    J.AddPair('substrate', M.Substrate);

    JTargets := TJSONArray.Create;
    for I := 0 to High(M.TargetLines) do
      JTargets.Add(M.TargetLines[I]);
    J.AddPair('targetLines', JTargets);

    JStacks := TJSONArray.Create;
    for I := 0 to High(S.Stacks) do
    begin
      JStackObj := TJSONObject.Create;
      JStackObj.AddPair('type', S.Stacks[I].StackType);
      JStackObj.AddPair('N', TJSONNumber.Create(S.Stacks[I].N));
      JLayers := TJSONArray.Create;
      for K := 0 to High(S.Stacks[I].Layers) do
      begin
        JLayer := TJSONObject.Create;
        JLayer.AddPair('material', S.Stacks[I].Layers[K].Material);
        JLayer.AddPair('thickness_A', JNum(S.Stacks[I].Layers[K].Thickness));
        JLayer.AddPair('roughness_A', JNum(S.Stacks[I].Layers[K].Roughness));
        JLayer.AddPair('density_gcm3', JNum(S.Stacks[I].Layers[K].Density));
        JLayers.AddElement(JLayer);
      end;
      JStackObj.AddPair('layers', JLayers);
      JStacks.AddElement(JStackObj);
    end;
    J.AddPair('stacks', JStacks);

    JSubs := TJSONObject.Create;
    JSubs.AddPair('material', S.Substrate.Material);
    JSubs.AddPair('roughness_A', JNum(S.Substrate.Roughness));
    JSubs.AddPair('density_gcm3', JNum(S.Substrate.Density));
    J.AddPair('substrate_detail', JSubs);

    JElements := TJSONArray.Create;
    for I := 0 to High(M.PerElement) do
    begin
      JLayer := TJSONObject.Create;
      JLayer.AddPair('line', M.PerElement[I].Line);
      JLayer.AddPair('peakR', JNum(M.PerElement[I].PeakR));
      JLayer.AddPair('fwhm_deg', JNum(M.PerElement[I].FWHM));
      JElements.AddElement(JLayer);
    end;
    J.AddPair('perElement', JElements);

    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
