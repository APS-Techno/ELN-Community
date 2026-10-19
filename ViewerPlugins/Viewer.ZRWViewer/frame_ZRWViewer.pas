unit frame_ZRWViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Buttons,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_ZRWData, unit_ZRWPlateau,
  unit_ZRWAnalysis;

type

  TframeZRWViewer = class(TFrame)
    Status: TRzStatusBar;
    dlgSave: TSaveDialog;
    pnlSelection: TPanel;
    lblMode: TLabel;
    lblStart: TLabel;
    lblEnd: TLabel;
    lblStats: TLabel;
    lblWarnings: TLabel;
    btnAutomatic: TSpeedButton;
    btnManual: TSpeedButton;
    edStart: TEdit;
    edEnd: TEdit;
    chkThroughEnd: TCheckBox;
    btnApply: TButton;
    btnReload: TButton;
    Chart: TChart;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    SeriesBand: TAreaSeries;
    Series1: TFastLineSeries;
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure ModeButtonClick(Sender: TObject);
    procedure edBoundChange(Sender: TObject);
    procedure chkThroughEndClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure btnReloadClick(Sender: TObject);
  private
    FCurve: TZRWCurve;
    FStatusBase: string;
    FLoadError: string;
    FContext: TAnalysisContext;
    FAnalysis: TZRWAnalysis;
    FAnalysisResolved: Boolean;
    FDetected: TZRWInterval;
    FDetectedFound: Boolean;
    FShared: TZRWSelection;
    FSharedParsed: Boolean;
    FConflictPending: Boolean;
    FConflictJson: string;
    FMessage: string;
    FUpdating: Boolean;
    FDraftValid: Boolean;
    FDraftInterval: TZRWInterval;
    FDraftStats: TZRWStats;
    FDraftWarnings: TZRWWarnings;
    FDraftError: string;
    FDraftTouched: Boolean;
    function Analysis: TZRWAnalysis;
    function LastCycle: Double;
    function SharedStale: Boolean;
    function DraftMode: TZRWSelectionMode;
    function DraftMatchesShared: Boolean;
    function CanApply: Boolean;
    procedure ParseShared;
    procedure SetModeButton(Manual: Boolean);
    function StaleUntouched: Boolean;
    procedure InitDraft;
    procedure EvaluateDraft;
    procedure DraftEdited;
    procedure RefreshSelectionUi;
    procedure UpdateBand;
    procedure SeriesToText(List: TStringList);
    procedure UpdateStatus;
    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromFile(const FileName: string);
    procedure SetAnalysisContext(const Context: TAnalysisContext);
    procedure SetDraftMode(Mode: TZRWSelectionMode);
    procedure SetDraftBounds(Start, Stop: Double; ThroughEnd: Boolean);
    procedure ApplySelection;
    procedure ReloadSelection;
    function GetAnalysisSnapshot(const KeyName: string): string;
    function GetAnalysisStatus: string;
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  ClipBrd, System.Generics.Collections, System.JSON, System.Math,
  System.DateUtils, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

constructor TframeZRWViewer.Create(AOwner: TComponent);
begin
  inherited;
  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;
  InitDraft;
end;

procedure TframeZRWViewer.UpdateStatus;
begin
  FStatusBase := Format('Stroke: %s mm  |  Speed: %s mm/s  |  Load: %s  |  Cycles: %s  |  Points: %d',
    [FCurve.Header.Stroke, FCurve.Header.Speed, FCurve.Header.Load, FCurve.Header.Cycles, Series1.Count]);
  Status.SimpleCaption := FStatusBase;
end;

procedure TframeZRWViewer.LoadFromFile(const FileName: string);
var
  Sample: TZRWSample;
begin
  FCurve := Default(TZRWCurve);
  FContext := Default(TAnalysisContext);
  FAnalysisResolved := False;
  FDetectedFound := False;
  FDetected := Default(TZRWInterval);
  FConflictPending := False;
  FConflictJson := '';
  FMessage := '';
  FLoadError := '';
  ParseShared;
  InitDraft;
  Series1.Clear;
  Chart.AutoRepaint := False;
  Series1.BeginUpdate;
  try
    try
      FCurve := LoadZRWFile(FileName);
      for Sample in FCurve.Samples do
        Series1.AddXY(Sample.Cycle, Sample.COF);
      FDetectedFound := DetectPlateau(FCurve, FDetected) = zdrFound;
    except
      on E: Exception do
      begin
        FCurve := Default(TZRWCurve);
        FDetectedFound := False;
        FDetected := Default(TZRWInterval);
        FLoadError := E.Message;
        Series1.Clear;
        FStatusBase := FLoadError;
        Status.SimpleCaption := FStatusBase;
        InitDraft;
        raise;
      end;
    end;
  finally
    Series1.EndUpdate;
    SeriesBand.ParentChart := nil;
    try
      ApplyChartTheme(Chart);
    finally
      SeriesBand.ParentChart := Chart;
      Chart.ExchangeSeries(SeriesBand, Series1);
    end;
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;

  UpdateStatus;
  InitDraft;
end;

function TframeZRWViewer.Analysis: TZRWAnalysis;
begin
  if not FAnalysisResolved then
  begin
    FAnalysis := ResolveZRWAnalysis(FCurve, FContext);
    FAnalysisResolved := True;
  end;
  Result := FAnalysis;
end;

procedure TframeZRWViewer.SetAnalysisContext(const Context: TAnalysisContext);
begin
  FContext := Context;
  FAnalysisResolved := False;
  FConflictPending := False;
  FConflictJson := '';
  FMessage := '';
  ParseShared;
  InitDraft;
end;

function TryParseBound(const Text: string; out Value: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(Text), ',', '.', []), Value,
    TFormatSettings.Invariant) and not IsNan(Value) and not IsInfinite(Value);
end;

function TframeZRWViewer.LastCycle: Double;
begin
  if Length(FCurve.Samples) > 0 then
    Result := FCurve.Samples[High(FCurve.Samples)].Cycle
  else
    Result := 0;
end;

function TframeZRWViewer.SharedStale: Boolean;
begin
  Result := FSharedParsed and not SameText(FShared.FileHash, FContext.FileHash);
end;

function TframeZRWViewer.DraftMode: TZRWSelectionMode;
begin
  if btnManual.Down then
    Result := zsmManual
  else
    Result := zsmAutomatic;
end;

function TframeZRWViewer.DraftMatchesShared: Boolean;
begin
  Result := FSharedParsed and not SharedStale and FDraftValid and
    (FShared.Mode = DraftMode) and
    (FShared.Interval.StartCycle = FDraftInterval.StartCycle) and
    (FShared.Interval.EndCycle = FDraftInterval.EndCycle) and
    (FShared.Interval.ThroughEnd = FDraftInterval.ThroughEnd);
end;

function TframeZRWViewer.CanApply: Boolean;
begin
  Result := Assigned(ElnAnalysisSettings) and FDraftValid and
    (FContext.Kind = ackCurrent) and (FContext.FileId > 0) and
    (FContext.FileHash <> '');
end;

procedure TframeZRWViewer.ParseShared;
begin
  FShared := Default(TZRWSelection);
  FSharedParsed := (FContext.Kind = ackCurrent) and
    (FContext.SharedSelection <> '') and
    TryParseSelection(FContext.SharedSelection, FShared);
end;

procedure TframeZRWViewer.InitDraft;
var
  Interval: TZRWInterval;
  Have: Boolean;
begin
  if FSharedParsed then
  begin
    Interval := FShared.Interval;
    Have := True;
  end
  else
  begin
    Interval := FDetected;
    Have := FDetectedFound;
  end;
  FUpdating := True;
  try
    SetModeButton(FSharedParsed and (FShared.Mode = zsmManual));
    if Have then
    begin
      edStart.Text := NumberText(Interval.StartCycle);
      edEnd.Text := NumberText(Interval.EndCycle);
    end
    else
    begin
      edStart.Text := '';
      edEnd.Text := '';
    end;
    chkThroughEnd.Checked := Have and Interval.ThroughEnd;
  finally
    FUpdating := False;
  end;
  FDraftTouched := False;
  EvaluateDraft;
  RefreshSelectionUi;
end;

procedure TframeZRWViewer.EvaluateDraft;
var
  StartValue, EndValue: Double;
begin
  FDraftValid := False;
  FDraftWarnings := [];
  FDraftError := '';
  FDraftStats := Default(TZRWStats);
  FDraftInterval := Default(TZRWInterval);
  if FLoadError <> '' then
  begin
    FDraftError := FLoadError;
    Exit;
  end;
  if DraftMode = zsmAutomatic then
  begin
    if not FDetectedFound then
    begin
      FDraftError := 'No plateau was detected.';
      Exit;
    end;
    FDraftInterval := FDetected;
  end
  else
  begin
    if not TryParseBound(edStart.Text, StartValue) then
    begin
      FDraftError := 'The start is not a number.';
      Exit;
    end;
    if chkThroughEnd.Checked then
      EndValue := LastCycle
    else if not TryParseBound(edEnd.Text, EndValue) then
    begin
      FDraftError := 'The end is not a number.';
      Exit;
    end;
    if not (StartValue < EndValue) then
    begin
      FDraftError := 'The start must be less than the end.';
      Exit;
    end;
    FDraftInterval.StartCycle := StartValue;
    FDraftInterval.EndCycle := EndValue;
    FDraftInterval.ThroughEnd := chkThroughEnd.Checked;
  end;
  try
    FDraftStats := IntervalStats(FCurve, FDraftInterval);
    if DraftMode = zsmManual then
      FDraftWarnings := ManualWarnings(FCurve, FDraftInterval);
    FDraftValid := True;
  except
    on E: EZRWFormatError do
      FDraftError := E.Message + '.';
  end;
end;

procedure TframeZRWViewer.DraftEdited;
begin
  if not FConflictPending then
    FMessage := '';
  FDraftTouched := True;
  EvaluateDraft;
  RefreshSelectionUi;
end;

function TframeZRWViewer.StaleUntouched: Boolean;
begin
  Result := SharedStale and not FDraftTouched;
end;

procedure TframeZRWViewer.RefreshSelectionUi;
var
  Manual: Boolean;
  Text, Mode: string;

  procedure AddWarning(const Part: string);
  begin
    if Text <> '' then
      Text := Text + '  |  ';
    Text := Text + Part;
  end;

begin
  Manual := DraftMode = zsmManual;
  edStart.Enabled := Manual;
  edEnd.Enabled := Manual and not chkThroughEnd.Checked;
  chkThroughEnd.Enabled := Manual;
  btnApply.Enabled := CanApply;
  btnReload.Enabled := Assigned(ElnAnalysisSettings) and FConflictPending;

  if FLoadError <> '' then
    lblStats.Caption := FLoadError
  else if StaleUntouched then
  begin
    if FShared.Mode = zsmManual then
      Mode := 'manual'
    else
      Mode := 'automatic';
    lblStats.Caption := Format('Stale selection: the file changed after it was ' +
      'applied (%s, cycles %s%s%s). No interval values are available until ' +
      'you apply a new selection (Manual or Automatic).',
      [Mode, NumberText(FShared.Interval.StartCycle), #$2013,
       NumberText(FShared.Interval.EndCycle)]);
  end
  else if FDraftValid then
  begin
    if DraftMatchesShared then
      Mode := Format('applied, revision %d', [FShared.Revision])
    else
      Mode := 'draft, not applied';
    lblStats.Caption := Format('Cycles %s%s%s  |  Samples: %d  |  COF: %s  |  STD: %s  |  %s',
      [NumberText(FDraftInterval.StartCycle), #$2013,
       NumberText(FDraftInterval.EndCycle), FDraftStats.Count,
       FloatToStrF(FDraftStats.Mean, ffFixed, 8, 4, TFormatSettings.Invariant),
       FloatToStrF(FDraftStats.PopulationStd, ffFixed, 8, 4, TFormatSettings.Invariant),
       Mode]);
  end
  else
    lblStats.Caption := 'Interval unavailable. ' + FDraftError;

  Text := '';
  if SharedStale and not StaleUntouched then
    AddWarning('Stale selection: extraction is blocked until you apply a new selection (Manual or Automatic)');
  if FDraftValid then
  begin
    if zwBelowMinimumDuration in FDraftWarnings then
      AddWarning('Warning: the interval is shorter than 20% of the recorded cycles');
    if zwUnstable in FDraftWarnings then
      AddWarning('Warning: the interval is not a stable plateau');
    if zwNonPositiveValues in FDraftWarnings then
      AddWarning('Warning: the interval contains non-positive COF values');
  end;
  if (FContext.Kind = ackCurrent) and (FContext.SharedSelection <> '') and
    not FSharedParsed then
    AddWarning('The stored selection cannot be read; Apply replaces it');
  if FMessage <> '' then
    AddWarning(FMessage);
  lblWarnings.Caption := Text;
  UpdateBand;
end;

procedure TframeZRWViewer.UpdateBand;
var
  Interval: TZRWInterval;
  Show: Boolean;
  Top: Double;
begin
  SeriesBand.Clear;
  if StaleUntouched then
  begin
    Interval := FShared.Interval;
    Show := True;
  end
  else
  begin
    Interval := FDraftInterval;
    Show := FDraftValid;
  end;
  if Show and (Series1.Count > 0) then
  begin
    Top := Series1.MaxYValue;
    SeriesBand.AddXY(Interval.StartCycle, Top);
    SeriesBand.AddXY(Interval.EndCycle, Top);
  end;
end;

procedure TframeZRWViewer.SetModeButton(Manual: Boolean);
begin
  if Manual then
    btnManual.Down := True
  else
    btnAutomatic.Down := True;
end;

procedure TframeZRWViewer.SetDraftMode(Mode: TZRWSelectionMode);
begin
  SetModeButton(Mode = zsmManual);
  ModeButtonClick(nil);
end;

procedure TframeZRWViewer.SetDraftBounds(Start, Stop: Double; ThroughEnd: Boolean);
begin
  FUpdating := True;
  try
    SetModeButton(True);
    edStart.Text := NumberText(Start);
    edEnd.Text := NumberText(Stop);
    chkThroughEnd.Checked := ThroughEnd;
  finally
    FUpdating := False;
  end;
  DraftEdited;
end;

procedure TframeZRWViewer.ModeButtonClick(Sender: TObject);
begin
  if FUpdating then
    Exit;
  if (DraftMode = zsmAutomatic) and FDetectedFound then
  begin
    FUpdating := True;
    try
      edStart.Text := NumberText(FDetected.StartCycle);
      edEnd.Text := NumberText(FDetected.EndCycle);
      chkThroughEnd.Checked := FDetected.ThroughEnd;
    finally
      FUpdating := False;
    end;
  end;
  DraftEdited;
end;

procedure TframeZRWViewer.edBoundChange(Sender: TObject);
begin
  if not FUpdating then
    DraftEdited;
end;

procedure TframeZRWViewer.chkThroughEndClick(Sender: TObject);
begin
  if FUpdating then
    Exit;
  if chkThroughEnd.Checked then
  begin
    FUpdating := True;
    try
      edEnd.Text := NumberText(LastCycle);
    finally
      FUpdating := False;
    end;
  end;
  DraftEdited;
end;

procedure TframeZRWViewer.btnApplyClick(Sender: TObject);
begin
  ApplySelection;
end;

procedure TframeZRWViewer.btnReloadClick(Sender: TObject);
begin
  ReloadSelection;
end;

procedure TframeZRWViewer.ApplySelection;
var
  Service: IElnAnalysisSettings;
  Selection: TZRWSelection;
  Current: string;
begin
  Service := ElnAnalysisSettings;
  if (Service = nil) or not CanApply then
    Exit;
  Selection := Default(TZRWSelection);
  Selection.Mode := DraftMode;
  Selection.Interval := FDraftInterval;
  Selection.ReaderVersion := ZRWReaderVersion;
  Selection.AlgorithmVersion := ZRWAlgorithmVersion;
  Selection.FileHash := FContext.FileHash;
  Selection.ApplyId := TGUID.NewGuid.ToString;
  Selection.AppliedAt := FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"Z"',
    TTimeZone.Local.ToUniversalTime(Now), TFormatSettings.Invariant);
  Selection.AppliedBy := Service.CurrentUserId;
  Selection.Revision := 1;
  if FSharedParsed then
    Selection.Revision := FShared.Revision + 1;
  case Service.Apply(FContext.FileId, ZRWReaderId, FContext.SharedSelection,
    SelectionToJson(Selection), Current) of
    aarApplied:
      begin
        FContext.SharedSelection := Current;
        FAnalysisResolved := False;
        FConflictPending := False;
        FConflictJson := '';
        ParseShared;
        FMessage := Format('Applied as revision %d.', [Selection.Revision]);
      end;
    aarConflict:
      begin
        FConflictPending := True;
        FConflictJson := Current;
        FMessage := 'Another change was applied first. Your draft is kept; ' +
          'press Reload to see the current selection, then apply again.';
      end;
    aarDenied:
      FMessage := 'You do not have permission to change this selection.';
    aarSigned:
      FMessage := 'The item is signed; the selection cannot be changed.';
    aarHashMismatch:
      FMessage := 'The stored file differs from the one shown here. Reopen the file before applying.';
    aarInvalid:
      FMessage := 'The selection was rejected as invalid.';
    aarTooLarge:
      FMessage := 'The selection is too large to store.';
  end;
  RefreshSelectionUi;
end;

procedure TframeZRWViewer.ReloadSelection;
begin
  if (ElnAnalysisSettings = nil) or not FConflictPending then
    Exit;
  FContext.SharedSelection := FConflictJson;
  FAnalysisResolved := False;
  FConflictPending := False;
  FConflictJson := '';
  ParseShared;
  FMessage := 'Reloaded the current selection. Review it and apply again if needed.';
  InitDraft;
end;

function TframeZRWViewer.GetAnalysisSnapshot(const KeyName: string): string;
begin
  Result := '';
  if SameText(KeyName, ZRWKeyCof) or SameText(KeyName, ZRWKeyCofStd) then
    Result := Analysis.Snapshot;
end;

function TframeZRWViewer.GetAnalysisStatus: string;
begin
  Result := Analysis.Status;
end;

procedure TframeZRWViewer.SeriesToText(List: TStringList);
var
  I: Integer;
begin
  List.Add('Cycles' + #9 + 'COF');
  for I := 0 to Series1.Count - 1 do
    List.Add(FloatToStrF(Series1.XValues[I], ffFixed, 10, 1) + #9 +
             FloatToStrF(Series1.YValues[I], ffFixed, 8, 4));
end;

function TframeZRWViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
begin
  Result := nil;
  if Series1.Count = 0 then
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

procedure TframeZRWViewer.btnCopyClick(Sender: TObject);
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    SeriesToText(List);
    ClipBoard.AsText := List.Text;
  finally
    List.Free;
  end;
end;

procedure TframeZRWViewer.btnSaveClick(Sender: TObject);
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


procedure TframeZRWViewer.ChartMouseWheel(Sender: TObject;
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

procedure TframeZRWViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  XVal, YVal: Double;
begin
  XVal := Chart.BottomAxis.CalcPosPoint(X);
  YVal := Chart.LeftAxis.CalcPosPoint(Y);
  Status.SimpleCaption := Format('%s  |  Cursor: %.1f, %.4f',
    [FStatusBase, XVal, YVal]);
end;

procedure TframeZRWViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;

function TframeZRWViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  V: Double;
  Computed: TZRWAnalysis;
  Origin: string;

  function ParseWithUnit(const S: string; const DefaultUnits: string;
    out Num: Double; out ActualUnits: string): Boolean;
  var
    I, C: Integer;
    NumStr, Suffix: string;
  begin
    Result := False;
    if S = '' then Exit;
    I := 1;
    while (I <= Length(S)) and (CharInSet(S[I], ['0'..'9', '.', '-', '+', 'E', 'e'])) do
      Inc(I);
    NumStr := Copy(S, 1, I - 1);
    Val(NumStr, Num, C);
    if (NumStr = '') or (C <> 0) then Exit;
    Suffix := LowerCase(Trim(Copy(S, I, MaxInt)));
    ActualUnits := DefaultUnits;
    if (Suffix = 'gf') or (Suffix = 'grf') then
    begin
      Num := Num * 0.00980665;
      ActualUnits := 'N';
    end
    else if Suffix = 'kgf' then
    begin
      Num := Num * 9.80665;
      ActualUnits := 'N';
    end
    else if Suffix = 'mn' then
    begin
      Num := Num * 0.001;
      ActualUnits := 'N';
    end;
    Result := True;
  end;

  procedure TryAdd(const AName, AStr, AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean = False);
  var
    Units: string;
  begin
    if ParseWithUnit(AStr, AUnits, V, Units) then
    begin
      KV.Name := AName;
      KV.Value := V;
      KV.Units := Units;
      KV.RecType := ARecType;
      KV.IsKey := AIsKey;
      KV.Description := '';
      List.Add(KV);
    end;
  end;

begin
  Result := nil;
  List := TList<TPluginKeyValue>.Create;
  try
    TryAdd('Fn', FCurve.Header.Load, 'N', prCondition, True);
    TryAdd('Cycles', FCurve.Header.Cycles, '', prCondition, True);
    TryAdd('Stroke', FCurve.Header.Stroke, 'mm', prCondition);
    TryAdd('Speed', FCurve.Header.Speed, 'mm/s', prCondition);
    TryAdd('Sampling Rate', FCurve.Header.SamplingRate, 'Hz', prCondition);
    TryAdd('Sampling Interval', FCurve.Header.SamplingInterval, '', prCondition);
    Computed := Analysis;
    if Computed.Available then
    begin
      if Computed.Mode = zsmAutomatic then
        Origin := 'automatic plateau'
      else
        Origin := 'manual selection';
      KV.Units := '';
      KV.RecType := prResult;
      KV.Description := 'Mean friction coefficient, cycles ' +
        NumberText(Computed.Interval.StartCycle) + #$2013 +
        NumberText(Computed.Interval.EndCycle) + ' (' + Origin + ')';
      KV.Name := ZRWKeyCof;
      KV.Value := Computed.Stats.Mean;
      KV.IsKey := True;
      List.Add(KV);
      KV.Name := ZRWKeyCofStd;
      KV.Value := Computed.Stats.PopulationStd;
      KV.IsKey := False;
      List.Add(KV);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeZRWViewer.GetDetailedInfo: string;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.AddPair('stroke_mm', FCurve.Header.Stroke);
    J.AddPair('speed_mm_s', FCurve.Header.Speed);
    J.AddPair('load', FCurve.Header.Load);
    J.AddPair('cycles', FCurve.Header.Cycles);
    J.AddPair('pause', FCurve.Header.Pause);
    J.AddPair('samplingRate', FCurve.Header.SamplingRate);
    J.AddPair('dataPoints', TJSONNumber.Create(Series1.Count));
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
