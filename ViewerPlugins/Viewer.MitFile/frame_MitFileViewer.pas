unit frame_MitFileViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Math, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.CheckLst,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton, RzStatus,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_MitFileParser, unit_MitAnalysis;

const
  GRID_POINTS = 200;

type

  TframeMitFileViewer = class(TFrame)
    pnlLeft: TPanel;
    lblRecords: TLabel;
    lblInfo: TLabel;
    lstRecords: TCheckListBox;
    pnlToolbar: TPanel;
    btnSelectAll: TRzBitBtn;
    btnSelectNone: TRzBitBtn;
    btnAverage: TRzBitBtn;
    Status: TRzStatusBar;
    spStatus: TRzStatusPane;
    Chart: TChart;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    serLoading: TFastLineSeries;
    serUnloading: TFastLineSeries;
    serDrift: TFastLineSeries;
    dlgSave: TSaveDialog;
    btnFit: TRzBitBtn;
    procedure lstRecordsClick(Sender: TObject);
    procedure lstRecordsClickCheck(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnSelectAllClick(Sender: TObject);
    procedure btnSelectNoneClick(Sender: TObject);
    procedure btnAverageClick(Sender: TObject);
    procedure btnFitClick(Sender: TObject);
  private
    FMitFile: TMitFile;
    FSelectedIndex: Integer;
    FOverlaySeries: TList<TFastLineSeries>;
    FFitSeries: TList<TFastLineSeries>;
    FShowAverage: Boolean;
    FAvgLoading: TFastLineSeries;
    FAvgUnloading: TFastLineSeries;
    FStatusBase: string;
    FHighlightTag: Integer;
    FContext: TAnalysisContext;
    FResolved: TMitAnalysis;
    FResolvedValid: Boolean;
    FTicksUserSet: Boolean;
    FTicksUnsaved: Boolean;
    FTicksRestored: Boolean;
    FOrigin: TMitOrigin;
    FLoadedPath: string;
    FLoadedHash: string;

    procedure ClearOverlaySeries;
    procedure GenerateCurve(RecIndex: Integer;
      LoadingSer, UnloadingSer: TFastLineSeries);
    procedure AddFitSeries(RecIndex: Integer);
    procedure UpdateOverlay;
    procedure HighlightIndent(RecIndex: Integer);
    procedure UpdateInfoPanel;
    function CurveIndices: TArray<Integer>;
    function ComputeAverage(out LoadPd, LoadFn, UnloadPd,
      UnloadFn: TArray<Double>): Boolean;
    procedure CalcAndPlotAverage;
    procedure ScaleAxes;
    function BuildStatusText: string;
    procedure SeriesToText(List: TStringList);

    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);

    function CheckedNumbers: TArray<Integer>;
    function CurrentAnalysis: TMitAnalysis;
    function ReportedStiffness(const Rec: TMitRecord): Double;
    function CanApplyShared: Boolean;
    procedure ApplySharedSelection;
    procedure AdoptSelection(const Selection: TMitSelection);
    procedure TicksChangedByUser;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
    procedure SetAnalysisContext(const Context: TAnalysisContext);
    function GetAnalysisSnapshot(const KeyName: string): string;
    function GetAnalysisStatus: string;
  end;

implementation

uses
  ClipBrd, System.JSON, System.Hash, System.DateUtils, unit_ELNPreviewUtils,
  unit_ELNThemeHelper;

{$R *.dfm}

constructor TframeMitFileViewer.Create(AOwner: TComponent);
begin
  inherited;
  FMitFile := TMitFile.Create;
  FOverlaySeries := TList<TFastLineSeries>.Create;
  FFitSeries := TList<TFastLineSeries>.Create;
  FSelectedIndex := -1;
  FShowAverage := False;
  FHighlightTag := -1;

  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;
end;

destructor TframeMitFileViewer.Destroy;
begin
  ClearOverlaySeries;
  FOverlaySeries.Free;
  FFitSeries.Free;
  FMitFile.Free;
  inherited;
end;


procedure TframeMitFileViewer.LoadFromFile(const FileName: string);
var
  I: Integer;
  Hash: string;
begin
  Hash := THashMD5.GetHashStringFromFile(FileName);
  if (FLoadedHash <> '') and SameFileName(FileName, FLoadedPath) and
    (Hash = FLoadedHash) then
  begin
    FContext := Default(TAnalysisContext);
    FResolvedValid := False;
    Exit;
  end;
  FLoadedHash := '';
  FContext := Default(TAnalysisContext);
  FResolvedValid := False;
  FTicksUserSet := False;
  FTicksUnsaved := False;
  FTicksRestored := False;
  FOrigin := Default(TMitOrigin);

  lstRecords.Items.Clear;
  ClearOverlaySeries;
  serLoading.Clear;
  serUnloading.Clear;
  serDrift.Clear;
  lblInfo.Caption := '';
  FSelectedIndex := -1;

  FMitFile.ParseFromFile(FileName);

  for I := 0 to FMitFile.RecordCount - 1 do
    if FMitFile.GetRecord(I).EstimatedDepth then
      lstRecords.Items.Add(Format('Indent %d (estimated depth)', [I + 1]))
    else
      lstRecords.Items.Add(Format('Indent %d', [I + 1]));

  ApplyChartTheme(Chart);

  if FMitFile.RecordCount > 0 then
  begin
    for I := 0 to FMitFile.RecordCount - 1 do
      lstRecords.Checked[I] := True;
    lstRecords.ItemIndex := 0;
    FSelectedIndex := 0;
    UpdateOverlay;
  end;
  FStatusBase := BuildStatusText;
  spStatus.Caption := FStatusBase;
  FLoadedPath := FileName;
  FLoadedHash := Hash;
end;


function TframeMitFileViewer.CheckedNumbers: TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to lstRecords.Count - 1 do
    if lstRecords.Checked[I] then
      Result := Result + [I + 1];
end;

function TframeMitFileViewer.CurrentAnalysis: TMitAnalysis;
begin
  if (FContext.Kind = ackCurrent) and FTicksUserSet then
    Exit(MitAnalysisFromChecked(FMitFile, CheckedNumbers, FOrigin));
  if not FResolvedValid then
  begin
    FResolved := ResolveMitAnalysis(FMitFile, FContext);
    FResolvedValid := True;
  end;
  Result := FResolved;
end;

function TframeMitFileViewer.ReportedStiffness(const Rec: TMitRecord): Double;
begin
  if FMitFile.Source = msInstrument then
    Result := Rec.SInstMNnm
  else
    Result := Rec.S_mNnm;
end;

function TframeMitFileViewer.CanApplyShared: Boolean;
begin
  Result := Assigned(ElnAnalysisSettings) and (FContext.Kind = ackCurrent) and
    (FContext.FileId > 0) and (FContext.FileHash <> '') and
    (FMitFile.RecordCount > 0);
end;

procedure TframeMitFileViewer.ApplySharedSelection;
var
  Service: IElnAnalysisSettings;
  Analysis: TMitAnalysis;
  Selection, Previous: TMitSelection;
  Expected, Current, ApplyId, AppliedAt: string;
  Revision, Attempt: Integer;
begin
  if not (FTicksUserSet and FTicksUnsaved and CanApplyShared) then
    Exit;
  Analysis := MitAnalysisFromChecked(FMitFile, CheckedNumbers, Default(TMitOrigin));
  if not Analysis.Available then
    Exit;
  Service := ElnAnalysisSettings;
  Selection := MitSelectionOf(Analysis, FContext.FileHash);
  Expected := FContext.SharedSelection;
  for Attempt := 1 to 2 do
  begin
    if TryParseMitSelection(Expected, Previous) and Previous.Origin.Present then
      Revision := Previous.Origin.Revision + 1
    else
      Revision := 1;
    ApplyId := TGUID.NewGuid.ToString;
    AppliedAt := FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"Z"',
      TTimeZone.Local.ToUniversalTime(Now), TFormatSettings.Invariant);
    case Service.Apply(FContext.FileId, MitReaderId, Expected,
      MitSelectionToJson(Selection, Revision, Service.CurrentUserId, ApplyId,
        AppliedAt), Current) of
      aarApplied:
        begin
          FContext.SharedSelection := Current;
          FResolvedValid := False;
          FOrigin.Present := True;
          FOrigin.Revision := Revision;
          FOrigin.ApplyId := ApplyId;
          FTicksUnsaved := False;
          Exit;
        end;
      aarConflict:
        Expected := Current;
    else
      Break;
    end;
  end;
  FOrigin := Default(TMitOrigin);
  spStatus.Caption := FStatusBase + '  |  Selection was not saved for this file';
end;

procedure TframeMitFileViewer.AdoptSelection(const Selection: TMitSelection);
var
  I, N: Integer;
begin
  for I := 0 to lstRecords.Count - 1 do
    lstRecords.Checked[I] := Selection.Mode = msmAutomatic;
  if Selection.Mode = msmIndents then
    for N in Selection.Checked do
      lstRecords.Checked[N - 1] := True;
  FOrigin := Selection.Origin;
  FTicksRestored := False;
  UpdateOverlay;
end;

procedure TframeMitFileViewer.TicksChangedByUser;
begin
  FTicksUserSet := True;
  FTicksUnsaved := True;
  FTicksRestored := False;
  FResolvedValid := False;
  UpdateOverlay;
  ApplySharedSelection;
end;

procedure TframeMitFileViewer.SetAnalysisContext(const Context: TAnalysisContext);
var
  Selection: TMitSelection;
begin
  FContext := Context;
  FResolvedValid := False;
  if (Context.Kind <> ackCurrent) or (FMitFile.RecordCount = 0) then
    Exit;
  if FTicksUserSet then
  begin
    ApplySharedSelection;
    Exit;
  end;
  if Context.SharedSelection <> '' then
  begin
    if (ResolveMitAnalysis(FMitFile, Context).Status = '') and
      TryParseMitSelection(Context.SharedSelection, Selection) then
      AdoptSelection(Selection);
    Exit;
  end;
  if FTicksRestored then
    FTicksUserSet := True;
end;

function TframeMitFileViewer.GetAnalysisSnapshot(const KeyName: string): string;
var
  Analysis: TMitAnalysis;
begin
  Result := '';
  Analysis := CurrentAnalysis;
  if Analysis.Available and MitKeyHasSnapshot(KeyName) and
    ((KeyName <> MitKeyModulus) or Analysis.HasModulus) then
    Result := BuildMitSnapshot(FContext, KeyName, Analysis);
end;

function TframeMitFileViewer.GetAnalysisStatus: string;
begin
  Result := CurrentAnalysis.Status;
end;


procedure TframeMitFileViewer.GenerateCurve(RecIndex: Integer;
  LoadingSer, UnloadingSer: TFastLineSeries);
var
  Rec: TMitRecord;
  I: Integer;
begin
  Rec := FMitFile.GetRecord(RecIndex);
  LoadingSer.Clear;
  UnloadingSer.Clear;
  if not Rec.HasCurve then
    Exit;
  for I := 0 to Rec.PeakIndex do
    LoadingSer.AddXY(Rec.Curve[I].DepthNm, Rec.Curve[I].ForceMN);
  for I := Rec.PeakIndex to High(Rec.Curve) do
    UnloadingSer.AddXY(Rec.Curve[I].DepthNm, Rec.Curve[I].ForceMN);
end;

procedure TframeMitFileViewer.AddFitSeries(RecIndex: Integer);
const
  FitPoints = 100;
var
  Rec: TMitRecord;
  Ser: TFastLineSeries;
  I: Integer;
  H: Double;
begin
  Rec := FMitFile.GetRecord(RecIndex);
  if Rec.EstimatedDepth or (Rec.HmaxNm <= Rec.HfNm) or (Rec.MExp <= 0) then
    Exit;
  Ser := TFastLineSeries.Create(Chart);
  Ser.Title := Format('Indent %d instrument unloading fit', [RecIndex + 1]);
  Ser.XValues.Order := loNone;
  Ser.YValues.Order := loNone;
  Chart.AddSeries(Ser);
  Ser.LinePen.Color := clRed;
  Ser.LinePen.Style := psDash;
  Ser.LinePen.Width := 1;
  FFitSeries.Add(Ser);
  for I := 0 to FitPoints - 1 do
  begin
    H := Rec.HfNm + (Rec.HmaxNm - Rec.HfNm) * I / (FitPoints - 1);
    Ser.AddXY(H, Rec.FmaxMN *
      Power((H - Rec.HfNm) / (Rec.HmaxNm - Rec.HfNm), Rec.MExp));
  end;
end;


procedure TframeMitFileViewer.ClearOverlaySeries;
var
  Ser: TFastLineSeries;
begin
  for Ser in FOverlaySeries do
  begin
    Chart.RemoveSeries(Ser);
    Ser.Free;
  end;
  FOverlaySeries.Clear;
  FHighlightTag := -1;

  for Ser in FFitSeries do
  begin
    Chart.RemoveSeries(Ser);
    Ser.Free;
  end;
  FFitSeries.Clear;

  if Assigned(FAvgLoading) then
  begin
    Chart.RemoveSeries(FAvgLoading);
    FreeAndNil(FAvgLoading);
  end;
  if Assigned(FAvgUnloading) then
  begin
    Chart.RemoveSeries(FAvgUnloading);
    FreeAndNil(FAvgUnloading);
  end;
end;

procedure TframeMitFileViewer.UpdateOverlay;
var
  I: Integer;
  SerLoad, SerUnload: TFastLineSeries;
begin
  Chart.AutoRepaint := False;
  try
    ClearOverlaySeries;

    serLoading.Clear;
    serUnloading.Clear;
    serDrift.Clear;

    for I := 0 to lstRecords.Count - 1 do
    begin
      if not lstRecords.Checked[I] then
        Continue;

      SerLoad := TFastLineSeries.Create(Chart);
      SerLoad.Tag := I;
      SerLoad.Title := Format('Indent %d', [I + 1]);
      SerLoad.XValues.Order := loNone;
      SerLoad.YValues.Order := loNone;
      Chart.AddSeries(SerLoad);
      SerLoad.LinePen.Color := clBlue;
      SerLoad.LinePen.Width := 1;
      FOverlaySeries.Add(SerLoad);

      SerUnload := TFastLineSeries.Create(Chart);
      SerUnload.Tag := I;
      SerUnload.Title := Format('Indent %d unload', [I + 1]);
      SerUnload.XValues.Order := loNone;
      SerUnload.YValues.Order := loNone;
      Chart.AddSeries(SerUnload);
      SerUnload.LinePen.Color := clBlue;
      SerUnload.LinePen.Width := 1;
      FOverlaySeries.Add(SerUnload);

      GenerateCurve(I, SerLoad, SerUnload);
      if btnFit.Down then
        AddFitSeries(I);
    end;

    FShowAverage := btnAverage.Down;
    if FShowAverage then
      CalcAndPlotAverage;

    ScaleAxes;

    UpdateInfoPanel;
    FStatusBase := BuildStatusText;
    spStatus.Caption := FStatusBase;
  finally
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;
end;

procedure TframeMitFileViewer.HighlightIndent(RecIndex: Integer);
begin
  // No visual highlight — all indents use uniform blue 1px.
  // Method kept for info panel update on click.
end;


procedure AccumulateBranch(const Rec: TMitRecord; Unloading: Boolean;
  const Grid: TArray<Double>; var Sum: TArray<Double>; var Cnt: TArray<Integer>);
var
  I, Dir, J: Integer;
  PrevD, PrevF, D, F: Double;
begin
  if Unloading then
  begin
    I := High(Rec.Curve);
    Dir := -1;
  end
  else
  begin
    I := 0;
    Dir := 1;
  end;
  PrevD := Rec.Curve[I].DepthNm;
  PrevF := Rec.Curve[I].ForceMN;
  J := 0;
  while (J < Length(Grid)) and (Grid[J] < PrevD) do
    Inc(J);
  while I <> Rec.PeakIndex do
  begin
    Inc(I, Dir);
    D := Rec.Curve[I].DepthNm;
    if D <= PrevD then
      Continue;
    F := Rec.Curve[I].ForceMN;
    while (J < Length(Grid)) and (Grid[J] <= D) do
    begin
      Sum[J] := Sum[J] + PrevF + (F - PrevF) * (Grid[J] - PrevD) / (D - PrevD);
      Inc(Cnt[J]);
      Inc(J);
    end;
    PrevD := D;
    PrevF := F;
  end;
end;

function TframeMitFileViewer.CurveIndices: TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to lstRecords.Count - 1 do
    if lstRecords.Checked[I] and FMitFile.GetRecord(I).HasCurve then
      Result := Result + [I];
end;

function TframeMitFileViewer.ComputeAverage(out LoadPd, LoadFn, UnloadPd,
  UnloadFn: TArray<Double>): Boolean;

  procedure Branch(const Indices: TArray<Integer>; Unloading: Boolean;
    out Pd, Fn: TArray<Double>);
  var
    I, J: Integer;
    Rec: TMitRecord;
    Lo, Hi, Start: Double;
    Grid, Sum: TArray<Double>;
    Cnt: TArray<Integer>;
  begin
    Pd := nil;
    Fn := nil;
    Lo := -MaxDouble;
    Hi := MaxDouble;
    for I in Indices do
    begin
      Rec := FMitFile.GetRecord(I);
      if Unloading then
        Start := Rec.Curve[High(Rec.Curve)].DepthNm
      else
        Start := Rec.Curve[0].DepthNm;
      Lo := Max(Lo, Start);
      Hi := Min(Hi, Rec.Curve[Rec.PeakIndex].DepthNm);
    end;
    if Hi <= Lo then
      Exit;
    SetLength(Grid, GRID_POINTS);
    for J := 0 to GRID_POINTS - 2 do
      Grid[J] := Lo + (Hi - Lo) * J / (GRID_POINTS - 1);
    Grid[GRID_POINTS - 1] := Hi;
    SetLength(Sum, GRID_POINTS);
    SetLength(Cnt, GRID_POINTS);
    for I in Indices do
      AccumulateBranch(FMitFile.GetRecord(I), Unloading, Grid, Sum, Cnt);
    for J := 0 to GRID_POINTS - 1 do
      if Cnt[J] = Length(Indices) then
      begin
        Pd := Pd + [Grid[J]];
        Fn := Fn + [Sum[J] / Cnt[J]];
      end;
  end;

var
  Indices: TArray<Integer>;
begin
  LoadPd := nil;
  LoadFn := nil;
  UnloadPd := nil;
  UnloadFn := nil;
  Indices := CurveIndices;
  if Indices = nil then
    Exit(False);
  Branch(Indices, False, LoadPd, LoadFn);
  Branch(Indices, True, UnloadPd, UnloadFn);
  Result := (LoadPd <> nil) or (UnloadPd <> nil);
end;

procedure TframeMitFileViewer.CalcAndPlotAverage;
var
  LoadPd, LoadFn, UnloadPd, UnloadFn: TArray<Double>;
  J: Integer;
begin
  if not ComputeAverage(LoadPd, LoadFn, UnloadPd, UnloadFn) then
    Exit;

  FAvgLoading := TFastLineSeries.Create(Chart);
  FAvgLoading.Title := 'Average loading';
  FAvgLoading.XValues.Order := loNone;
  FAvgLoading.YValues.Order := loNone;
  Chart.AddSeries(FAvgLoading);
  FAvgLoading.LinePen.Color := clMaroon;
  FAvgLoading.LinePen.Width := 3;

  FAvgUnloading := TFastLineSeries.Create(Chart);
  FAvgUnloading.Title := 'Average unloading';
  FAvgUnloading.XValues.Order := loNone;
  FAvgUnloading.YValues.Order := loNone;
  Chart.AddSeries(FAvgUnloading);
  FAvgUnloading.LinePen.Color := clMaroon;
  FAvgUnloading.LinePen.Width := 3;

  for J := 0 to High(LoadPd) do
    FAvgLoading.AddXY(LoadPd[J], LoadFn[J]);
  for J := 0 to High(UnloadPd) do
    FAvgUnloading.AddXY(UnloadPd[J], UnloadFn[J]);
end;

procedure TframeMitFileViewer.ScaleAxes;
var
  Ser: TFastLineSeries;
  J: Integer;
  MinX, MaxX, MaxY, Pad: Double;
  Measured: TList<TFastLineSeries>;
begin
  MinX := 0;
  MaxX := 0;
  MaxY := 0;

  Measured := TList<TFastLineSeries>.Create;
  try
    Measured.AddRange(FOverlaySeries);
    if Assigned(FAvgLoading) then
      Measured.Add(FAvgLoading);
    if Assigned(FAvgUnloading) then
      Measured.Add(FAvgUnloading);
    for Ser in Measured do
      for J := 0 to Ser.Count - 1 do
      begin
        MinX := Min(MinX, Ser.XValue[J]);
        MaxX := Max(MaxX, Ser.XValue[J]);
        MaxY := Max(MaxY, Ser.YValue[J]);
      end;
  finally
    Measured.Free;
  end;

  if (MaxX > 0) and (MaxY > 0) then
  begin
    Pad := 0.1 * (MaxX - MinX);
    Chart.BottomAxis.Automatic := False;
    if MinX < 0 then
      Chart.BottomAxis.SetMinMax(MinX - Pad, MaxX + Pad)
    else
      Chart.BottomAxis.SetMinMax(0, MaxX + Pad);
    Chart.LeftAxis.Automatic := False;
    Chart.LeftAxis.SetMinMax(0, MaxY * 1.1);
  end;
end;


procedure TframeMitFileViewer.UpdateInfoPanel;
var
  Rec: TMitRecord;
  Item: TMitIndent;
  Avg: TMitAnalysis;
  I: Integer;
  Text: string;
begin
  Avg := MitAnalysisFromChecked(FMitFile, CheckedNumbers, Default(TMitOrigin));
  if Length(Avg.Used) > 1 then
  begin
    Text := Format(
      'Average (%d usable indents; estimates excluded)'#13#10#13#10 +
      'H: %.1f +/- %.1f GPa'#13#10,
      [Length(Avg.Used), Avg.Hardness.Mean, Avg.Hardness.Std]);
    if Avg.HasModulus then
      Text := Text + Format('E: %.1f +/- %.1f GPa'#13#10,
        [Avg.Modulus.Mean, Avg.Modulus.Std]);
    lblInfo.Caption := Text + Format(
      'Er: %.1f +/- %.1f GPa'#13#10 +
      'hc: %.1f +/- %.1f nm'#13#10 +
      'Fmax: %.3f +/- %.3f mN',
      [Avg.ReducedModulus.Mean, Avg.ReducedModulus.Std,
       Avg.ContactDepth.Mean, Avg.ContactDepth.Std,
       Avg.MaxForce.Mean, Avg.MaxForce.Std]);
  end
  else if (FSelectedIndex >= 0) and (FSelectedIndex < FMitFile.RecordCount) then
  begin
    Rec := FMitFile.GetRecord(FSelectedIndex);
    Item := FMitFile.Indent(FSelectedIndex);

    var LoadRate: Double := 0;
    var TestTime: Double := 0;
    var Temp: Double := 0;
    var TempCount: Integer := 0;

    if Rec.SampleCount > 1 then
    begin
      TestTime := Rec.Time(Rec.SampleCount - 1) - Rec.Time(0);

      for I := 0 to Rec.SampleCount - 1 do
      begin
        var T: Single := Rec.Temperature(I);
        if (T > 0) and (T < 1000) then
        begin
          Temp := Temp + T;
          Inc(TempCount);
        end;
      end;

      if TempCount > 0 then
        Temp := Temp / TempCount;

      if Rec.HasCurve then
      begin
        var LoadTime: Double := Rec.Time(Rec.ContactRow + Rec.PeakIndex) -
          Rec.Time(Rec.ContactRow);
        if LoadTime > 0 then
          LoadRate := Rec.Curve[Rec.PeakIndex].ForceMN / LoadTime;
      end;
    end;

    if Rec.EstimatedDepth then
      lblInfo.Caption := Format(
        '%s'#13#10#13#10 +
        'Estimated depth (not a measurement)'#13#10 +
        'hmax estimate: %.1f nm'#13#10 +
        'hc estimate: %.1f nm'#13#10 +
        'Fmax: %.3f mN'#13#10 +
        'Hardness and modulus unavailable',
        [Rec.Description, Rec.HmaxNm, Rec.HcNm, Rec.FmaxMN])
    else
    begin
      Text := Format('%s'#13#10#13#10 + 'Indenter: %s'#13#10 + 'Material: %s'#13#10#13#10,
        [Rec.Description, Rec.IndenterType, Rec.Material]);
      if Item.Usable then
      begin
        Text := Text + Format('H: %.1f GPa'#13#10, [Item.H_GPa]);
        if Item.HasE then
          Text := Text + Format('E: %.1f GPa'#13#10, [Item.E_GPa]);
        Text := Text + Format('Er: %.1f GPa'#13#10, [Item.Er_GPa]);
      end
      else
        Text := Text + 'Not used: the unloading fit is not physical'#13#10;
      lblInfo.Caption := Text + Format(
        'S: %.4f mN/nm'#13#10 +
        'hmax: %.1f nm'#13#10 +
        'hc: %.1f nm'#13#10 +
        'Fmax: %.3f mN'#13#10 +
        'm: %.3f',
        [ReportedStiffness(Rec), Rec.HmaxNm, Rec.HcNm, Rec.FmaxMN, Rec.MExp]);
    end;

    if LoadRate > 0 then
      lblInfo.Caption := lblInfo.Caption + Format(#13#10#13#10'Loading rate: %.3f mN/s', [LoadRate]);
    if TestTime > 0 then
      lblInfo.Caption := lblInfo.Caption + Format(#13#10'Test time: %.1f s', [TestTime]);
    if Temp > 0 then
      lblInfo.Caption := lblInfo.Caption + Format(#13#10'Temperature: %.1f '#$B0'C', [Temp]);
    if Rec.FrameCompliance > 0 then
      lblInfo.Caption := lblInfo.Caption + Format(#13#10'Frame compliance: %.4f nm/mN',
        [Rec.FrameCompliance * 1e6]);
  end
  else
    lblInfo.Caption := 'No indents selected';
end;


function TframeMitFileViewer.BuildStatusText: string;
begin
  Result := Format('%s  |  v%d  |  %d records', [
    ExtractFileName(FMitFile.FileName),
    FMitFile.Version,
    FMitFile.RecordCount]);
end;


procedure TframeMitFileViewer.ChartMouseWheel(Sender: TObject;
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

procedure TframeMitFileViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  PdVal, FnVal: Double;
  I, NewTag: Integer;
  Ser: TFastLineSeries;
begin
  PdVal := Chart.BottomAxis.CalcPosPoint(X);
  FnVal := Chart.LeftAxis.CalcPosPoint(Y);

  NewTag := -1;
  for I := 0 to FOverlaySeries.Count - 1 do
  begin
    Ser := FOverlaySeries[I];
    if Ser.Clicked(X, Y) >= 0 then
    begin
      NewTag := Ser.Tag;
      Break;
    end;
  end;

  if NewTag <> FHighlightTag then
  begin
    FHighlightTag := NewTag;
    Chart.AutoRepaint := False;
    try
      for I := 0 to FOverlaySeries.Count - 1 do
      begin
        Ser := FOverlaySeries[I];
        if Ser.Tag = FHighlightTag then
        begin
          Ser.LinePen.Color := clNavy;
          Ser.LinePen.Width := 3;
        end
        else
        begin
          Ser.LinePen.Color := clBlue;
          Ser.LinePen.Width := 1;
        end;
      end;
    finally
      Chart.AutoRepaint := True;
      Chart.Repaint;
    end;
  end;

  if FHighlightTag >= 0 then
    spStatus.Caption := Format('%s  |  Indent %d  |  %.1f nm, %.4f mN',
      [FStatusBase, FHighlightTag + 1, PdVal, FnVal])
  else
    spStatus.Caption := Format('%s  |  Cursor: %.1f nm, %.4f mN',
      [FStatusBase, PdVal, FnVal]);
end;

procedure TframeMitFileViewer.ChartDblClick(Sender: TObject);
begin
  if FHighlightTag >= 0 then
  begin
    lstRecords.Checked[FHighlightTag] := not lstRecords.Checked[FHighlightTag];
    TicksChangedByUser;
  end
  else
    ScaleAxes;
end;


procedure TframeMitFileViewer.lstRecordsClick(Sender: TObject);
begin
  if lstRecords.ItemIndex >= 0 then
  begin
    FSelectedIndex := lstRecords.ItemIndex;
    HighlightIndent(FSelectedIndex);
    UpdateInfoPanel;
    FStatusBase := BuildStatusText;
    spStatus.Caption := FStatusBase;
    Chart.Repaint;
  end;
end;

procedure TframeMitFileViewer.lstRecordsClickCheck(Sender: TObject);
begin
  TicksChangedByUser;
end;

procedure TframeMitFileViewer.btnSelectAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to lstRecords.Count - 1 do
    lstRecords.Checked[I] := True;
  TicksChangedByUser;
end;

procedure TframeMitFileViewer.btnSelectNoneClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to lstRecords.Count - 1 do
    lstRecords.Checked[I] := False;
  TicksChangedByUser;
end;

procedure TframeMitFileViewer.btnAverageClick(Sender: TObject);
begin
  UpdateOverlay;
end;

procedure TframeMitFileViewer.btnFitClick(Sender: TObject);
begin
  UpdateOverlay;
end;


procedure TframeMitFileViewer.SeriesToText(List: TStringList);
var
  I, J, K, CheckedCount, Rows: Integer;
  CheckedIndices, Curves: TArray<Integer>;
  Rec: TMitRecord;
  Header, Line: string;
  ColX, ColY: TArray<TArray<Double>>;
  LoadPd, LoadFn, UnloadPd, UnloadFn, X, Y: TArray<Double>;
begin
  CheckedCount := 0;
  SetLength(CheckedIndices, lstRecords.Count);
  for I := 0 to lstRecords.Count - 1 do
    if lstRecords.Checked[I] and FMitFile.Indent(I).Usable then
    begin
      CheckedIndices[CheckedCount] := I;
      Inc(CheckedCount);
    end;
  SetLength(CheckedIndices, CheckedCount);
  Curves := CurveIndices;

  if (CheckedCount = 0) and (Curves = nil) then
    Exit;

  List.Add('# MIT Nanoindentation Export');
  List.Add(Format('# File: %s', [ExtractFileName(FMitFile.FileName)]));
  List.Add('# Curves: measured Pd and Fn from the contact point stored in the file.');
  if (Curves <> nil) and (FMitFile.GetRecord(Curves[0]).FrameCompliance > 0) then
    List.Add(Format('# Frame compliance subtracted from Pd: %.4f nm/mN',
      [FMitFile.GetRecord(Curves[0]).FrameCompliance * 1e6]));

  if CheckedCount > 0 then
  begin
    List.Add(Format('# Indents with results: %d', [CheckedCount]));
    List.Add('#');
    List.Add('# Indent' + #9 + 'Fmax (mN)' + #9 + 'hmax (nm)' + #9 +
             'hc (nm)' + #9 + 'H (GPa)' + #9 + 'Er (GPa)' + #9 +
             'S (mN/nm)' + #9 + 'm');

    for I := 0 to CheckedCount - 1 do
    begin
      Rec := FMitFile.GetRecord(CheckedIndices[I]);
      List.Add(Format('# %d' + #9 + '%.3f' + #9 + '%.1f' + #9 +
                      '%.1f' + #9 + '%.1f' + #9 + '%.1f' + #9 +
                      '%.4f' + #9 + '%.3f',
        [CheckedIndices[I] + 1, Rec.FmaxMN, Rec.HmaxNm,
         Rec.HcNm, FMitFile.Indent(CheckedIndices[I]).H_GPa,
         FMitFile.Indent(CheckedIndices[I]).Er_GPa, ReportedStiffness(Rec), Rec.MExp]));
    end;

    if FShowAverage then
    begin
      var SumH: Double := 0;
      var SumEr: Double := 0;
      var SumHc: Double := 0;
      var SumFmax: Double := 0;
      var SumHmax: Double := 0;
      for I := 0 to CheckedCount - 1 do
      begin
        Rec := FMitFile.GetRecord(CheckedIndices[I]);
        SumH := SumH + FMitFile.Indent(CheckedIndices[I]).H_GPa;
        SumEr := SumEr + FMitFile.Indent(CheckedIndices[I]).Er_GPa;
        SumHc := SumHc + Rec.HcNm;
        SumFmax := SumFmax + Rec.FmaxMN;
        SumHmax := SumHmax + Rec.HmaxNm;
      end;
      List.Add(Format('# Avg' + #9 + '%.3f' + #9 + '%.1f' + #9 +
                      '%.1f' + #9 + '%.1f' + #9 + '%.1f',
        [SumFmax / CheckedCount, SumHmax / CheckedCount,
         SumHc / CheckedCount, SumH / CheckedCount, SumEr / CheckedCount]));
    end;
  end;

  List.Add('#');
  List.Add('');

  if Curves = nil then
    Exit;

  Header := '';
  for I in Curves do
  begin
    Rec := FMitFile.GetRecord(I);
    X := nil;
    Y := nil;
    SetLength(X, Length(Rec.Curve));
    SetLength(Y, Length(Rec.Curve));
    for J := 0 to High(Rec.Curve) do
    begin
      X[J] := Rec.Curve[J].DepthNm;
      Y[J] := Rec.Curve[J].ForceMN;
    end;
    ColX := ColX + [X];
    ColY := ColY + [Y];
    Header := Header + Format('Pd_%d (nm)'#9'Fn_%d (mN)'#9, [I + 1, I + 1]);
  end;
  if FShowAverage and ComputeAverage(LoadPd, LoadFn, UnloadPd, UnloadFn) then
  begin
    ColX := ColX + [LoadPd, UnloadPd];
    ColY := ColY + [LoadFn, UnloadFn];
    Header := Header + 'Pd_avg_load (nm)'#9'Fn_avg_load (mN)'#9 +
      'Pd_avg_unload (nm)'#9'Fn_avg_unload (mN)'#9;
  end;
  List.Add(Header.TrimRight([#9]));

  Rows := 0;
  for K := 0 to High(ColX) do
    Rows := Max(Rows, Length(ColX[K]));
  for J := 0 to Rows - 1 do
  begin
    Line := '';
    for K := 0 to High(ColX) do
      if J < Length(ColX[K]) then
        Line := Line + FloatToStrF(ColX[K][J], ffFixed, 12, 4) + #9 +
          FloatToStrF(ColY[K][J], ffFixed, 12, 6) + #9
      else
        Line := Line + #9#9;
    List.Add(Line.TrimRight([#9]));
  end;
end;

procedure TframeMitFileViewer.btnCopyClick(Sender: TObject);
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    SeriesToText(List);
    if List.Count > 0 then
      ClipBoard.AsText := List.Text;
  finally
    List.Free;
  end;
end;

procedure TframeMitFileViewer.btnSaveClick(Sender: TObject);
var
  List: TStringList;
begin
  if dlgSave.Execute then
  begin
    List := TStringList.Create;
    try
      SeriesToText(List);
      List.SaveToFile(dlgSave.FileName);
    finally
      List.Free;
    end;
  end;
end;


function TframeMitFileViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  HasData: Boolean;
  I: Integer;
begin
  Result := nil;

  HasData := False;
  for I := 0 to FOverlaySeries.Count - 1 do
    if FOverlaySeries[I].Count > 0 then
    begin
      HasData := True;
      Break;
    end;
  if not HasData and (serLoading.Count = 0) then
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

function TframeMitFileViewer.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := MitKeyValues(CurrentAnalysis);
end;

function TframeMitFileViewer.GetDetailedInfo: string;
var
  J, JRec, JEstimated: TJSONObject;
  JArr: TJSONArray;
  I: Integer;
  Rec: TMitRecord;
  Item: TMitIndent;
begin
  Result := '';
  if FMitFile.RecordCount = 0 then
    Exit;

  J := TJSONObject.Create;
  try
    J.AddPair('fileName', ExtractFileName(FMitFile.FileName));
    J.AddPair('recordCount', TJSONNumber.Create(FMitFile.RecordCount));
    if FMitFile.Source = msInstrument then
      J.AddPair('source', 'instrument')
    else
      J.AddPair('source', 'computed');
    J.AddPair('usableCount', TJSONNumber.Create(FMitFile.UsableCount));
    J.AddPair('excludedCount', TJSONNumber.Create(FMitFile.ExcludedCount));

    JArr := TJSONArray.Create;
    for I := 0 to FMitFile.RecordCount - 1 do
    begin
      Rec := FMitFile.GetRecord(I);
      Item := FMitFile.Indent(I);
      JRec := TJSONObject.Create;
      JRec.AddPair('index', TJSONNumber.Create(I));
      JRec.AddPair('description', Rec.Description);
      JRec.AddPair('indenterType', Rec.IndenterType);
      JRec.AddPair('material', Rec.Material);
      JRec.AddPair('dataPointCount', TJSONNumber.Create(Rec.DataPointCount));
      JRec.AddPair('estimatedDepth', TJSONBool.Create(Rec.EstimatedDepth));
      JRec.AddPair('FmaxMN', JNum(Rec.FmaxMN));
      if Rec.EstimatedDepth then
      begin
        JRec.AddPair('provenance', 'Depth estimated; hardness and modulus are not measured');
        JEstimated := TJSONObject.Create;
        JEstimated.AddPair('HmaxNm', JNum(Rec.HmaxNm));
        JEstimated.AddPair('HcNm', JNum(Rec.HcNm));
        JRec.AddPair('estimated', JEstimated);
      end
      else
      begin
        JRec.AddPair('usable', TJSONBool.Create(Item.Usable));
        if Item.Usable then
        begin
          JRec.AddPair('H_GPa', JNum(Item.H_GPa));
          if Item.HasE then
            JRec.AddPair('E_GPa', JNum(Item.E_GPa));
          JRec.AddPair('Er_GPa', JNum(Item.Er_GPa));
        end;
        JRec.AddPair('HcNm', JNum(Rec.HcNm));
        JRec.AddPair('HmaxNm', JNum(Rec.HmaxNm));
        JRec.AddPair('HfNm', JNum(Rec.HfNm));
        JRec.AddPair('S_mNnm', JNum(ReportedStiffness(Rec)));
        JRec.AddPair('A_nm2', JNum(Rec.A_nm2));
      end;
      JArr.AddElement(JRec);
    end;
    J.AddPair('records', JArr);

    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;


function TframeMitFileViewer.SaveState: string;
var
  JObj: TJSONObject;
  JArr: TJSONArray;
  I: Integer;
begin
  Result := '';
  if lstRecords.Count = 0 then
    Exit;

  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(1));

    JArr := TJSONArray.Create;
    for I := 0 to lstRecords.Count - 1 do
      if lstRecords.Checked[I] then
        JArr.Add(I);
    JObj.AddPair('checked', JArr);

    JObj.AddPair('average', TJSONBool.Create(btnAverage.Down));
    JObj.AddPair('fit', TJSONBool.Create(btnFit.Down));

    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeMitFileViewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  JArr: TJSONArray;
  JVal: TJSONValue;
  I, Idx: Integer;
begin
  if lstRecords.Count = 0 then
    Exit;

  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then
    Exit;

  try
    // Restore checked indices (empty array = keep default all-checked)
    JArr := JObj.GetValue('checked') as TJSONArray;
    if Assigned(JArr) and (JArr.Count > 0) then
    begin
      for I := 0 to lstRecords.Count - 1 do
        lstRecords.Checked[I] := False;
      for JVal in JArr do
      begin
        Idx := (JVal as TJSONNumber).AsInt;
        if (Idx >= 0) and (Idx < lstRecords.Count) then
          lstRecords.Checked[Idx] := True;
      end;
      FTicksRestored := MitAnalysisFromChecked(FMitFile, CheckedNumbers,
        Default(TMitOrigin)).Mode = msmIndents;
    end;

    JVal := JObj.GetValue('average');
    if Assigned(JVal) and (JVal is TJSONBool) then
      btnAverage.Down := (JVal as TJSONBool).AsBoolean;

    JVal := JObj.GetValue('fit');
    if Assigned(JVal) and (JVal is TJSONBool) then
      btnFit.Down := (JVal as TJSONBool).AsBoolean;

    FShowAverage := btnAverage.Down;

    UpdateOverlay;
  finally
    JObj.Free;
  end;
end;

end.
