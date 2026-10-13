unit test_ViewerValues;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, System.Win.ComObj, Vcl.Forms, Winapi.ActiveX, unit_ELNPluginTypes,
  frame_XRDMLViewer, frame_LAMMPSViewer, frame_DSCViewer;

type
  [TestFixture]
  TViewerValueTests = class
  private
    FDir: string;
    FHost: TForm;
    function TextFile(const Name, Text: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure XRDML_ExtractedPointCountMatchesLoadedScan;
    [Test] procedure DSC_WarmUpUsesMinutesAndProcessTimesUseSeconds;
    [Test] procedure LAMMPS_CrossSectionUsesCartesianTriclinicEnvelope;
  end;

implementation

procedure TViewerValueTests.Setup;
begin
  OleCheck(CoInitialize(nil));
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ViewerValues_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FHost := TForm.CreateNew(nil);
end;

procedure TViewerValueTests.TearDown;
begin
  FHost.Free;
  TDirectory.Delete(FDir, True);
  CoUninitialize;
end;

function TViewerValueTests.TextFile(const Name, Text: string): string;
begin
  Result := TPath.Combine(FDir, Name);
  TFile.WriteAllText(Result, Text, TEncoding.UTF8);
end;

procedure TViewerValueTests.XRDML_ExtractedPointCountMatchesLoadedScan;
var
  Frame: TframeXRDMLViewer;
  JSON: TJSONObject;
begin
  Frame := TframeXRDMLViewer.Create(FHost);
  Frame.Parent := FHost;
  Frame.LoadFromFile(TextFile('scan.xrdml',
    '<xrdMeasurements><xrdMeasurement><scan scanAxis="2Theta" mode="Continuous">' +
    '<dataPoints><positions axis="2Theta"><startPosition>10</startPosition>' +
    '<endPosition>12</endPosition></positions><commonCountingTime>2</commonCountingTime>' +
    '<counts>20 40 60</counts></dataPoints></scan></xrdMeasurement></xrdMeasurements>'));
  Assert.AreEqual(3, Frame.Series1.Count);
  Assert.AreEqual(Double(30), Frame.Series1.YValue[2], 1E-9);
  JSON := TJSONObject.ParseJSONValue(Frame.GetDetailedInfo) as TJSONObject;
  try
    Assert.AreEqual(3, JSON.GetValue<Integer>('dataPoints'));
  finally
    JSON.Free;
  end;
end;

procedure TViewerValueTests.DSC_WarmUpUsesMinutesAndProcessTimesUseSeconds;
var
  Frame: TframeDSCViewer;
  Values: TArray<TPluginKeyValue>;
begin
  Frame := TframeDSCViewer.Create(FHost);
  Frame.Parent := FHost;
  Frame.Editor.Lines.Text := 'var wArMuPtImE 45' + sLineBreak +
    'var CleaningTime 120' + sLineBreak +
    'var TimeW 15.0275' + sLineBreak +
    'start' + sLineBreak + 'wait wArMuPtImE';
  Values := Frame.GetKeyValues;
  Assert.AreEqual(3, Length(Values));
  Assert.AreEqual('Warm-up', Values[0].Description);
  Assert.AreEqual(Double(45), Values[0].Value, 1E-9);
  Assert.AreEqual('min', Values[0].Units);
  Assert.AreEqual('Cleaning', Values[1].Description);
  Assert.AreEqual(Double(120), Values[1].Value, 1E-9);
  Assert.AreEqual('s', Values[1].Units);
  Assert.AreEqual(Double(15.0275), Values[2].Value, 1E-9);
  Assert.AreEqual('s', Values[2].Units);
end;

procedure TViewerValueTests.LAMMPS_CrossSectionUsesCartesianTriclinicEnvelope;
var
  Frame: TframeLAMMPSViewer;

  procedure CheckSlab(const YBounds, YZ, MidY, OtherY, OutsideY: string);
  begin
    Frame.chkCrossSection.Checked := False;
    Frame.LoadFromFile(TextFile('slab.dump',
      'ITEM: TIMESTEP'#13#10'0'#13#10 +
      'ITEM: NUMBER OF ATOMS'#13#10'3'#13#10 +
      'ITEM: BOX BOUNDS xy xz yz pp pp pp'#13#10 +
      '0 10 0'#13#10 + YBounds + ' 0'#13#10 + '0 10 ' + YZ + #13#10 +
      'ITEM: ATOMS id type x y z'#13#10 +
      '1 1 1 ' + MidY + ' 5'#13#10 +
      '2 1 2 ' + OtherY + ' 5'#13#10 +
      '3 1 3 ' + OutsideY + ' 5'));
    Assert.AreEqual(3, Frame.Chart.Series[0].Count);
    Frame.trkSlab.Position := 10;
    Frame.chkCrossSection.Checked := True;
    Assert.AreEqual(1, Frame.Chart.SeriesCount);
    Assert.AreEqual(1, Frame.Chart.Series[0].Count);
    Assert.AreEqual(Double(1), Frame.Chart.Series[0].XValue[0], 1E-9);
    Assert.AreEqual(Double(5), Frame.Chart.Series[0].YValue[0], 1E-9);
  end;

begin
  Frame := TframeLAMMPSViewer.Create(FHost);
  Frame.Parent := FHost;
  CheckSlab('0 20', '10', '10', '5', '12');
  CheckSlab('-10 10', '-10', '0', '5', '2');
  CheckSlab('0 10', '0', '5', '2', '7');
end;

initialization
  TDUnitX.RegisterTestFixture(TViewerValueTests);
end.
