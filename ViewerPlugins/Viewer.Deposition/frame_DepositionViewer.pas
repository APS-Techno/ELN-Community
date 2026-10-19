unit frame_DepositionViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ComCtrls, Vcl.WinXPanels, Vcl.ExtCtrls, RzTabs, RzCommon, RzPanel,
  RzButton, VCLTee.TeEngine, VCLTee.TeeProcs, VCLTee.Chart, VCLTee.Series,
  SynEdit, SynEditTypes, SynEditCodeFolding, SynEditHighlighter,
  SynHighlighterGeneral,
  unit_LogFile, unit_DepositionData;

type
  TframeDepositionViewer = class(TFrame)
    Pages: TRzTabControl;
    Cards: TCardPanel;
    CardOverview: TCard;
    lvOverview: TListView;
    CardRecipe: TCard;
    lvRecipeParams: TListView;
    synScript: TSynEdit;
    Syn: TSynGeneralSyn;
    CardPressure: TCard;
    ChartPressure: TChart;
    CardTemperature: TCard;
    ChartTemperature: TChart;
    CardGas: TCard;
    ChartGas: TChart;
    CardBias: TCard;
    ChartBias: TChart;
    CardVI: TCard;
    ChartVI: TChart;
    CardStage: TCard;
    ChartStage: TChart;
    CardText: TCard;
    memText: TMemo;
    procedure PagesChange(Sender: TObject);
    procedure lvOverviewDblClick(Sender: TObject);
    procedure lvOverviewMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure lvOverviewCustomDrawSubItem(Sender: TCustomListView;
      Item: TListItem; SubItem: Integer; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure lvOverviewInfoTip(Sender: TObject; Item: TListItem;
      var InfoTip: string);
  private
    type
      TOverviewRow = record
        Key, Value: string;
        GroupId: Integer;
        Link: string;
        Hint: string;
        Color: TColor;  // value-cell font color, or clNone for default
        Tab: Integer;   // chart tab opened on double-click, or -1
      end;
  var
    FLogFile: TLogFile;        // not owned; supplied by plugin
    FSnapshot: TDepoSnapshot;  // not owned; supplied by plugin
    FElapsedCol: Integer;
    FRows: TArray<TOverviewRow>; // parallel to lvOverview.Items
    FToolbar: TRzPanel;
    FBtnCopy: TRzBitBtn;
    FBtnSave: TRzBitBtn;
    FDlgSave: TSaveDialog;
    procedure CreateToolbar;
    procedure ScanScriptFolds(Sender: TObject; FoldRanges: TSynFoldRanges;
      LinesToScan: TStrings; FromLine, ToLine: Integer);
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    function ChartByTab(TabIndex: Integer): TChart;
    function FirstChartWithSeries: TChart;
    procedure ClearAll;
    procedure AddSeries(Chart: TChart; const ColName: string;
      RightAxis: Boolean = False);
    procedure FillCharts;
    procedure FillOverview;
    procedure FillRecipe;
    function AddGroup(const Header: string): Integer;
    procedure AddRow(GroupId: Integer; const Key, Value: string;
      const Link: string = ''; AColor: TColor = clNone;
      const HintText: string = ''; ATab: Integer = -1);
    procedure OpenLink(const Url: string);
  public
    constructor Create(AOwner: TComponent); override;
    function DisplayRun(LogFile: TLogFile; Snapshot: TDepoSnapshot): Boolean;
    procedure DisplayRawText(const AText: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetOverviewPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

implementation

uses
  System.JSON, System.Math, System.Character, System.StrUtils,
  System.DateUtils, Winapi.ShellAPI, Vcl.Imaging.pngimage,
  unit_ELNPluginCore, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

const
  TAB_OVERVIEW = 0;
  TAB_RECIPE   = 1;
  TAB_PRESSURE = 2;

type
  TChannelChart = record
    Col: string;
    Tab: Integer;
    RightAxis: Boolean;
  end;

  TSubRow = record
    Caption, Value, Link: string;
    Color: TColor;
  end;

// G500 is a pressure *controller*: S_ is the process pressure it measures
// (log left axis, Torr) and TV_ is its throttle-valve position (right axis,
// %), the diagnostic for whether the PID still had headroom.
const
  CHANNEL_CHARTS: array[0..30] of TChannelChart = (
    (Col: 'S_pm';              Tab: 2; RightAxis: False),
    (Col: 'S_pl';              Tab: 2; RightAxis: False),
    (Col: 'S_G500#1';          Tab: 2; RightAxis: False),
    (Col: 'TV_G500#1';         Tab: 2; RightAxis: True),
    (Col: 'S_tmp';             Tab: 3; RightAxis: False),
    (Col: 'S_KCM91';           Tab: 3; RightAxis: False),
    (Col: 'MFC_N21';           Tab: 4; RightAxis: False),
    (Col: 'MFC_Ar1';           Tab: 4; RightAxis: False),
    (Col: 'MFC_Ar2';           Tab: 4; RightAxis: False),
    (Col: 'MFC_N22';           Tab: 4; RightAxis: False),
    (Col: 'BIAS_N6705C_ch1_V'; Tab: 5; RightAxis: False),
    (Col: 'BIAS_N6705C_ch2_V'; Tab: 5; RightAxis: False),
    (Col: 'BIAS_N6705C_ch3_V'; Tab: 5; RightAxis: False),
    (Col: 'BIAS_N6705C_ch4_V'; Tab: 5; RightAxis: False),
    (Col: 'BIAS_N6705C_ch1_I'; Tab: 5; RightAxis: True),
    (Col: 'BIAS_N6705C_ch2_I'; Tab: 5; RightAxis: True),
    (Col: 'BIAS_N6705C_ch3_I'; Tab: 5; RightAxis: True),
    (Col: 'BIAS_N6705C_ch4_I'; Tab: 5; RightAxis: True),
    (Col: 'PSU_DC4001A_V';     Tab: 6; RightAxis: False),
    (Col: 'PSU_G3F_B_V';       Tab: 6; RightAxis: False),
    (Col: 'PSU_G3F_C_V';       Tab: 6; RightAxis: False),
    (Col: 'PSU_RF301_V';       Tab: 6; RightAxis: False),
    (Col: 'PSU_RF601_V';       Tab: 6; RightAxis: False),
    (Col: 'PSU_DC4001A_I';     Tab: 6; RightAxis: True),
    (Col: 'PSU_G3F_B_I';       Tab: 6; RightAxis: True),
    (Col: 'PSU_G3F_C_I';       Tab: 6; RightAxis: True),
    (Col: 'PSU_RF301_I';       Tab: 6; RightAxis: True),
    (Col: 'PSU_RF601_I';       Tab: 6; RightAxis: True),
    (Col: 'STG_VS';            Tab: 7; RightAxis: False),
    (Col: 'STG_HS';            Tab: 7; RightAxis: False),
    (Col: 'STG_rotation';      Tab: 7; RightAxis: False)
  );

// Snapshot means use short channel names ('pm', 'Ar2', 'RF601') while log
// columns carry a device prefix and, for PSUs, a _V/_I suffix ('S_pm',
// 'MFC_Ar2', 'PSU_RF601_V'). Match exact first, then '<...>_<name>' suffix,
// then '<...>_<name>_<...>' infix, and hand back the matched column so the
// caller can verify it against the attached log.
function ChannelChartFor(const Channel: string; out Col: string;
  out Tab: Integer): Boolean;
var
  I: Integer;
begin
  Col := '';
  Tab := -1;
  if Channel = '' then Exit(False);
  for I := Low(CHANNEL_CHARTS) to High(CHANNEL_CHARTS) do
    if SameText(CHANNEL_CHARTS[I].Col, Channel) then
    begin
      Col := CHANNEL_CHARTS[I].Col;
      Tab := CHANNEL_CHARTS[I].Tab;
      Exit(True);
    end;
  for I := Low(CHANNEL_CHARTS) to High(CHANNEL_CHARTS) do
    if EndsText('_' + Channel, CHANNEL_CHARTS[I].Col) or
      ContainsText(CHANNEL_CHARTS[I].Col, '_' + Channel + '_') then
    begin
      Col := CHANNEL_CHARTS[I].Col;
      Tab := CHANNEL_CHARTS[I].Tab;
      Exit(True);
    end;
  Result := False;
end;

// Older RecipeModel builds serialized a region ending at the last script
// statement with "#endregion" glued onto the statement line. Historical
// snapshots keep that form forever, so split the marker onto its own line
// for display. Only unquoted "#endregion" markers move; user comments and
// '#' inside strings stay untouched.
function SplitTrailingEndRegion(const Script: string): string;
var
  Lines: TStringList;
  I, P: Integer;
  Line, Rest: string;
  InQuote: Boolean;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Script;
    for I := Lines.Count - 1 downto 0 do
    begin
      Line := Lines[I];
      InQuote := False;
      for P := 1 to Length(Line) do
        if Line[P] = '"' then
          InQuote := not InQuote
        else if (Line[P] = '#') and not InQuote then
        begin
          Rest := Trim(Copy(Line, P + 1, MaxInt));
          if (SameText(Rest, 'endregion') or
             (Rest.StartsWith('endregion', True) and (Rest.Length > 9) and
              Rest[10].IsWhiteSpace)) and
            (Trim(Copy(Line, 1, P - 1)) <> '') then
          begin
            Lines[I] := TrimRight(Copy(Line, 1, P - 1));
            Lines.Insert(I + 1, Copy(Line, P, MaxInt));
          end;
          Break; // first unquoted '#' starts a comment: nothing further to scan
        end;
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

constructor TframeDepositionViewer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  CreateToolbar;
  // #region/#endregion markers fold like Delphi IDE regions. The handler must
  // be assigned before UseCodeFolding so the first scan already sees it.
  synScript.OnScanForFoldRanges := ScanScriptFolds;
  synScript.UseCodeFolding := True;
end;

// Region markers are '#' or '//' comments whose body starts with the word
// "region" / "endregion" (same grammar as RecipeModel's RegionMarker).
procedure TframeDepositionViewer.ScanScriptFolds(Sender: TObject;
  FoldRanges: TSynFoldRanges; LinesToScan: TStrings; FromLine, ToLine: Integer);
var
  Line: Integer;
  S: string;

  function IsWord(const Body, Keyword: string): Boolean;
  begin
    Result := Body.StartsWith(Keyword, True) and
      ((Body.Length = Keyword.Length) or Body[Keyword.Length + 1].IsWhiteSpace);
  end;

begin
  for Line := FromLine to ToLine do
  begin
    S := TrimLeft(LinesToScan[Line]);
    if S.StartsWith('//') then
      S := TrimLeft(Copy(S, 3, MaxInt))
    else if S.StartsWith('#') then
      S := TrimLeft(Copy(S, 2, MaxInt))
    else
      S := '';

    if IsWord(S, 'region') then
      FoldRanges.StartFoldRange(Line + 1, FoldRegionType)
    else if IsWord(S, 'endregion') then
      FoldRanges.StopFoldRange(Line + 1, FoldRegionType)
    else
      FoldRanges.NoFoldInfo(Line + 1);
  end;
end;

procedure TframeDepositionViewer.CreateToolbar;
var
  PPI: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, PPI, 96);
  end;

begin
  PPI := CurrentPPI;

  FToolbar := TRzPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alBottom;
  FToolbar.Height := S(34);
  FToolbar.BorderOuter := fsNone;
  FToolbar.AlignWithMargins := True;

  FBtnCopy := TRzBitBtn.Create(Self);
  FBtnCopy.Parent := FToolbar;
  FBtnCopy.Align := alLeft;
  FBtnCopy.AlignWithMargins := True;
  FBtnCopy.Width := S(80);
  FBtnCopy.Caption := 'Copy';
  FBtnCopy.OnClick := BtnCopyClick;

  FBtnSave := TRzBitBtn.Create(Self);
  FBtnSave.Parent := FToolbar;
  FBtnSave.Align := alLeft;
  FBtnSave.AlignWithMargins := True;
  FBtnSave.Width := S(80);
  FBtnSave.Caption := 'Save As';
  FBtnSave.OnClick := BtnSaveClick;

  FDlgSave := TSaveDialog.Create(Self);
  FDlgSave.Filter := 'PNG Image|*.png|BMP Image|*.bmp';
  FDlgSave.DefaultExt := 'png';
end;

function TframeDepositionViewer.ChartByTab(TabIndex: Integer): TChart;
begin
  case TabIndex of
    2: Result := ChartPressure;
    3: Result := ChartTemperature;
    4: Result := ChartGas;
    5: Result := ChartBias;
    6: Result := ChartVI;
    7: Result := ChartStage;
  else
    Result := nil;
  end;
end;

function TframeDepositionViewer.FirstChartWithSeries: TChart;
var
  I: Integer;
  C: TChart;
begin
  Result := nil;
  for I := 2 to 7 do
  begin
    C := ChartByTab(I);
    if Assigned(C) and (C.SeriesList.Count > 0) then
      Exit(C);
  end;
end;

procedure TframeDepositionViewer.ClearAll;
var
  I: Integer;
  C: TChart;
begin
  lvOverview.Items.Clear;
  lvOverview.Groups.Clear;
  FRows := nil;
  lvRecipeParams.Items.Clear;
  synScript.Lines.Clear;
  memText.Clear;
  for I := 2 to 7 do
  begin
    C := ChartByTab(I);
    C.AutoRepaint := False;
    C.SeriesList.Clear;
  end;
end;

procedure TframeDepositionViewer.AddSeries(Chart: TChart;
  const ColName: string; RightAxis: Boolean);
var
  Idx: TArray<Integer>;
  Line: TFastLineSeries;
  R, Col: Integer;
  X, Y: Double;
begin
  if not Assigned(FLogFile) then Exit;
  if not FLogFile.ResolveColumnName(ColName, Idx) then Exit;
  Col := Idx[0];

  Line := TFastLineSeries.Create(Self);
  Line.LinePen.Width := 2;
  if FLogFile.ColumnAt(Col).Units <> '' then
    Line.Title := ColName + ' [' + FLogFile.ColumnAt(Col).Units + ']'
  else
    Line.Title := ColName;
  if RightAxis then
    Line.VertAxis := aRightAxis;
  Line.BeginUpdate;
  Chart.AddSeries(Line);

  for R := 0 to FLogFile.RowCount - 1 do
  begin
    Y := FLogFile.CellNumeric(R, Col);
    if IsNaN(Y) then Continue;
    if Chart.LeftAxis.Logarithmic and (Y <= 0) then Continue;
    if FElapsedCol >= 0 then
      X := FLogFile.CellNumeric(R, FElapsedCol)
    else
      X := R;
    if IsNaN(X) then Continue;
    Line.AddXY(X, Y);
  end;
  Line.EndUpdate;
end;

procedure TframeDepositionViewer.FillCharts;
var
  Idx: TArray<Integer>;
  I: Integer;
  C: TChart;
begin
  FElapsedCol := -1;
  if Assigned(FLogFile) and FLogFile.ResolveColumnName('Elapsed', Idx) then
    FElapsedCol := Idx[0];

  if Assigned(FLogFile) then
    for var CC in CHANNEL_CHARTS do
      AddSeries(ChartByTab(CC.Tab), CC.Col, CC.RightAxis);

  for I := 2 to 7 do
  begin
    C := ChartByTab(I);
    ApplyChartTheme(C);
    if Assigned(FLogFile) and FLogFile.Truncated then
    begin
      C.SubTitle.Visible := True;
      C.SubTitle.Font.Color := clGray;
      C.SubTitle.Font.Size := 9;
      C.SubTitle.Text.Text :=
        Format('Preview - showing first %d rows', [FLogFile.RowCount]);
    end
    else
      C.SubTitle.Visible := False;
    C.AutoRepaint := True;
    C.Repaint;
  end;
end;

function TframeDepositionViewer.AddGroup(const Header: string): Integer;
var
  Grp: TListGroup;
begin
  Grp := lvOverview.Groups.Add;
  Grp.Header := Header;
  Result := Grp.GroupID;
end;

procedure TframeDepositionViewer.AddRow(GroupId: Integer;
  const Key, Value: string; const Link: string; AColor: TColor;
  const HintText: string; ATab: Integer);
var
  It: TListItem;
  Row: TOverviewRow;
begin
  It := lvOverview.Items.Add;
  It.Caption := Key;
  It.SubItems.Add(Value);
  It.GroupID := GroupId;
  Row.Key := Key;
  Row.Value := Value;
  Row.GroupId := GroupId;
  Row.Link := Link;
  Row.Hint := HintText;
  Row.Color := AColor;
  Row.Tab := ATab;
  FRows := FRows + [Row];
end;

procedure TframeDepositionViewer.OpenLink(const Url: string);
begin
  if Url = '' then Exit;
  if StartsText('eln:', Url) then
  begin
    if Assigned(ElnLinkHandler) then
      ElnLinkHandler.HandleLink(Url);
  end
  else if StartsText('http:', Url) or StartsText('https:', Url) then
    ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
end;

procedure TframeDepositionViewer.lvOverviewDblClick(Sender: TObject);
var
  Row: TOverviewRow;
begin
  if Assigned(lvOverview.Selected) and
    (lvOverview.Selected.Index < Length(FRows)) then
  begin
    Row := FRows[lvOverview.Selected.Index];
    if Row.Tab >= 0 then
    begin
      Pages.TabIndex := Row.Tab;
      Cards.ActiveCardIndex := Row.Tab;
    end
    else
      OpenLink(Row.Link);
  end;
end;

procedure TframeDepositionViewer.lvOverviewMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  It: TListItem;
begin
  It := lvOverview.GetItemAt(X, Y);
  if Assigned(It) and (It.Index < Length(FRows)) and
    ((FRows[It.Index].Link <> '') or (FRows[It.Index].Tab >= 0)) then
    lvOverview.Cursor := crHandPoint
  else
    lvOverview.Cursor := crDefault;
end;

procedure TframeDepositionViewer.lvOverviewCustomDrawSubItem(
  Sender: TCustomListView; Item: TListItem; SubItem: Integer;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Color := lvOverview.Font.Color;
  Sender.Canvas.Font.Style := [];
  if (SubItem = 1) and (Item.Index < Length(FRows)) then
  begin
    if (FRows[Item.Index].Link <> '') or (FRows[Item.Index].Tab >= 0) then
    begin
      Sender.Canvas.Font.Color := clHotLight;
      Sender.Canvas.Font.Style := [fsUnderline];
    end
    else if FRows[Item.Index].Color <> clNone then
      Sender.Canvas.Font.Color := FRows[Item.Index].Color;
  end;
end;

procedure TframeDepositionViewer.lvOverviewInfoTip(Sender: TObject;
  Item: TListItem; var InfoTip: string);
begin
  if (Item.Index < Length(FRows)) and (FRows[Item.Index].Hint <> '') then
    InfoTip := FRows[Item.Index].Hint;
end;

procedure TframeDepositionViewer.FillOverview;
var
  Src: TDepoSource;
  M: TDepoMean;
  Grp, Tab: Integer;
  Col: string;
  Idx: TArray<Integer>;
  Subs: TArray<TSubRow>;
  I: Integer;
  Glyph: Char;

  function FmtVal(const V: Double): string;
  begin
    Result := Format('%.5g', [V]);
  end;

  function FmtUtc(const Iso: string): string;
  var
    DT: TDateTime;
  begin
    try
      DT := ISO8601ToDate(Iso, True);
      Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', DT) + ' UTC';
    except
      Result := Iso;
    end;
  end;

  function FmtDuration(const Sec: Double): string;
  begin
    if Sec >= 60 then
      Result := Format('%d min %d s', [Trunc(Sec) div 60, Trunc(Sec) mod 60])
    else
      Result := Format('%.1f s', [Sec]);
  end;

  function ShortHash(const FP: string): string;
  begin
    Result := FP;
    if StartsText('sha256:', Result) then
      Delete(Result, 1, Length('sha256:'));
    if Length(Result) > 16 then
      Result := Copy(Result, 1, 6) + Char($2026) +
        Copy(Result, Length(Result) - 5, 6);
  end;

  function ResultColor(const R: string): TColor;
  begin
    if SameText(R, 'completed') then
      Result := clGreen
    else
      Result := clMaroon;
  end;

  function SourceLine(const S: TDepoSource): string;
  begin
    Result := Format('%s, %s, %s', [S.Material, S.Format, S.MagnetronModel]);
    if S.Erosion.Present then
      Result := Result + Format(', erosion %.3f mm', [S.Erosion.Value]);
  end;

  procedure AddSub(var List: TArray<TSubRow>; const ACaption, AValue,
    ALink: string; AColor: TColor);
  var
    R: TSubRow;
  begin
    if AValue = '' then Exit;
    R.Caption := ACaption;
    R.Value := AValue;
    R.Link := ALink;
    R.Color := AColor;
    List := List + [R];
  end;

  function PsuLine(const P: TDepoPowerSupply): string;
  begin
    Result := Format('%s (%s, %s)', [P.Id, P.Model, P.Description]);
    if not P.Responding then
      Result := Result + ' - not responding';
  end;

begin
  if Assigned(FSnapshot) then
  begin
    Grp := AddGroup('Run');
    if FSnapshot.HasOutcome then
    begin
      AddRow(Grp, 'Result', Char($25CF) + ' ' + FSnapshot.OutcomeResult, '',
        ResultColor(FSnapshot.OutcomeResult));
      AddRow(Grp, 'Started', FmtUtc(FSnapshot.StartedUtc));
      AddRow(Grp, 'Ended', FmtUtc(FSnapshot.EndedUtc));
      if FSnapshot.DurationSec > 0 then
        AddRow(Grp, 'Duration', FmtDuration(FSnapshot.DurationSec));
      if FSnapshot.HasBasePressure then
        AddRow(Grp, 'Base pressure',
          Format('%s = %s %s', [FSnapshot.BasePressureChannel,
            FmtVal(FSnapshot.BasePressureMin), FSnapshot.BasePressureUnit]));
    end
    else
      AddRow(Grp, 'Result', 'no outcome recorded (run not finalized)', '',
        clGrayText);
    AddRow(Grp, 'Specimen', FSnapshot.Specimen);
    AddRow(Grp, 'Recipe', FSnapshot.RecipeName);
    if not Assigned(FLogFile) then
      AddRow(Grp, 'Log file', 'Not attached to this item - charts unavailable',
        '', clMaroon);

    Grp := AddGroup('Signature');
    AddRow(Grp, 'Signed by', Format('%s (%s), %s',
      [FSnapshot.SignName, FSnapshot.SignRole, FSnapshot.SignIntent]));
    AddRow(Grp, 'Signed at', FmtUtc(FSnapshot.SignedAtUtc));
    AddRow(Grp, 'Software', Format('control %s / %s',
      [FSnapshot.SoftControl, FSnapshot.SoftWorker]));
    AddRow(Grp, 'Fingerprint', ShortHash(FSnapshot.Fingerprint), '', clNone,
      FSnapshot.Fingerprint);

    if Length(FSnapshot.Sources) > 0 then
    begin
      Grp := AddGroup('Sources');
      for Src in FSnapshot.Sources do
      begin
        AddRow(Grp, Format('Flange %d', [Src.Flange]), SourceLine(Src),
          Src.MagnetronElnLink);

        Subs := nil;
        AddSub(Subs, 'Target', DepoTargetLine(Src), '', clNone);
        // A negative gap means the operator entered a lift exceeding the
        // zero distance - physically impossible. Flag it; do not correct it.
        if Src.TargetDistance.Present and (Src.TargetDistance.Value < 0) then
          AddSub(Subs, 'Geometry', DepoGeometryLine(Src), '', clMaroon)
        else
          AddSub(Subs, 'Geometry', DepoGeometryLine(Src), '', clNone);
        if Src.PowerSupply.Present then
          AddSub(Subs, 'PSU', PsuLine(Src.PowerSupply),
            Src.PowerSupply.ElnLink, clNone);

        for I := 0 to High(Subs) do
        begin
          if I = High(Subs) then
            Glyph := Char($2514)
          else
            Glyph := Char($251C);
          AddRow(Grp, '  ' + Glyph + ' ' + Subs[I].Caption, Subs[I].Value,
            Subs[I].Link, Subs[I].Color);
        end;
      end;
    end;

    if Length(FSnapshot.Means) > 0 then
    begin
      Grp := AddGroup('Channel means');
      for M in FSnapshot.Means do
      begin
        if not ChannelChartFor(M.Channel, Col, Tab) or
          not Assigned(FLogFile) or
          not FLogFile.ResolveColumnName(Col, Idx) then
          Tab := -1;
        if Tab >= 0 then
          AddRow(Grp, M.Channel,
            FmtVal(IfThen(Abs(M.Value) < 1E-30, 0, M.Value)), '', clNone,
            Format('Double-click to open the %s chart',
              [Pages.Tabs[Tab].Caption]), Tab)
        else
          AddRow(Grp, M.Channel,
            FmtVal(IfThen(Abs(M.Value) < 1E-30, 0, M.Value)));
      end;
    end;
  end
  else
  begin
    Grp := AddGroup('Run');
    AddRow(Grp, 'Run snapshot', 'No .depo.json attached to this item', '',
      clGrayText);
    if not Assigned(FLogFile) then
      AddRow(Grp, 'Log file', 'Not attached to this item - charts unavailable',
        '', clMaroon);
  end;
end;

procedure TframeDepositionViewer.FillRecipe;
var
  P: TDepoRecipeParam;
  It: TListItem;
begin
  if not Assigned(FSnapshot) then Exit;
  for P in FSnapshot.RecipeParams do
  begin
    It := lvRecipeParams.Items.Add;
    It.Caption := P.Group;
    if P.Caption <> '' then
      It.SubItems.Add(P.Caption)
    else
      It.SubItems.Add(P.Name);
    It.SubItems.Add(P.Value);
    It.SubItems.Add(P.Units);
  end;
  // Snapshot scripts arrive with LF-only line breaks; normalize so the
  // editor splits them into lines.
  synScript.Lines.Text :=
    SplitTrailingEndRegion(AdjustLineBreaks(FSnapshot.RecipeScript));
  synScript.CaretXY := BufferCoord(1, 1);
  synScript.TopLine := 1;
end;

function TframeDepositionViewer.DisplayRun(LogFile: TLogFile;
  Snapshot: TDepoSnapshot): Boolean;
begin
  FLogFile := LogFile;
  FSnapshot := Snapshot;
  ClearAll;
  Pages.Visible := True;
  FToolbar.Visible := True;
  if ThemePluginsEnabled then
  begin
    synScript.Color := ThemePanelColor;
    synScript.Font.Color := ThemeTextColor;
    synScript.Gutter.Color := ThemePanelColor;
    synScript.Gutter.Font.Color := ThemeTextColor;
  end;
  try
    FillOverview;
    FillRecipe;
    FillCharts;
    if Assigned(FSnapshot) then
      Pages.TabIndex := TAB_OVERVIEW
    else
      Pages.TabIndex := TAB_PRESSURE;
    Cards.ActiveCardIndex := Pages.TabIndex;
    Result := True;
  except
    Result := False;
  end;
end;

procedure TframeDepositionViewer.DisplayRawText(const AText: string);
begin
  FLogFile := nil;
  FSnapshot := nil;
  ClearAll;
  Pages.Visible := False;
  FToolbar.Visible := False;
  memText.Text := AText;
  Cards.ActiveCard := CardText;
end;

procedure TframeDepositionViewer.PagesChange(Sender: TObject);
begin
  Cards.ActiveCardIndex := Pages.TabIndex;
end;

procedure TframeDepositionViewer.BtnCopyClick(Sender: TObject);
var
  C: TChart;
begin
  C := ChartByTab(Pages.TabIndex);
  if Assigned(C) then
    C.CopyToClipboardBitmap;
end;

procedure TframeDepositionViewer.BtnSaveClick(Sender: TObject);
var
  C: TChart;
  Bmp: TBitmap;
begin
  C := ChartByTab(Pages.TabIndex);
  if not Assigned(C) or (C.SeriesList.Count = 0) then Exit;
  if not FDlgSave.Execute then Exit;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(C.Width, C.Height);
    C.Draw(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height));
    if LowerCase(ExtractFileExt(FDlgSave.FileName)) = '.png' then
    begin
      var Png := Vcl.Imaging.pngimage.TPngImage.Create;
      try
        Png.Assign(Bmp);
        Png.SaveToFile(FDlgSave.FileName);
      finally
        Png.Free;
      end;
    end
    else
      Bmp.SaveToFile(FDlgSave.FileName);
  finally
    Bmp.Free;
  end;
end;

function TframeDepositionViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  C: TChart;
  Large: TBitmap;
begin
  Result := nil;
  C := ChartByTab(Pages.TabIndex);
  if (not Assigned(C)) or (C.SeriesList.Count = 0) then
    C := FirstChartWithSeries;
  if not Assigned(C) then Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    C.Draw(Large.Canvas, Rect(0, 0, 800, 600));
    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

function TframeDepositionViewer.GetOverviewPreviewBitmap(MaxW,
  MaxH: Integer): TBitmap;
const
  W = 800;
  H = 600;
  Pad = 8;
  KeyW = 260;
var
  Large: TBitmap;
  C: TCanvas;
  G, Y, LineH: Integer;
  Grp: TListGroup;
  Row: TOverviewRow;
begin
  Result := nil;
  if Length(FRows) = 0 then Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(W, H);
    C := Large.Canvas;
    C.Brush.Color := ThemePanelColor;
    C.FillRect(Rect(0, 0, W, H));
    C.Brush.Style := bsClear;
    C.Font.Name := lvOverview.Font.Name;
    C.Font.Height := -16;
    LineH := C.TextHeight('Wg') + 6;

    Y := Pad;
    C.Font.Style := [fsBold];
    C.Font.Color := ThemeTextColor;
    C.TextOut(Pad, Y, lvOverview.Columns[0].Caption);
    C.TextOut(Pad + KeyW, Y, lvOverview.Columns[1].Caption);
    Inc(Y, LineH);
    C.Pen.Color := ThemeGridColor;
    C.MoveTo(0, Y - 3);
    C.LineTo(W, Y - 3);

    for G := 0 to lvOverview.Groups.Count - 1 do
    begin
      if Y + 4 + 2 * LineH > H then Break;
      Grp := lvOverview.Groups.Items[G];
      Inc(Y, 4);
      C.Font.Style := [fsBold];
      C.Font.Color := clHotLight;
      C.TextOut(Pad, Y, Grp.Header);
      C.Pen.Color := ThemeGridColor;
      C.MoveTo(2 * Pad + C.TextWidth(Grp.Header), Y + LineH div 2);
      C.LineTo(W - Pad, Y + LineH div 2);
      Inc(Y, LineH);

      for Row in FRows do
      begin
        if Row.GroupId <> Grp.GroupID then Continue;
        if Y + LineH > H then Break;
        C.Font.Style := [];
        C.Font.Color := ThemeTextColor;
        C.TextRect(Rect(2 * Pad, Y, KeyW, Y + LineH), 2 * Pad, Y, Row.Key);
        if (Row.Link <> '') or (Row.Tab >= 0) then
        begin
          C.Font.Color := clHotLight;
          C.Font.Style := [fsUnderline];
        end
        else if Row.Color <> clNone then
          C.Font.Color := Row.Color;
        C.TextRect(Rect(Pad + KeyW, Y, W - Pad, Y + LineH), Pad + KeyW, Y,
          Row.Value);
        Inc(Y, LineH);
      end;
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

function TframeDepositionViewer.SaveState: string;
var
  JObj: TJSONObject;
begin
  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(1));
    JObj.AddPair('tab', TJSONNumber.Create(Pages.TabIndex));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeDepositionViewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  Idx: Integer;
begin
  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;
  try
    Idx := JObj.GetValue<Integer>('tab', 0);
    if Pages.Visible and (Idx >= 0) and (Idx < Pages.Tabs.Count) then
    begin
      Pages.TabIndex := Idx;
      Cards.ActiveCardIndex := Idx;
    end;
  finally
    JObj.Free;
  end;
end;

end.
