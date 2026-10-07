unit frm_Analysis;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.CheckLst, Vcl.Clipbrd,
  RzButton, RzPanel, RzLabel,
  System.Generics.Collections,
  VCLTee.Chart, VCLTee.Series,
  unit_Item, unit_ItemTypes, unit_ValueType, VCLTee.TeEngine, VCLTee.TeeProcs,
  RzSplit;

type
  TAnalysisPoint = record
    ProcTitle: string;
    XVal, YVal: Double;
  end;

  TfrmAnalysis = class(TForm)
    pnlToolbar: TRzPanel;
    lblXAxis:   TRzLabel;
    cbXAxis:    TComboBox;
    lblYAxis:   TRzLabel;
    cbYAxis:    TComboBox;
    btnPlot:    TRzBitBtn;
    pnlChart:     TRzPanel;
    pnlBottom:    TRzPanel;
    btnClose:     TRzBitBtn;
    btnCopyData:  TRzBitBtn;
    btnCopyChart: TRzBitBtn;
    RzSplitter1: TRzSplitter;
    pnlProcs: TRzPanel;
    clbProcs: TCheckListBox;
    pnlProcBtns: TRzPanel;
    btnAll: TRzBitBtn;
    btnNone: TRzBitBtn;
    chtMain: TChart;
    serData: TPointSeries;
    serTrend: TLineSeries;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnPlotClick(Sender: TObject);
    procedure btnAllClick(Sender: TObject);
    procedure btnNoneClick(Sender: TObject);
    procedure btnCopyDataClick(Sender: TObject);
    procedure btnCopyChartClick(Sender: TObject);
  private
    FProjectID, FFolderID: Integer;
    FProcIDs:     TList<Integer>;             // Proc IDs parallel to clbProcs items
    FXTypes:      TList<TValueType>;          // unique condition types (NOT owned)
    FYTypes:      TList<TValueType>;          // unique result types (NOT owned)
    FPlottedData: TArray<TAnalysisPoint>;     // cached for CSV export
    procedure PopulateCombos(AllItems: TItems);
    procedure PlotData;
    procedure AddRegressionLine(const Pts: TArray<TAnalysisPoint>);
  public
    class procedure Execute(const AProjectID, AFolderID: Integer);
  end;

implementation

uses
  Vcl.Graphics,
  unit_DataModel,
  unit_NotebookSettings,
  unit_ELNThemeHelper;

{$R *.dfm}

{ TfrmAnalysis }

procedure TfrmAnalysis.FormCreate(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  FProcIDs := TList<Integer>.Create;
  FXTypes  := TList<TValueType>.Create;
  FYTypes  := TList<TValueType>.Create;

  LSettings := TNotebookSettings.Create;
  try
    RzSplitter1.Position := LSettings.LoadUIValue('frmAnalysis', 'RzSplitter1', RzSplitter1.Position);
  finally
    LSettings.Free;
  end;

  ApplyChartTheme(chtMain);
end;

procedure TfrmAnalysis.FormDestroy(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  LSettings := TNotebookSettings.Create;
  try
    LSettings.SaveUIValue('frmAnalysis', 'RzSplitter1', RzSplitter1.Position);
  finally
    LSettings.Free;
  end;

  FProcIDs.Free;
  FXTypes.Free;  // does NOT free TValueType objects (owned by Aurelius)
  FYTypes.Free;
end;

class procedure TfrmAnalysis.Execute(const AProjectID, AFolderID: Integer);
var
  Dlg: TfrmAnalysis;
  AllItems: TItems;
begin
  Dlg := TfrmAnalysis.Create(Application.MainForm);
  try
    Dlg.FProjectID := AProjectID;
    Dlg.FFolderID  := AFolderID;
    Model.Items.AssignProject(AProjectID, AFolderID);
    AllItems := Model.Items.List;
    try
      Dlg.PopulateCombos(AllItems);
    finally
      AllItems.Free;
    end;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmAnalysis.PopulateCombos(AllItems: TItems);

  function AlreadyIn(List: TList<TValueType>; VT: TValueType): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    for i := 0 to List.Count - 1 do
      if List[i].Id = VT.Id then
        Exit(True);
  end;

var
  Item: TItem;
  Val:  TValue;
  VT:   TValueType;
begin
  FProcIDs.Clear;
  clbProcs.Items.Clear;
  for Item in AllItems do
    if Item.Level = TItemLevel.Proc then
    begin
      FProcIDs.Add(Item.Id);
      clbProcs.Items.Add(Item.Title);
      clbProcs.Checked[clbProcs.Count - 1] := True;
    end;

  FXTypes.Clear; FYTypes.Clear;
  cbXAxis.Items.Clear; cbYAxis.Items.Clear;
  for Item in AllItems do
    for Val in Item.Values do
    begin
      if not Assigned(Val.ValueType) then Continue;
      VT := Val.ValueType;
      if (Val.RecType = EXP_CONDITION) and not AlreadyIn(FXTypes, VT) then
      begin
        FXTypes.Add(VT);
        cbXAxis.Items.Add(VT.Symbol + ' — ' + VT.Title + ' (' + VT.Units + ')');
      end;
      if (Val.RecType = TEST_RESULT) and not AlreadyIn(FYTypes, VT) then
      begin
        FYTypes.Add(VT);
        cbYAxis.Items.Add(VT.Symbol + ' — ' + VT.Title + ' (' + VT.Units + ')');
      end;
    end;
  if cbXAxis.Items.Count > 0 then cbXAxis.ItemIndex := 0;
  if cbYAxis.Items.Count > 0 then cbYAxis.ItemIndex := 0;
  btnPlot.Enabled := (cbXAxis.Items.Count > 0) and (cbYAxis.Items.Count > 0);
end;

procedure TfrmAnalysis.PlotData;
var
  AllItems:   TItems;
  ChildMap:   TDictionary<Integer, TList<TItem>>;
  Procs:      TList<TItem>;
  DataPoints: TList<TAnalysisPoint>;
  Item, ChildItem, ActionItem: TItem;
  Val:        TValue;
  SelXTypeId, SelYTypeId: Integer;
  XFound: Boolean;
  XVal, YSum: Double;
  YCount: Integer;
  Pt: TAnalysisPoint;
  ChildList: TList<TItem>;
begin
  if (cbXAxis.ItemIndex < 0) or (cbYAxis.ItemIndex < 0) then Exit;
  SelXTypeId := FXTypes[cbXAxis.ItemIndex].Id;
  SelYTypeId := FYTypes[cbYAxis.ItemIndex].Id;

  chtMain.BottomAxis.Title.Caption :=
    FXTypes[cbXAxis.ItemIndex].Symbol + ' (' + FXTypes[cbXAxis.ItemIndex].Units + ')';
  chtMain.LeftAxis.Title.Caption :=
    FYTypes[cbYAxis.ItemIndex].Symbol + ' (' + FYTypes[cbYAxis.ItemIndex].Units + ')';

  serData.Clear;
  serTrend.Clear;

  Model.Items.AssignProject(FProjectID, FFolderID);
  AllItems := Model.Items.List;

  Procs      := TList<TItem>.Create;
  ChildMap   := TDictionary<Integer, TList<TItem>>.Create;
  DataPoints := TList<TAnalysisPoint>.Create;
  try
    // Partition items into Procs and a parent→children map
    for Item in AllItems do
      if Item.Level = TItemLevel.Proc then
        Procs.Add(Item)
      else
      begin
        if not ChildMap.ContainsKey(Item.Parent) then
          ChildMap.Add(Item.Parent, TList<TItem>.Create);
        ChildMap[Item.Parent].Add(Item);
      end;

    // Collect (X, Y) per selected Proc
    for Item in Procs do
    begin
      var ChkIdx := FProcIDs.IndexOf(Item.Id);
      if (ChkIdx < 0) or not clbProcs.Checked[ChkIdx] then Continue;

      // X: EXP_CONDITION value directly on the Proc
      XVal := 0;
      XFound := False;
      for Val in Item.Values do
        if (Val.RecType = EXP_CONDITION) and
           Assigned(Val.ValueType) and (Val.ValueType.Id = SelXTypeId) then
        begin
          XVal := Val.Value;
          XFound := True;
          Break;
        end;
      if not XFound then Continue;

      // Y: average TEST_RESULT across all descendant Actions (including sub-actions)
      YSum := 0; YCount := 0;
      if ChildMap.TryGetValue(Item.Id, ChildList) then
        for ChildItem in ChildList do
        begin
          if ChildItem.Level = TItemLevel.Item then  // Specimen level
          begin
            var ActionList: TList<TItem>;
            if ChildMap.TryGetValue(ChildItem.Id, ActionList) then
              for ActionItem in ActionList do
                if ActionItem.Level = TItemLevel.Action then
                begin
                  for Val in ActionItem.Values do
                    if (Val.RecType = TEST_RESULT) and
                       Assigned(Val.ValueType) and (Val.ValueType.Id = SelYTypeId) then
                    begin
                      YSum := YSum + Val.Value;
                      Inc(YCount);
                    end;
                  // Sub-actions (e.g., XRR Simulation under XRR)
                  var SubList: TList<TItem>;
                  if ChildMap.TryGetValue(ActionItem.Id, SubList) then
                    for var SubAction in SubList do
                      if SubAction.Level = TItemLevel.Action then
                        for Val in SubAction.Values do
                          if (Val.RecType = TEST_RESULT) and
                             Assigned(Val.ValueType) and (Val.ValueType.Id = SelYTypeId) then
                          begin
                            YSum := YSum + Val.Value;
                            Inc(YCount);
                          end;
                end;
          end
          else if ChildItem.Level = TItemLevel.Action then
            // Direct Action child of Proc (no Specimen level)
            for Val in ChildItem.Values do
              if (Val.RecType = TEST_RESULT) and
                 Assigned(Val.ValueType) and (Val.ValueType.Id = SelYTypeId) then
              begin
                YSum := YSum + Val.Value;
                Inc(YCount);
              end;
        end;

      if YCount = 0 then Continue;

      serData.AddXY(XVal, YSum / YCount, Item.Title);
      Pt.ProcTitle := Item.Title;
      Pt.XVal := XVal;
      Pt.YVal := YSum / YCount;
      DataPoints.Add(Pt);
    end;

    FPlottedData := DataPoints.ToArray;
    if Length(FPlottedData) >= 2 then
      AddRegressionLine(FPlottedData);
    btnCopyData.Enabled  := Length(FPlottedData) > 0;
    btnCopyChart.Enabled := True;
  finally
    for var KV in ChildMap do
      KV.Value.Free;
    ChildMap.Free;
    Procs.Free;
    DataPoints.Free;
    AllItems.Free;
  end;
end;

procedure TfrmAnalysis.AddRegressionLine(const Pts: TArray<TAnalysisPoint>);
var
  n: Integer;
  SumX, SumY, SumXY, SumX2, Denom, Slope, Intercept, XMin, XMax: Double;
  i: Integer;
begin
  n := Length(Pts);
  if n < 2 then Exit;
  SumX := 0; SumY := 0; SumXY := 0; SumX2 := 0;
  XMin := Pts[0].XVal; XMax := Pts[0].XVal;
  for i := 0 to n - 1 do
  begin
    SumX  := SumX  + Pts[i].XVal;
    SumY  := SumY  + Pts[i].YVal;
    SumXY := SumXY + Pts[i].XVal * Pts[i].YVal;
    SumX2 := SumX2 + Pts[i].XVal * Pts[i].XVal;
    if Pts[i].XVal < XMin then XMin := Pts[i].XVal;
    if Pts[i].XVal > XMax then XMax := Pts[i].XVal;
  end;
  Denom := n * SumX2 - SumX * SumX;
  if Abs(Denom) < 1e-12 then Exit;
  Slope     := (n * SumXY - SumX * SumY) / Denom;
  Intercept := (SumY - Slope * SumX) / n;
  serTrend.AddXY(XMin, Slope * XMin + Intercept);
  serTrend.AddXY(XMax, Slope * XMax + Intercept);
end;

procedure TfrmAnalysis.btnPlotClick(Sender: TObject);
begin
  PlotData;
end;

procedure TfrmAnalysis.btnAllClick(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to clbProcs.Count - 1 do
    clbProcs.Checked[i] := True;
end;

procedure TfrmAnalysis.btnNoneClick(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to clbProcs.Count - 1 do
    clbProcs.Checked[i] := False;
end;

procedure TfrmAnalysis.btnCopyDataClick(Sender: TObject);
var
  SB:    TStringBuilder;
  XType, YType: TValueType;
  FS:    TFormatSettings;
  Pt:    TAnalysisPoint;
begin
  if Length(FPlottedData) = 0 then Exit;
  XType := FXTypes[cbXAxis.ItemIndex];
  YType := FYTypes[cbYAxis.ItemIndex];
  FS    := TFormatSettings.Invariant;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('Proc,%s (%s),%s (%s)',
      [XType.Symbol, XType.Units, YType.Symbol, YType.Units]));
    for Pt in FPlottedData do
      SB.AppendLine(Format('"%s",%s,%s', [
        Pt.ProcTitle,
        FloatToStr(Pt.XVal, FS),
        FloatToStr(Pt.YVal, FS)]));
    Clipboard.AsText := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TfrmAnalysis.btnCopyChartClick(Sender: TObject);
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Width  := chtMain.Width;
    Bmp.Height := chtMain.Height;
    chtMain.PaintTo(Bmp.Canvas.Handle, 0, 0);
    Clipboard.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
