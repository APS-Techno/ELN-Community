unit frame_ColumnarDataViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.WinXPanels,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton, RzTabs,
  unit_ColumnarClassify;

type

  TframeColumnarDataViewer = class(TFrame)
    Status: TRzStatusBar;
    dlgSave: TSaveDialog;
    Pages: TRzTabControl;
    Cards: TCardPanel;
    CardChart: TCard;
    Chart: TChart;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    CardText: TCard;
    pnlTextTools: TRzPanel;
    btnCopyText: TRzBitBtn;
    btnSaveText: TRzBitBtn;
    memText: TMemo;
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure PagesChange(Sender: TObject);
  private
    FDelimiterName: string;
    FColumnNames: TArray<string>;
    FRowCount: Integer;
    FColCount: Integer;
    FFileName: string;
    FStatusBase: string;
    FIsTabular: Boolean;
    FLineCount: Integer;
    FByteCount: Int64;
    FTextTruncated: Boolean;
    FTableText: string;
    FTableNames: TArray<string>;
    FTableRows: TArray<TArray<string>>;

    procedure BuildSeries(ALines: TStrings;
      const AClassification: TColumnarClassification);
    procedure FillTextView(ALines: TStrings);
    procedure ApplyTextTheme;
    function ActiveContent: string;
    procedure UpdateStatus;
    procedure ClearSeries;
    function TextPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    procedure ChartMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromFile(const FileName: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetDetailedInfo: string;
    property IsTabular: Boolean read FIsTabular;
    property TableNames: TArray<string> read FTableNames;
    property TableRows: TArray<TArray<string>> read FTableRows;
  end;

implementation

uses
  ClipBrd, System.JSON, unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

const
  TAB_CHART = 0;
  TAB_TEXT  = 1;

  { The memo is a viewer, not a pager — past this the Win32 edit control turns
    sluggish and nobody is reading anyway. }
  MaxTextLines = 20000;

  { Ceiling on the text handed to extract_file_data, so one large log cannot
    swamp an agent's context. }
  MaxDetailChars = 200 * 1024;

constructor TframeColumnarDataViewer.Create(AOwner: TComponent);
begin
  inherited;
  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;
end;

const
  SeriesColors: array[0..7] of TColor = (
    clNavy, clRed, clGreen, clPurple, clTeal, clMaroon, clOlive, clFuchsia
  );

function FileSizeOf(const AFileName: string): Int64;
var
  Rec: TSearchRec;
begin
  Result := 0;
  if FindFirst(AFileName, faAnyFile, Rec) = 0 then
  try
    Result := Rec.Size;
  finally
    FindClose(Rec);
  end;
end;

function FormatBytes(ABytes: Int64): string;
begin
  if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)])
  else if ABytes >= 1024 then
    Result := Format('%.1f KB', [ABytes / 1024])
  else
    Result := Format('%d B', [ABytes]);
end;

procedure TframeColumnarDataViewer.ClearSeries;
var
  I: Integer;
begin
  for I := Chart.SeriesCount - 1 downto 0 do
    Chart.Series[I].Free;
end;

procedure TframeColumnarDataViewer.UpdateStatus;
begin
  if FIsTabular then
    FStatusBase := Format('%s  |  %d rows  |  %d columns  |  Delimiter: %s',
      [ExtractFileName(FFileName), FRowCount, FColCount, FDelimiterName])
  else
    FStatusBase := Format('%s  |  Text  |  %d lines  |  %s',
      [ExtractFileName(FFileName), FLineCount, FormatBytes(FByteCount)]);
  Status.SimpleCaption := FStatusBase;
end;

procedure TframeColumnarDataViewer.ApplyTextTheme;
begin
  memText.Color := ThemePanelColor;
  memText.Font.Color := ThemeTextColor;
  pnlTextTools.Color := ThemePanelColor;
end;

procedure TframeColumnarDataViewer.FillTextView(ALines: TStrings);
var
  I, Shown: Integer;
begin
  memText.Lines.BeginUpdate;
  try
    memText.Clear;

    Shown := ALines.Count;
    FTextTruncated := Shown > MaxTextLines;
    if FTextTruncated then
      Shown := MaxTextLines;

    for I := 0 to Shown - 1 do
      memText.Lines.Add(ALines[I]);

    if FTextTruncated then
    begin
      memText.Lines.Add('');
      memText.Lines.Add(Format('--- truncated: showing %d of %d lines ---',
        [MaxTextLines, ALines.Count]));
    end;
  finally
    memText.Lines.EndUpdate;
  end;
  memText.SelStart := 0;
end;

{ Rebuilds the chart from a document already known to be tabular. Takes the
  layout from the classification so the series can never disagree with the
  decision that put us on the Chart tab. }
procedure TframeColumnarDataViewer.BuildSeries(ALines: TStrings;
  const AClassification: TColumnarClassification);
var
  I, J: Integer;
  Line: string;
  Parts: TArray<string>;
  XVal, YVal: Double;
  Series: TFastLineSeries;
  HeaderSkipped, DataStarted: Boolean;
begin
  for J := 1 to AClassification.ColCount - 1 do
  begin
    Series := TFastLineSeries.Create(Chart);
    Series.ParentChart := Chart;
    Series.LinePen.Width := 2;
    Series.LinePen.Color := SeriesColors[(J - 1) mod Length(SeriesColors)];

    if AClassification.HasHeader and (J < Length(AClassification.ColumnNames)) then
      Series.Title := AClassification.ColumnNames[J]
    else
      Series.Title := 'Column ' + IntToStr(J);
  end;

  if AClassification.HasHeader and (Length(AClassification.ColumnNames) > 0) then
  begin
    Chart.BottomAxis.Title.Caption := AClassification.ColumnNames[0];
    if Length(AClassification.ColumnNames) > 1 then
      Chart.LeftAxis.Title.Caption := AClassification.ColumnNames[1]
    else
      Chart.LeftAxis.Title.Caption := 'Value';
  end
  else
  begin
    Chart.BottomAxis.Title.Caption := 'X';
    Chart.LeftAxis.Title.Caption := 'Value';
  end;

  Chart.Legend.Visible := (AClassification.ColCount > 2);

  HeaderSkipped := not AClassification.HasHeader;
  DataStarted := False;

  for I := 0 to ALines.Count - 1 do
  begin
    Line := ALines[I];
    if IsCommentLine(Line) then
      Continue;

    if not DataStarted then
    begin
      if not HeaderSkipped then
      begin
        HeaderSkipped := True;
        Continue;
      end;
      DataStarted := True;
    end;

    Parts := SplitLine(Line, AClassification.Delimiter);
    if Length(Parts) < 2 then
      Continue;
    if not TryStrToFloat(Parts[0], XVal) then
      Continue;

    for J := 1 to AClassification.ColCount - 1 do
      if (J < Length(Parts)) and TryStrToFloat(Parts[J], YVal) then
        (Chart.Series[J - 1] as TFastLineSeries).AddXY(XVal, YVal);
  end;
end;

procedure TframeColumnarDataViewer.LoadFromFile(const FileName: string);
var
  Lines: TStringList;
  Classification: TColumnarClassification;
begin
  FFileName := FileName;
  FRowCount := 0;
  FColCount := 0;
  FLineCount := 0;
  FByteCount := 0;
  FDelimiterName := '';
  FIsTabular := False;
  FTextTruncated := False;
  FTableText := '';
  FTableNames := nil;
  FTableRows := nil;
  SetLength(FColumnNames, 0);

  ClearSeries;
  Chart.AutoRepaint := False;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    FLineCount := Lines.Count;
    FByteCount := FileSizeOf(FileName);

    Classification := ClassifyColumnarText(Lines);
    FIsTabular      := Classification.IsTabular;
    FDelimiterName  := Classification.DelimiterName;
    FColumnNames    := Classification.ColumnNames;
    FColCount       := Classification.ColCount;
    FRowCount       := Classification.RowCount;

    FillTextView(Lines);

    if FIsTabular then
    begin
      FTableNames := ColumnarTableNames(Classification);
      FTableRows := ColumnarTableRows(Lines, Classification);
      FTableText := ColumnarTableToText(FTableNames, FTableRows);
      BuildSeries(Lines, Classification);
    end;
  finally
    Lines.Free;
    ApplyChartTheme(Chart);
    ApplyTextTheme;
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;

  if FIsTabular then
    Pages.TabIndex := TAB_CHART
  else
    Pages.TabIndex := TAB_TEXT;
  Cards.ActiveCardIndex := Pages.TabIndex;

  UpdateStatus;
end;

procedure TframeColumnarDataViewer.PagesChange(Sender: TObject);
begin
  Cards.ActiveCardIndex := Pages.TabIndex;
end;


function TframeColumnarDataViewer.ActiveContent: string;
begin
  if Pages.TabIndex = TAB_TEXT then
    Exit(memText.Lines.Text);

  Result := FTableText;
end;

function TframeColumnarDataViewer.TextPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  I, Y, LineH, Shown: Integer;
begin
  Result := nil;
  if memText.Lines.Count = 0 then
    Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    Large.Canvas.Brush.Color := ThemePanelColor;
    Large.Canvas.FillRect(Rect(0, 0, 800, 600));
    Large.Canvas.Font.Name := memText.Font.Name;
    Large.Canvas.Font.Size := memText.Font.Size;
    Large.Canvas.Font.Color := ThemeTextColor;

    LineH := Large.Canvas.TextHeight('Wg') + 2;
    Shown := 600 div LineH;
    if Shown > memText.Lines.Count then
      Shown := memText.Lines.Count;

    Y := 4;
    for I := 0 to Shown - 1 do
    begin
      Large.Canvas.TextOut(4, Y, memText.Lines[I]);
      Y := Y + LineH;
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

function TframeColumnarDataViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
begin
  // A text file has no chart to snapshot; without this its tree preview would
  // stay blank even though the viewer now shows it fine.
  if not FIsTabular then
    Exit(TextPreviewBitmap(MaxW, MaxH));

  Result := nil;
  if Chart.SeriesCount = 0 then
    Exit;
  if Chart.Series[0].Count = 0 then
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

{ Structured extraction for non-tabular files. Tabular ones return nothing —
  their content is the chart, which callers read through the columnar tools. }
function TframeColumnarDataViewer.GetDetailedInfo: string;
var
  Obj: TJSONObject;
  Lines: TStringList;
  Body: string;
  Truncated: Boolean;
begin
  Result := '';
  if FIsTabular or (FFileName = '') or not FileExists(FFileName) then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FFileName);
    Body := Lines.Text;
  finally
    Lines.Free;
  end;

  Truncated := Length(Body) > MaxDetailChars;
  if Truncated then
    Body := Copy(Body, 1, MaxDetailChars);

  Obj := TJSONObject.Create;
  try
    Obj.AddPair('kind', 'text');
    Obj.AddPair('line_count', TJSONNumber.Create(FLineCount));
    Obj.AddPair('byte_count', TJSONNumber.Create(FByteCount));
    Obj.AddPair('truncated', TJSONBool.Create(Truncated));
    Obj.AddPair('text', Body);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure TframeColumnarDataViewer.btnCopyClick(Sender: TObject);
begin
  ClipBoard.AsText := ActiveContent;
end;

procedure TframeColumnarDataViewer.btnSaveClick(Sender: TObject);
var
  List: TStringList;
begin
  if Pages.TabIndex = TAB_TEXT then
  begin
    dlgSave.DefaultExt := '.txt';
    dlgSave.FilterIndex := 3;
  end
  else
  begin
    dlgSave.DefaultExt := '.dat';
    dlgSave.FilterIndex := 1;
  end;

  if not dlgSave.Execute then
    Exit;

  List := TStringList.Create;
  try
    List.Text := ActiveContent;
    List.SaveToFile(dlgSave.FileName, TEncoding.UTF8);
  finally
    List.Free;
  end;
end;


procedure TframeColumnarDataViewer.ChartMouseWheel(Sender: TObject;
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

procedure TframeColumnarDataViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  XVal, YVal: Double;
begin
  XVal := Chart.BottomAxis.CalcPosPoint(X);
  YVal := Chart.LeftAxis.CalcPosPoint(Y);
  Status.SimpleCaption := Format('%s  |  Cursor: %.4g, %.4g',
    [FStatusBase, XVal, YVal]);
end;

procedure TframeColumnarDataViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;

end.
