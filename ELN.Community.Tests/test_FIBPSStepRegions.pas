unit test_FIBPSStepRegions;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Math, System.Types, unit_FIBPSData;

type
  [TestFixture]
  TFIBPSStepRegionTests = class
  private
    function Surface(StepNm, RippleUm: Double; Bump, Transpose: Boolean): TFIBPSData;
  public
    [Test] procedure BowedFilmWithEdgeLipGivesTrueStep;
    [Test] procedure DebrisInPlateauDoesNotShiftStep;
    [Test] procedure StepAlongRowsGivesSameValue;
    [Test] procedure BowAndLipWithoutStepReportNoStep;
    [Test] procedure RegionsStayClearOfEdgeBand;
    [Test] procedure GrooveWithTwoWallsIsNotReportedAsStep;
    [Test] procedure CleanStepIsNotLowConfidence;
    [Test] procedure NoisyStepIsLowConfidenceButKeepsItsValue;
    [Test] procedure StepBetweenTheGatesIsLowConfidence;
    [Test] procedure StepBuriedInScatterIsNotReported;
    [Test] procedure LowConfidenceIsOnlyReportedForAutomaticSteps;
    [Test] procedure ScanWithoutStepOrWearReportsNoStepFound;
    [Test] procedure ScanWithWearOrManualRegionsNeverReportsNoStepFound;
  end;

implementation

const
  MapW = 300;
  MapH = 240;
  EdgeX = 150;
  TrueStepUm = 0.040;
  CleanRippleUm = 0.0005;
  NoisyRippleUm = 0.012;
  VeryNoisyRippleUm = 0.020;
  BuriedRippleUm = 0.032;

function TFIBPSStepRegionTests.Surface(StepNm, RippleUm: Double; Bump, Transpose: Boolean): TFIBPSData;
var
  X, Y: Integer;
  Z: Double;
begin
  Result := TFIBPSData.Create;
  if Transpose then
  begin
    Result.PixW := MapH;
    Result.PixH := MapW;
  end
  else
  begin
    Result.PixW := MapW;
    Result.PixH := MapH;
  end;
  SetLength(Result.Heights, MapW * MapH);
  for Y := 0 to MapH - 1 do
    for X := 0 to MapW - 1 do
    begin
      Z := 0.030 * Sqr((X - 0.3 * MapW) / (0.7 * MapW)) + 0.00003 * Y +
        RippleUm * Sin(0.7 * X) * Cos(0.9 * Y);
      if X < EdgeX then
        Z := Z + StepNm / 1000 + 0.020 * Exp(-(EdgeX - X) / 4.0);
      if Bump and (Y >= 100) and (Y < 112) and (X >= 180) and (X < 192) then
        Z := Z + 0.3;
      if Transpose then
        Result.Heights[X * MapH + Y] := Z
      else
        Result.Heights[Y * MapW + X] := Z;
    end;
end;

procedure TFIBPSStepRegionTests.BowedFilmWithEdgeLipGivesTrueStep;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, CleanRippleUm, False, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.AreEqual(TrueStepUm, Res.StepHeight, 0.1 * TrueStepUm);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.DebrisInPlateauDoesNotShiftStep;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, CleanRippleUm, True, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.AreEqual(TrueStepUm, Res.StepHeight, 0.1 * TrueStepUm);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.StepAlongRowsGivesSameValue;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, CleanRippleUm, False, True);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.AreEqual(TrueStepUm, Res.StepHeight, 0.1 * TrueStepUm);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.BowAndLipWithoutStepReportNoStep;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(0, CleanRippleUm, False, False);
  try
    Assert.IsFalse(Data.TryCalcStepHeightEx(Res));
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.RegionsStayClearOfEdgeBand;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, CleanRippleUm, False, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.IsTrue(Res.RectA.Right <= EdgeX - 10, 'region A must stop before the edge lip');
    Assert.IsTrue(Res.RectB.Left >= EdgeX + 10, 'region B must start after the edge');
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.GrooveWithTwoWallsIsNotReportedAsStep;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
  X, Y: Integer;
begin
  Data := TFIBPSData.Create;
  try
    Data.PixW := MapW;
    Data.PixH := MapH;
    SetLength(Data.Heights, MapW * MapH);
    for Y := 0 to MapH - 1 do
      for X := 0 to MapW - 1 do
      begin
        Data.Heights[Y * MapW + X] := 0.030 * Sqr((X - 0.3 * MapW) / (0.7 * MapW)) +
          0.00003 * Y + 0.0005 * Sin(0.7 * X) * Cos(0.9 * Y);
        if (X >= 90) and (X < 210) then
          Data.Heights[Y * MapW + X] := Data.Heights[Y * MapW + X] - 0.4;
      end;
    Assert.IsFalse(Data.TryCalcStepHeightEx(Res),
      'two walls of the same size are a groove, not a step');
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.CleanStepIsNotLowConfidence;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, CleanRippleUm, False, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.IsFalse(Res.LowConfidence);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.NoisyStepIsLowConfidenceButKeepsItsValue;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, NoisyRippleUm, False, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.IsTrue(Res.LowConfidence);
    Assert.AreEqual(TrueStepUm, Res.StepHeight, 0.1 * TrueStepUm);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.StepBetweenTheGatesIsLowConfidence;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, VeryNoisyRippleUm, False, False);
  try
    Assert.IsTrue(Data.TryCalcStepHeightEx(Res));
    Assert.IsTrue(Res.LowConfidence);
    Assert.AreEqual(TrueStepUm, Res.StepHeight, 0.1 * TrueStepUm);
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.StepBuriedInScatterIsNotReported;
var
  Data: TFIBPSData;
  Res: TFIBPSStepResult;
begin
  Data := Surface(TrueStepUm * 1000, BuriedRippleUm, False, False);
  try
    Assert.IsFalse(Data.TryCalcStepHeightEx(Res));
  finally
    Data.Free;
  end;
end;

procedure TFIBPSStepRegionTests.LowConfidenceIsOnlyReportedForAutomaticSteps;
begin
  Assert.IsTrue(fsoLowConfidence =
    FIBPSStepOutcome(True, True, True, True, False, True));
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(True, True, True, False, False, True));
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(True, True, False, True, False, True),
    'a step chosen by hand is not a weak automatic result');
end;

procedure TFIBPSStepRegionTests.ScanWithoutStepOrWearReportsNoStepFound;
begin
  Assert.IsTrue(fsoNoStepFound =
    FIBPSStepOutcome(False, False, True, False, False, True));
end;

procedure TFIBPSStepRegionTests.ScanWithWearOrManualRegionsNeverReportsNoStepFound;
begin
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(False, False, True, False, True, True),
    'a scan with a wear groove has Wear Area');
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(False, False, False, False, False, True),
    'a failed manual selection has its own status');
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(False, True, True, False, True, True),
    'a step that exists but is not extracted because of a wear groove');
  Assert.IsTrue(fsoNone = FIBPSStepOutcome(False, False, True, False, False, False),
    'nothing is loaded');
end;

initialization
  TDUnitX.RegisterTestFixture(TFIBPSStepRegionTests);

end.
