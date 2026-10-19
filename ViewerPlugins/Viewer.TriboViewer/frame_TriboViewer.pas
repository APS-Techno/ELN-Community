unit frame_TriboViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton,
  unit_ELNPluginCore, unit_ELNPluginTypes;

type

  TframeTriboViewer = class(TFrame)
    Status: TRzStatusBar;
    dlgSave: TSaveDialog;
    Chart: TChart;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    Series1: TFastLineSeries;
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FStroke: string;
    FSpeed: string;
    FLoad: string;
    FCycles: string;
    FPause: string;
    FSamplingRate: string;
    FStatusBase: string;
    FXLabel: string;
    FYLabel: string;
    procedure SeriesToText(List: TStringList);
    procedure ParseHeader(const Line: string);
    procedure UpdateStatus;
    procedure ProcessRawData(Lines: TStringList; StartLine, FnIdx, FlIdx: Integer);
    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromFile(const FileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  ClipBrd, System.Generics.Collections, System.JSON, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

procedure TframeTriboViewer.ParseHeader(const Line: string);
var
  Parts: TArray<string>;
  I: Integer;
begin
  Parts := Line.Split([#9]);
  I := 0;
  while I < Length(Parts) do
  begin
    if Parts[I].StartsWith('Stroke:') then
    begin
      if I + 1 < Length(Parts) then
        FStroke := Trim(Parts[I + 1]);
    end
    else if Parts[I].StartsWith('Speed:') then
    begin
      if I + 1 < Length(Parts) then
        FSpeed := Trim(Parts[I + 1]);
    end
    else if Parts[I].StartsWith('Duration:') then
    begin
    end
    else if Parts[I].StartsWith('Load:') then
    begin
      if I + 1 < Length(Parts) then
        FLoad := Trim(Parts[I + 1]);
    end
    else if Parts[I].StartsWith('Cycles:') then
    begin
      if I + 1 < Length(Parts) then
        FCycles := Trim(Parts[I + 1]);
    end
    else if Parts[I].StartsWith('Pause:') then
    begin
      if I + 1 < Length(Parts) then
        FPause := Trim(Parts[I + 1]);
    end
    else if Parts[I].StartsWith('Sampling rate:') then
    begin
      if I + 1 < Length(Parts) then
        FSamplingRate := Trim(Parts[I + 1]);
    end;
    Inc(I);
  end;
end;

constructor TframeTriboViewer.Create(AOwner: TComponent);
begin
  inherited;
  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;
end;

procedure TframeTriboViewer.UpdateStatus;
begin
  FStatusBase := Format('Stroke: %s mm  |  Speed: %s mm/s  |  Load: %s  |  Cycles: %s  |  Points: %d',
    [FStroke, FSpeed, FLoad, FCycles, Series1.Count]);
  Status.SimpleCaption := FStatusBase;
end;

procedure TframeTriboViewer.LoadFromFile(const FileName: string);
var
  Lines: TStringList;
  I: Integer;
  Line: string;
  Parts: TArray<string>;
  ColNames, ColUnits: TArray<string>;
  XVal, YVal: Double;
  HeaderDone, DataStarted, IsRawData: Boolean;
  K, YColIdx, FnColIdx, FlColIdx: Integer;
begin
  FStroke := '';
  FSpeed := '';
  FLoad := '';
  FCycles := '';
  FPause := '';
  FSamplingRate := '';
  FXLabel := 'Cycles';
  FYLabel := 'COF';

  Series1.Clear;
  Chart.AutoRepaint := False;
  Series1.BeginUpdate;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);

    HeaderDone := False;
    DataStarted := False;
    ColNames := nil;
    ColUnits := nil;
    YColIdx := 1;
    FnColIdx := -1;
    FlColIdx := -1;
    IsRawData := False;

    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;

      if not HeaderDone then
      begin
        if (Pos(':', Line) > 0) and
           not CharInSet(Line[1], ['0'..'9', '-', '+']) then
        begin
          ParseHeader(Lines[I]);
          Continue;
        end;

        if CharInSet(Line[1], ['A'..'Z', 'a'..'z']) then
        begin
          ColNames := Lines[I].Split([#9]);
          if Length(ColNames) >= 2 then
          begin
            YColIdx := Length(ColNames) - 1;
            FXLabel := Trim(ColNames[0]);
            FYLabel := Trim(ColNames[YColIdx]);
            for K := 0 to High(ColNames) do
            begin
              if SameText(Trim(ColNames[K]), 'Fn') then
                FnColIdx := K
              else if SameText(Trim(ColNames[K]), 'Fl') then
                FlColIdx := K;
            end;
            IsRawData := (FnColIdx >= 0) and (FlColIdx >= 0);
          end;
          Continue;
        end;

        if Line[1] = '#' then
        begin
          ColUnits := Lines[I].Split([#9]);
          Continue;
        end;

        HeaderDone := True;
      end;

      if IsRawData then
      begin
        ProcessRawData(Lines, I, FnColIdx, FlColIdx);
        Break;
      end;

      Parts := Line.Split([#9]);
      if Length(Parts) < 2 then
        Continue;

      if not DataStarted then
      begin
        DataStarted := True;
        if YColIdx >= Length(Parts) then
        begin
          YColIdx := Length(Parts) - 1;
          if (ColNames <> nil) and (YColIdx < Length(ColNames)) then
            FYLabel := Trim(ColNames[YColIdx]);
        end;
        if (ColUnits <> nil) and (YColIdx < Length(ColUnits)) then
        begin
          Line := Trim(ColUnits[YColIdx]);
          if (Line <> '') and (Line <> '#') then
            FYLabel := FYLabel + ' (' + Line + ')';
        end;
      end;

      XVal := StrToFloatDef(Parts[0], 0);
      YVal := StrToFloatDef(Parts[YColIdx], 0);
      Series1.AddXY(XVal, YVal);
    end;
  finally
    Lines.Free;
    Series1.EndUpdate;
    ApplyChartTheme(Chart);
    Chart.BottomAxis.Title.Caption := FXLabel;
    Chart.LeftAxis.Title.Caption := FYLabel;
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;

  UpdateStatus;
end;

procedure TframeTriboViewer.ProcessRawData(Lines: TStringList;
  StartLine, FnIdx, FlIdx: Integer);
const
  MAX_POINTS = 2000;
var
  I, J, Count, Window, WinCount: Integer;
  Parts: TArray<string>;
  FnArr, FlArr: TArray<Double>;
  AvgFl, SumCOF, Scale: Double;
  MaxIdx: Integer;
begin
  Count := Lines.Count - StartLine;
  SetLength(FnArr, Count);
  SetLength(FlArr, Count);
  J := 0;
  for I := StartLine to Lines.Count - 1 do
  begin
    Parts := Trim(Lines[I]).Split([#9]);
    if (Length(Parts) <= FnIdx) or (Length(Parts) <= FlIdx) then
      Continue;
    FnArr[J] := StrToFloatDef(Parts[FnIdx], 0);
    FlArr[J] := StrToFloatDef(Parts[FlIdx], 0);
    Inc(J);
  end;
  Count := J;
  if Count = 0 then Exit;

  // Skip the first three settling samples. With no later samples, leave
  // the raw lateral force unchanged rather than inventing a baseline.
  AvgFl := 0;
  MaxIdx := Round(0.9 * Count);
  if MaxIdx >= Count then
    MaxIdx := Count - 1;
  for I := 3 to MaxIdx do
    AvgFl := AvgFl + FlArr[I];
  if MaxIdx >= 3 then
    AvgFl := AvgFl / (MaxIdx - 3 + 1);
  for I := 0 to Count - 1 do
    FlArr[I] := FlArr[I] - AvgFl;

  Window := Count div MAX_POINTS;
  if Window < 1 then Window := 1;

  Scale := StrToFloatDef(FCycles, 0);
  if Scale <= 0 then Scale := Count;
  Scale := Scale / Count;

  SumCOF := 0;
  WinCount := 0;
  for I := 0 to Count - 1 do
  begin
    if FnArr[I] > 0 then
      SumCOF := SumCOF + Abs(FlArr[I]) / FnArr[I];
    Inc(WinCount);
    if WinCount = Window then
    begin
      Series1.AddXY(I * Scale, SumCOF / WinCount);
      SumCOF := 0;
      WinCount := 0;
    end;
  end;
  if WinCount > 0 then
    Series1.AddXY((Count - 1) * Scale, SumCOF / WinCount);

  FXLabel := 'Cycles';
  FYLabel := 'COF';
end;

procedure TframeTriboViewer.SeriesToText(List: TStringList);
var
  I: Integer;
begin
  List.Add(FXLabel + #9 + FYLabel);
  for I := 0 to Series1.Count - 1 do
    List.Add(FloatToStrF(Series1.XValues[I], ffFixed, 10, 1) + #9 +
             FloatToStrF(Series1.YValues[I], ffFixed, 8, 4));
end;

function TframeTriboViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
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

procedure TframeTriboViewer.btnCopyClick(Sender: TObject);
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

procedure TframeTriboViewer.btnSaveClick(Sender: TObject);
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


procedure TframeTriboViewer.ChartMouseWheel(Sender: TObject;
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

procedure TframeTriboViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  XVal, YVal: Double;
begin
  XVal := Chart.BottomAxis.CalcPosPoint(X);
  YVal := Chart.LeftAxis.CalcPosPoint(Y);
  Status.SimpleCaption := Format('%s  |  Cursor: %.1f, %.4f',
    [FStatusBase, XVal, YVal]);
end;

procedure TframeTriboViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;

function TframeTriboViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  V: Double;

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
    TryAdd('Fn', FLoad, 'N', prCondition, True);
    TryAdd('Cycles', FCycles, '', prCondition, True);
    TryAdd('Stroke', FStroke, 'mm', prCondition);
    TryAdd('Speed', FSpeed, 'mm/s', prCondition);
    TryAdd('Sampling Rate', FSamplingRate, 'Hz', prCondition);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeTriboViewer.GetDetailedInfo: string;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.AddPair('stroke_mm', FStroke);
    J.AddPair('speed_mm_s', FSpeed);
    J.AddPair('load', FLoad);
    J.AddPair('cycles', FCycles);
    J.AddPair('pause', FPause);
    J.AddPair('samplingRate', FSamplingRate);
    J.AddPair('dataPoints', TJSONNumber.Create(Series1.Count));
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
