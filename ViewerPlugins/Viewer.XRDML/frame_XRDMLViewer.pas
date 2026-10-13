unit frame_XRDMLViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton, xml.XMLDoc, XML.XMLIntf,
  unit_ELNPluginCore, unit_ELNPluginTypes;

type

  TframeXRDMLViewer = class(TFrame)
    Status: TRzStatusBar;
    dlgSave: TSaveDialog;
    Chart: TChart;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    Series1: TFastLineSeries;
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FMax: Integer;
    FStatusBase: string;
    FPnlMeta: TPanel;
    FLblInfo: TLabel;
    FMetaJSON: string;
    procedure SeriesToText(List: TStringList);
    procedure CreateInfoPanel;
    function ExtractMetadata(XML: IXMLDocument): string;
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
  ClipBrd, System.Generics.Collections, System.Math, System.StrUtils, System.JSON,
  unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

constructor TframeXRDMLViewer.Create(AOwner: TComponent);
begin
  inherited;
  CreateInfoPanel;
  Chart.OnMouseWheel := ChartMouseWheel;
  Chart.OnMouseMove := ChartMouseMove;
  Chart.OnDblClick := ChartDblClick;
end;

procedure TframeXRDMLViewer.CreateInfoPanel;
var
  PPI: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, PPI, 96);
  end;

begin
  PPI := CurrentPPI;

  FPnlMeta := TPanel.Create(Self);
  FPnlMeta.Parent := Self;
  FPnlMeta.Align := alRight;
  FPnlMeta.Width := S(220);
  FPnlMeta.BevelOuter := bvNone;
  FPnlMeta.Visible := False;

  FLblInfo := TLabel.Create(Self);
  FLblInfo.Parent := FPnlMeta;
  FLblInfo.AlignWithMargins := True;
  FLblInfo.Margins.Left := S(8);
  FLblInfo.Margins.Top := S(8);
  FLblInfo.Margins.Right := S(8);
  FLblInfo.Margins.Bottom := S(8);
  FLblInfo.Align := alClient;
  FLblInfo.AutoSize := False;
  FLblInfo.WordWrap := True;
  FLblInfo.Caption := '';
end;

function TframeXRDMLViewer.ExtractMetadata(XML: IXMLDocument): string;
var
  SL: TStringList;
  JMeta: TJSONObject;
  Root, Measurement, Beam, Node, SubNode: IXMLNode;
  I: Integer;
  S, TensionStr, CurrentStr: string;

  procedure AddLine(const Name, Value: string);
  begin
    if Value <> '' then
    begin
      SL.Add(Name + ': ' + Value);
      JMeta.AddPair(Name, Value);
    end;
  end;

  function FindChild(Parent: IXMLNode; const Name: string): IXMLNode;
  begin
    Result := nil;
    if Parent <> nil then
      Result := Parent.ChildNodes.FindNode(Name);
  end;

  function NodeText(Parent: IXMLNode; const Name: string): string;
  var
    N: IXMLNode;
  begin
    Result := '';
    N := FindChild(Parent, Name);
    if (N <> nil) and not VarIsNull(N.NodeValue) then
      Result := Trim(VarToStr(N.NodeValue));
  end;

begin
  Result := '';
  FMetaJSON := '';
  SL := TStringList.Create;
  JMeta := TJSONObject.Create;
  try
    Root := XML.DocumentElement;
    Node := FindChild(Root, 'comment');
    if Node <> nil then
      for I := 0 to Node.ChildNodes.Count - 1 do
      begin
        S := VarToStr(Node.ChildNodes[I].NodeValue);
        if S.StartsWith('Diffractometer system=') then
          AddLine('Instrument', S.Substring(Length('Diffractometer system=')));
        if S.StartsWith('Goniometer=') then
        begin
          S := S.Substring(Length('Goniometer='));
          if Pos(';', S) > 0 then
            S := Copy(S, 1, Pos(';', S) - 1);
          AddLine('Goniometer', Trim(S));
        end;
      end;

    Node := FindChild(Root, 'sample');
    if Node <> nil then
    begin
      S := NodeText(Node, 'name');
      AddLine('Sample', S);
    end;

    Measurement := FindChild(Root, 'xrdMeasurement');
    if Measurement = nil then
    begin
      Result := SL.Text;
      FMetaJSON := JMeta.ToJSON;
      Exit;
    end;

    TensionStr := '';
    CurrentStr := '';
    Node := FindChild(Measurement, 'usedWavelength');
    if Node <> nil then
    begin
      S := VarToStr(Node.Attributes['intended']);
      SubNode := FindChild(Node, 'kAlpha1');
      if SubNode <> nil then
      begin
        AddLine('Wavelength', Trim(VarToStr(SubNode.NodeValue)) + ' '#197 +
          IfThen(S <> '', ' (' + S + ')'));
        JMeta.AddPair('wavelength_A', JNum(
          StrToFloatDef(Trim(VarToStr(SubNode.NodeValue)), 0)));
      end;
    end;

    Beam := FindChild(Measurement, 'incidentBeamPath');
    if Beam <> nil then
    begin
      Node := FindChild(Beam, 'xRayTube');
      if Node <> nil then
      begin
        S := NodeText(Node, 'anodeMaterial');
        AddLine('Anode', S);
        S := '';
        SubNode := FindChild(Node, 'tension');
        if SubNode <> nil then
        begin
          TensionStr := Trim(VarToStr(SubNode.NodeValue));
          S := TensionStr + ' kV';
          JMeta.AddPair('tension_kV', JNum(
            StrToFloatDef(TensionStr, 0)));
        end;
        SubNode := FindChild(Node, 'current');
        if SubNode <> nil then
        begin
          CurrentStr := Trim(VarToStr(SubNode.NodeValue));
          S := S + ' / ' + CurrentStr + ' mA';
          JMeta.AddPair('current_mA', JNum(
            StrToFloatDef(CurrentStr, 0)));
        end;
        AddLine('Power', Trim(S));
      end;
    end;

    Beam := FindChild(Measurement, 'diffractedBeamPath');
    if Beam <> nil then
    begin
      Node := FindChild(Beam, 'detector');
      if Node <> nil then
      begin
        S := VarToStr(Node.Attributes['name']);
        if (Pos('PIXcel', S) > 0) and (Pos(' detector', S) > 0) then
          S := Copy(S, 1, Pos(' detector', S) - 1);
        AddLine('Detector', S);
      end;
    end;

    Node := FindChild(Measurement, 'scan');
    if Node <> nil then
    begin
      S := VarToStr(Node.Attributes['scanAxis']);
      AddLine('Scan axis', S);
      S := VarToStr(Node.Attributes['mode']);
      AddLine('Scan mode', S);

      SubNode := FindChild(Node, 'header');
      if SubNode <> nil then
      begin
        S := NodeText(SubNode, 'startTimeStamp');
        if Length(S) >= 10 then
          AddLine('Date', Copy(S, 1, 10));
      end;
    end;

    JMeta.AddPair('dataPoints', TJSONNumber.Create(Series1.Count));
    FMetaJSON := JMeta.ToJSON;
    Result := SL.Text;
  finally
    SL.Free;
    JMeta.Free;
  end;
end;

procedure TframeXRDMLViewer.LoadFromFile(const FileName: string);
var
  Measurement, scan, dataPoints, position, countsNode: IXMLNode;
  XML: IXMLDocument;
  Start, Stop, Time: single;
  CountsStr: string;
  count, Int: integer;
  delta: single;
  StartPos, SpacePos, Len: Integer;
  MetaText: string;
begin
  Start := 0;
  Stop  := 0;
  Series1.Clear;
  FMetaJSON := '';
  Chart.AutoRepaint := False;
  Series1.BeginUpdate;
  XML := TXMLDocument.Create(nil);
  try
    // XRDML is a structured XML format that never uses DTDs or external
    // entities. Strip poResolveExternals so a crafted file containing an
    // XXE payload (<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///...">]>)
    // cannot exfiltrate local files via metadata rendering.
    XML.ParseOptions := XML.ParseOptions - [poResolveExternals];
    XML.LoadFromFile(FileName);
    XML.Active := True;

    Measurement := XML.DocumentElement.ChildNodes['xrdMeasurement'];
    scan := Measurement.ChildNodes['scan'];
    dataPoints := Scan.ChildNodes.FindNode('dataPoints');
    if dataPoints <> nil then
    begin
      position := dataPoints.ChildNodes[0];
      if position.Attributes['axis'] = '2Theta' then
      begin
        Start := position.ChildNodes['startPosition'].NodeValue;
        Stop  := position.ChildNodes['endPosition'].NodeValue;
      end;
      Time := dataPoints.ChildNodes['commonCountingTime'].NodeValue;

      countsNode := dataPoints.ChildNodes.FindNode('counts');
      if countsNode = nil then
        countsNode := dataPoints.ChildNodes.FindNode('intensities');
      CountsStr := Trim(countsNode.NodeValue);

      count := CountsStr.CountChar(' ');
      delta := (Stop - Start) / count;
      Len := Length(CountsStr);

      FMax := 0;
      StartPos := 1;
      while StartPos <= Len do
      begin
        SpacePos := StartPos;
        while (SpacePos <= Len) and (CountsStr[SpacePos] <> ' ') do
          Inc(SpacePos);

        Int := StrToInt(Copy(CountsStr, StartPos, SpacePos - StartPos));
        Series1.AddXY(Start, Int / Time);
        Start := Start + Delta;
        if FMax < Int then
          FMax := Int;
        StartPos := SpacePos + 1;
      end;
    end;
    MetaText := ExtractMetadata(XML);
  finally
    Series1.EndUpdate;
    ApplyChartTheme(Chart);
    Chart.AutoRepaint := True;
    Chart.Repaint;
  end;

  if MetaText <> '' then
  begin
    FLblInfo.Caption := MetaText;
    FPnlMeta.Visible := True;
  end
  else
    FPnlMeta.Visible := False;

  FStatusBase := Format('%s  |  %d points', [ExtractFileName(FileName), Series1.Count]);
  Status.SimpleCaption := FStatusBase;
end;

procedure TframeXRDMLViewer.SeriesToText(List: TStringList);
var
  i: integer;
  Divisor: Double;
begin
  List.Add('2Theta' + #9 + 'Intensity');
  List.Add('deg' + #9 + '');
  List.Add('');
  Divisor := IfThen(FMax > 0, FMax, 1);
  for i := 0 to Series1.Count - 1 do
    List.Add(FloatToStrF(Series1.XValues[i], ffFixed, 5, 3) + #9 +
             FloatToStrF(Series1.YValues[i] / Divisor, ffExponent, 5, 4));
end;

function TframeXRDMLViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
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

procedure TframeXRDMLViewer.btnCopyClick(Sender: TObject);
var
  List: TStringList;
begin
  try
    List := TStringList.Create;
    SeriesToText(List);
    ClipBoard.AsText := List.Text;
  finally
    FreeAndNil(List);
  end;
end;

procedure TframeXRDMLViewer.btnSaveClick(Sender: TObject);
var
  List: TStringList;
begin
  if dlgSave.Execute then
  begin
    try
      List := TStringList.Create;
      SeriesToText(List);
      List.SaveToFile(dlgSave.FileName);
    finally
      FreeAndNil(List);
    end;
  end;
end;


procedure TframeXRDMLViewer.ChartMouseWheel(Sender: TObject;
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

procedure TframeXRDMLViewer.ChartMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  XVal, YVal: Double;
begin
  XVal := Chart.BottomAxis.CalcPosPoint(X);
  YVal := Chart.LeftAxis.CalcPosPoint(Y);
  Status.SimpleCaption := Format('%s  |  Cursor: %.3f'#176', %.1f cps',
    [FStatusBase, XVal, YVal]);
end;

procedure TframeXRDMLViewer.ChartDblClick(Sender: TObject);
begin
  Chart.BottomAxis.Automatic := True;
  Chart.LeftAxis.Automatic := True;
end;

function TframeXRDMLViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  J: TJSONObject;
  V: TJSONValue;

  procedure AddFromJSON(const AKey, AName, AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean = False);
  begin
    V := J.FindValue(AKey);
    if (V <> nil) and (V is TJSONNumber) then
    begin
      KV.Name := AName;
      KV.Value := TJSONNumber(V).AsDouble;
      KV.Units := AUnits;
      KV.RecType := ARecType;
      KV.IsKey := AIsKey;
      List.Add(KV);
    end;
  end;

begin
  Result := nil;
  if FMetaJSON = '' then
    Exit;

  J := TJSONObject.ParseJSONValue(FMetaJSON) as TJSONObject;
  if J = nil then
    Exit;

  List := TList<TPluginKeyValue>.Create;
  try
    AddFromJSON('wavelength_A', 'Wavelength', 'A', prCondition, True);
    AddFromJSON('tension_kV', 'Tube Voltage', 'kV', prCondition, True);
    AddFromJSON('current_mA', 'Tube Current', 'mA', prCondition, True);
    Result := List.ToArray;
  finally
    List.Free;
    J.Free;
  end;
end;

function TframeXRDMLViewer.GetDetailedInfo: string;
begin
  Result := FMetaJSON;
end;

end.
