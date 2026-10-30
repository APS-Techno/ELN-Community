unit test_ZRWViewerSelection;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.Hash, unit_ELNPluginCore, unit_ELNPluginTypes, unit_ZRWPlateau,
  frame_ZRWViewer;

type
  TApplyDouble = class(TInterfacedObject, IElnAnalysisSettings)
  public
    Calls: Integer;
    LastFileId: Int64;
    LastReaderId, LastExpected, LastNew: string;
    Outcome: TAnalysisApplyResult;
    ConflictJson: string;
    UserId: Integer;
    function Apply(FileId: Int64; const ReaderId, ExpectedJson, NewJson: string;
      out CurrentJson: string): TAnalysisApplyResult;
    function CurrentUserId: Integer;
  end;

  [TestFixture]
  TZRWViewerSelectionTests = class
  private
    FDir: string;
    FPath: string;
    FHash: string;
    FFrame: TframeZRWViewer;
    FService: IElnAnalysisSettings;
    FDouble: TApplyDouble;
    FPrevious: IElnAnalysisSettings;
    function Context(const SharedSelection: string): TAnalysisContext;
    function SharedJson(Mode: TZRWSelectionMode; Start, Stop: Double;
      ThroughEnd: Boolean; const FileHash: string; Revision: Integer): string;
    function Keys: TArray<TPluginKeyValue>;
    function CofOf(out Cof: Double): Boolean;
    function EnDashRange(const A, B: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DraftEditsChangeStatisticsAndDoNotCallApply;
    [Test] procedure ClosingAndReloadingTheFileDoNotCallApply;
    [Test] procedure ConflictKeepsDraftAndReloadShowsCurrentSelection;
    [Test] procedure StaleSelectionShowsOldBoundsAndBlocksValuesUntilApply;
    [Test] procedure StaleDraftEditsShowDraftStatisticsWhileExtractionStaysBlocked;
    [Test] procedure ReopenedStaleAutomaticSelectionKeepsOldBoundsAndBandUntilEdited;
    [Test] procedure ReopenedStaleThroughEndSelectionKeepsOldBoundsAndBandUntilEdited;
    [Test] procedure BandStaysBehindTheCurveOnEveryLoad;
    [Test] procedure EditingTheDraftClearsTheApplyMessage;
    [Test] procedure StaleSelectionReturnsToAutomaticByApplyingAutomatic;
    [Test] procedure ManualWarningsDoNotBlockApply;
    [Test] procedure InvalidBoundsDisableApply;
    [Test] procedure ApplyBuildsTheSelectionJson;
    [Test] procedure AutomaticApplyStoresTheDetectedInterval;
    [Test] procedure NoPlateauDisablesAutomaticApply;
    [Test] procedure MissingServiceDisablesApplyAndReloadButKeepsTheViewer;
    [Test] procedure AppliedSelectionReachesExtractionFromTheSameViewer;
    [Test] procedure RefusedApplyKeepsDraftAndShowsMessage;
    [Test] procedure RejectedFileShowsItsLoadErrorNotNoPlateau;
  end;

implementation

uses
  unit_ZRWAnalysis, unit_ZRWData, test_ZRWExtraction;

const
  OtherHash = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';

function TApplyDouble.Apply(FileId: Int64; const ReaderId, ExpectedJson,
  NewJson: string; out CurrentJson: string): TAnalysisApplyResult;
begin
  Inc(Calls);
  LastFileId := FileId;
  LastReaderId := ReaderId;
  LastExpected := ExpectedJson;
  LastNew := NewJson;
  if Outcome = aarApplied then
    CurrentJson := NewJson
  else
    CurrentJson := ConflictJson;
  Result := Outcome;
end;

function TApplyDouble.CurrentUserId: Integer;
begin
  Result := UserId;
end;

procedure TZRWViewerSelectionTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ZRWSelection_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FPath := TPath.Combine(FDir, 'plateau.zrw');
  WriteSyntheticZrw(FPath);
  FHash := UpperCase(THashMD5.GetHashStringFromFile(FPath));
  FPrevious := ElnAnalysisSettings;
  FDouble := TApplyDouble.Create;
  FDouble.Outcome := aarApplied;
  FDouble.UserId := 7;
  FService := FDouble;
  ElnAnalysisSettings := FService;
  FFrame := TframeZRWViewer.Create(nil);
  FFrame.LoadFromFile(FPath);
end;

procedure TZRWViewerSelectionTests.TearDown;
begin
  FreeAndNil(FFrame);
  ElnAnalysisSettings := FPrevious;
  FPrevious := nil;
  FService := nil;
  FDouble := nil;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TZRWViewerSelectionTests.Context(const SharedSelection: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := ackCurrent;
  Result.FileId := 17;
  Result.FileHash := FHash;
  Result.SharedSelection := SharedSelection;
end;

function TZRWViewerSelectionTests.SharedJson(Mode: TZRWSelectionMode; Start,
  Stop: Double; ThroughEnd: Boolean; const FileHash: string;
  Revision: Integer): string;
var
  S: TZRWSelection;
begin
  S := Default(TZRWSelection);
  S.Mode := Mode;
  S.Interval.StartCycle := Start;
  S.Interval.EndCycle := Stop;
  S.Interval.ThroughEnd := ThroughEnd;
  S.ReaderVersion := '2';
  S.AlgorithmVersion := '1';
  S.FileHash := FileHash;
  S.ApplyId := 'apply-' + IntToStr(Revision);
  S.AppliedAt := '2026-01-02T03:04:05Z';
  S.AppliedBy := 1;
  S.Revision := Revision;
  Result := SelectionToJson(S);
end;

function TZRWViewerSelectionTests.Keys: TArray<TPluginKeyValue>;
begin
  Result := FFrame.GetKeyValues;
end;

function TZRWViewerSelectionTests.CofOf(out Cof: Double): Boolean;
var
  Key: TPluginKeyValue;
begin
  for Key in Keys do
    if Key.Name = 'COF' then
    begin
      Cof := Key.Value;
      Exit(True);
    end;
  Cof := 0;
  Result := False;
end;

function TZRWViewerSelectionTests.EnDashRange(const A, B: string): string;
begin
  Result := A + #$2013 + B;
end;

procedure TZRWViewerSelectionTests.DraftEditsChangeStatisticsAndDoNotCallApply;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(Pos('Cycles ' + EnDashRange('20', '60'), FFrame.lblStats.Caption) > 0,
    FFrame.lblStats.Caption);
  Assert.IsTrue(Pos('Samples: 40', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.IsTrue(Pos('COF: 0.4079', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.IsTrue(Pos('draft, not applied', FFrame.lblStats.Caption) > 0);
  FFrame.SetDraftBounds(30, 70, False);
  Assert.IsTrue(Pos('COF: 0.4099', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  FFrame.edStart.Text := '40';
  FFrame.edBoundChange(FFrame.edStart);
  Assert.IsTrue(Pos('Cycles ' + EnDashRange('40', '70'), FFrame.lblStats.Caption) > 0,
    FFrame.lblStats.Caption);
  Assert.AreEqual(0, FDouble.Calls, 'Editing a draft must never apply it');
end;

procedure TZRWViewerSelectionTests.ClosingAndReloadingTheFileDoNotCallApply;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  FFrame.LoadFromFile(FPath);
  Assert.AreEqual(0, FDouble.Calls, 'Loading a file discards the draft');
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  FreeAndNil(FFrame);
  Assert.AreEqual(0, FDouble.Calls, 'Closing the viewer must never apply the draft');
end;

procedure TZRWViewerSelectionTests.ConflictKeepsDraftAndReloadShowsCurrentSelection;
var
  Held, Cof: Double;
  Current: string;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  Current := SharedJson(zsmManual, 5, 25, False, FHash, 2);
  FDouble.Outcome := aarConflict;
  FDouble.ConflictJson := Current;
  FFrame.ApplySelection;
  Assert.AreEqual(1, FDouble.Calls);
  Assert.AreEqual('20', FFrame.edStart.Text, 'The draft survives a conflict');
  Assert.AreEqual('60', FFrame.edEnd.Text);
  Assert.IsTrue(Pos('Reload', FFrame.lblWarnings.Caption) > 0, FFrame.lblWarnings.Caption);
  Assert.IsTrue(FFrame.btnReload.Enabled);
  Assert.IsTrue(CofOf(Held));
  Assert.AreEqual(0.4 + 0.0002 * 49.5, Held, 1e-9,
    'Extraction keeps using the selection the viewer started with');

  FFrame.ReloadSelection;
  Assert.AreEqual(1, FDouble.Calls, 'Reload must not call Apply');
  Assert.AreEqual('5', FFrame.edStart.Text);
  Assert.AreEqual('25', FFrame.edEnd.Text);
  Assert.IsTrue(FFrame.btnManual.Down);
  Assert.IsFalse(FFrame.btnReload.Enabled);
  Assert.IsTrue(CofOf(Cof));
  Assert.AreEqual(0.4 + 0.0002 * 14.5, Cof, 1e-9);

  FDouble.Outcome := aarApplied;
  FFrame.ApplySelection;
  Assert.AreEqual(2, FDouble.Calls);
  Assert.AreEqual(Current, FDouble.LastExpected,
    'The second apply must expect the reloaded selection');
end;

procedure TZRWViewerSelectionTests.StaleSelectionShowsOldBoundsAndBlocksValuesUntilApply;
var
  Cof: Double;
begin
  FFrame.SetAnalysisContext(Context(SharedJson(zsmManual, 20, 60, False, OtherHash, 3)));
  Assert.AreEqual('20', FFrame.edStart.Text);
  Assert.AreEqual('60', FFrame.edEnd.Text);
  Assert.IsTrue(Pos('Stale', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.IsTrue(Pos(EnDashRange('20', '60'), FFrame.lblStats.Caption) > 0,
    FFrame.lblStats.Caption);
  Assert.AreEqual(0, Pos('COF:', FFrame.lblStats.Caption), 'No interval values while stale');
  Assert.IsFalse(CofOf(Cof), 'Extraction yields no COF while stale');
  Assert.AreEqual(ANALYSIS_STATUS_STALE_SELECTION, FFrame.GetAnalysisStatus);
  Assert.IsTrue(FFrame.btnApply.Enabled);

  FFrame.ApplySelection;
  Assert.AreEqual(1, FDouble.Calls);
  Assert.AreEqual(SharedJson(zsmManual, 20, 60, False, OtherHash, 3), FDouble.LastExpected);
  Assert.AreEqual(0, Pos('Stale', FFrame.lblStats.Caption), FFrame.lblStats.Caption);
  Assert.IsTrue(CofOf(Cof), 'Applying clears the stale state');
  Assert.AreEqual(0.4 + 0.0002 * 39.5, Cof, 1e-9);
end;

procedure TZRWViewerSelectionTests.StaleDraftEditsShowDraftStatisticsWhileExtractionStaysBlocked;
var
  Cof: Double;
begin
  FFrame.SetAnalysisContext(Context(SharedJson(zsmManual, 20, 60, False, OtherHash, 3)));
  FFrame.SetDraftBounds(30, 70, False);
  Assert.IsTrue(Pos('COF: 0.4099', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.IsTrue(Pos('draft, not applied', FFrame.lblStats.Caption) > 0);
  Assert.IsTrue(Pos('Stale', FFrame.lblWarnings.Caption) > 0, FFrame.lblWarnings.Caption);
  Assert.AreEqual<NativeInt>(2, FFrame.SeriesBand.Count);
  Assert.AreEqual<Double>(30, FFrame.SeriesBand.XValues[0]);
  Assert.IsFalse(CofOf(Cof), 'Extraction stays blocked while stale');
  Assert.AreEqual(0, FDouble.Calls);
end;

procedure TZRWViewerSelectionTests.ReopenedStaleAutomaticSelectionKeepsOldBoundsAndBandUntilEdited;
begin
  FFrame.SetAnalysisContext(Context(SharedJson(zsmAutomatic, 0, 50, False, OtherHash, 2)));
  Assert.AreEqual('0', FFrame.edStart.Text);
  Assert.AreEqual('50', FFrame.edEnd.Text);
  Assert.IsTrue(Pos('Stale', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.AreEqual(0, Pos('draft', FFrame.lblStats.Caption));
  Assert.AreEqual<NativeInt>(2, FFrame.SeriesBand.Count);
  Assert.AreEqual<Double>(50, FFrame.SeriesBand.XValues[1]);
  FFrame.SetDraftMode(zsmAutomatic);
  Assert.IsTrue(Pos('draft, not applied', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.AreEqual<Double>(99, FFrame.SeriesBand.XValues[1]);
end;

procedure TZRWViewerSelectionTests.ReopenedStaleThroughEndSelectionKeepsOldBoundsAndBandUntilEdited;
begin
  FFrame.SetAnalysisContext(Context(SharedJson(zsmManual, 20, 50, True, OtherHash, 2)));
  Assert.AreEqual('20', FFrame.edStart.Text);
  Assert.AreEqual('50', FFrame.edEnd.Text);
  Assert.IsTrue(Pos('Stale', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.AreEqual(0, Pos('draft', FFrame.lblStats.Caption));
  Assert.AreEqual<Double>(50, FFrame.SeriesBand.XValues[1]);
  FFrame.edStart.Text := '21';
  Assert.IsTrue(Pos('draft, not applied', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  Assert.AreEqual<Double>(99, FFrame.SeriesBand.XValues[1]);
end;

procedure TZRWViewerSelectionTests.BandStaysBehindTheCurveOnEveryLoad;
begin
  Assert.IsTrue(FFrame.Chart.Series[0] = FFrame.SeriesBand);
  FFrame.LoadFromFile(FPath);
  Assert.IsTrue(FFrame.Chart.Series[0] = FFrame.SeriesBand);
  Assert.IsTrue(FFrame.Chart.Series[1] = FFrame.Series1);
end;

procedure TZRWViewerSelectionTests.EditingTheDraftClearsTheApplyMessage;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  FFrame.ApplySelection;
  Assert.IsTrue(Pos('Applied as revision', FFrame.lblWarnings.Caption) > 0);
  FFrame.SetDraftBounds(30, 70, False);
  Assert.AreEqual(0, Pos('Applied as revision', FFrame.lblWarnings.Caption));
end;

procedure TZRWViewerSelectionTests.StaleSelectionReturnsToAutomaticByApplyingAutomatic;
var
  Cof: Double;
  Stored: TZRWSelection;
begin
  FFrame.SetAnalysisContext(Context(SharedJson(zsmManual, 20, 60, False, OtherHash, 3)));
  FFrame.SetDraftMode(zsmAutomatic);
  Assert.IsFalse(FFrame.edStart.Enabled, 'Automatic bounds are not editable');
  FFrame.ApplySelection;
  Assert.IsTrue(TryParseSelection(FDouble.LastNew, Stored));
  Assert.IsTrue(Stored.Mode = zsmAutomatic);
  Assert.AreEqual<Double>(0, Stored.Interval.StartCycle);
  Assert.AreEqual<Double>(99, Stored.Interval.EndCycle);
  Assert.IsTrue(Stored.Interval.ThroughEnd);
  Assert.AreEqual(4, Stored.Revision, 'The revision continues the stale selection');
  Assert.IsTrue(CofOf(Cof));
  Assert.AreEqual(0.4 + 0.0002 * 49.5, Cof, 1e-9);
end;

procedure TZRWViewerSelectionTests.ManualWarningsDoNotBlockApply;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 25, False);
  Assert.IsTrue(Pos('shorter than 20%', FFrame.lblWarnings.Caption) > 0,
    FFrame.lblWarnings.Caption);
  Assert.IsTrue(FFrame.btnApply.Enabled, 'A warning must not block Apply');
  FFrame.ApplySelection;
  Assert.AreEqual(1, FDouble.Calls);
end;

procedure TZRWViewerSelectionTests.InvalidBoundsDisableApply;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(60, 20, False);
  Assert.IsFalse(FFrame.btnApply.Enabled);
  Assert.IsTrue(Pos('Interval unavailable', FFrame.lblStats.Caption) > 0);
  FFrame.SetDraftBounds(500, 600, False);
  Assert.IsFalse(FFrame.btnApply.Enabled, 'An interval without samples is invalid');
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(FFrame.btnApply.Enabled);
  FFrame.edStart.Text := 'abc';
  FFrame.edBoundChange(FFrame.edStart);
  Assert.IsFalse(FFrame.btnApply.Enabled);
  FFrame.ApplySelection;
  Assert.AreEqual(0, FDouble.Calls, 'A disabled Apply must not reach the service');
end;

procedure TZRWViewerSelectionTests.ApplyBuildsTheSelectionJson;
var
  Stored: TZRWSelection;
  First, FirstId: string;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  FFrame.ApplySelection;
  First := FDouble.LastNew;
  Assert.AreEqual<Int64>(17, FDouble.LastFileId);
  Assert.AreEqual('aps.zrw', FDouble.LastReaderId);
  Assert.AreEqual('', FDouble.LastExpected);
  Assert.IsTrue(TryParseSelection(First, Stored));
  Assert.IsTrue(Stored.Mode = zsmManual);
  Assert.AreEqual<Double>(20, Stored.Interval.StartCycle);
  Assert.AreEqual<Double>(60, Stored.Interval.EndCycle);
  Assert.IsFalse(Stored.Interval.ThroughEnd);
  Assert.AreEqual('2', Stored.ReaderVersion);
  Assert.AreEqual('3', Stored.AlgorithmVersion);
  Assert.AreEqual(FHash, Stored.FileHash);
  Assert.AreEqual(1, Stored.Revision);
  Assert.AreEqual(7, Stored.AppliedBy);
  Assert.IsTrue(Stored.ApplyId <> '');
  Assert.AreEqual<NativeInt>(20, Length(Stored.AppliedAt));
  Assert.AreEqual('Z', Copy(Stored.AppliedAt, 20, 1));
  Assert.AreEqual('T', Copy(Stored.AppliedAt, 11, 1));
  FirstId := Stored.ApplyId;

  FFrame.SetDraftBounds(30, 70, False);
  FFrame.ApplySelection;
  Assert.AreEqual(First, FDouble.LastExpected);
  Assert.IsTrue(TryParseSelection(FDouble.LastNew, Stored));
  Assert.AreEqual(2, Stored.Revision);
  Assert.AreNotEqual(FirstId, Stored.ApplyId);
end;

procedure TZRWViewerSelectionTests.AutomaticApplyStoresTheDetectedInterval;
var
  Stored: TZRWSelection;
begin
  FFrame.SetAnalysisContext(Context(''));
  Assert.IsTrue(FFrame.btnAutomatic.Down);
  Assert.IsTrue(FFrame.btnApply.Enabled);
  FFrame.ApplySelection;
  Assert.IsTrue(TryParseSelection(FDouble.LastNew, Stored));
  Assert.IsTrue(Stored.Mode = zsmAutomatic);
  Assert.AreEqual<Double>(0, Stored.Interval.StartCycle);
  Assert.AreEqual<Double>(99, Stored.Interval.EndCycle);
  Assert.IsTrue(Stored.Interval.ThroughEnd);
end;

procedure TZRWViewerSelectionTests.NoPlateauDisablesAutomaticApply;
begin
  WriteSyntheticZrw(FPath, False);
  FHash := UpperCase(THashMD5.GetHashStringFromFile(FPath));
  FFrame.LoadFromFile(FPath);
  FFrame.SetAnalysisContext(Context(''));
  Assert.IsFalse(FFrame.btnApply.Enabled);
  Assert.IsTrue(Pos('No plateau', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(FFrame.btnApply.Enabled, 'A manual interval needs no detected plateau');
end;

procedure TZRWViewerSelectionTests.MissingServiceDisablesApplyAndReloadButKeepsTheViewer;
var
  Cof: Double;
begin
  ElnAnalysisSettings := nil;
  FFrame.SetAnalysisContext(Context(''));
  Assert.IsFalse(FFrame.btnApply.Enabled);
  Assert.IsFalse(FFrame.btnReload.Enabled);
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(Pos('COF: 0.4079', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
  FFrame.ApplySelection;
  FFrame.ReloadSelection;
  Assert.AreEqual(0, FDouble.Calls);
  Assert.IsTrue(CofOf(Cof), 'Extraction works without the service');
end;

procedure TZRWViewerSelectionTests.AppliedSelectionReachesExtractionFromTheSameViewer;
var
  Cof: Double;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(CofOf(Cof));
  Assert.AreEqual(0.4 + 0.0002 * 49.5, Cof, 1e-9, 'Before Apply extraction uses the detector');
  FFrame.ApplySelection;
  Assert.IsTrue(CofOf(Cof));
  Assert.AreEqual(0.4 + 0.0002 * 39.5, Cof, 1e-9);
  Assert.IsTrue(Pos('applied, revision 1', FFrame.lblStats.Caption) > 0,
    FFrame.lblStats.Caption);
end;

procedure TZRWViewerSelectionTests.RefusedApplyKeepsDraftAndShowsMessage;
const
  Refusals: array[0..4] of TAnalysisApplyResult = (aarDenied, aarSigned,
    aarHashMismatch, aarInvalid, aarTooLarge);
var
  Refusal: TAnalysisApplyResult;
  Before, Cof: Double;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.SetDraftBounds(20, 60, False);
  Assert.IsTrue(CofOf(Before));
  for Refusal in Refusals do
  begin
    FDouble.Outcome := Refusal;
    FFrame.ApplySelection;
    Assert.IsTrue(FFrame.lblWarnings.Caption <> '', 'A refusal needs a message');
    Assert.AreEqual('20', FFrame.edStart.Text);
    Assert.AreEqual('60', FFrame.edEnd.Text);
    Assert.IsFalse(FFrame.btnReload.Enabled);
    Assert.IsTrue(CofOf(Cof));
    Assert.AreEqual(Before, Cof, 0.0, 'A refusal must not change the extraction context');
  end;
  Assert.AreEqual(Length(Refusals), FDouble.Calls);
end;

procedure TZRWViewerSelectionTests.RejectedFileShowsItsLoadErrorNotNoPlateau;
var
  Bad: string;
  Kind: Integer;
begin
  for Kind := 0 to 1 do
  begin
    Bad := TPath.Combine(FDir, 'bad' + IntToStr(Kind) + '.zrw');
    if Kind = 0 then
      WriteMalformedZrw(Bad)
    else
      WriteCommaDecimalZrw(Bad);
    Assert.WillRaise(
      procedure
      begin
        FFrame.LoadFromFile(Bad);
      end, EZRWFormatError);
    Assert.IsTrue(Pos('line ', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
    Assert.IsTrue(Pos('No plateau', FFrame.lblStats.Caption) = 0, FFrame.lblStats.Caption);
    Assert.IsTrue(Pos('line ', FFrame.Status.SimpleCaption) > 0, FFrame.Status.SimpleCaption);
    Assert.IsTrue(Pos('Stroke', FFrame.Status.SimpleCaption) = 0,
      'The previous file status must not remain');
    Assert.AreEqual<NativeInt>(0, FFrame.Series1.Count);
    FFrame.SetAnalysisContext(Context(''));
    Assert.IsTrue(Pos('line ', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
    FFrame.SetDraftMode(zsmManual);
    Assert.IsTrue(Pos('line ', FFrame.lblStats.Caption) > 0, FFrame.lblStats.Caption);
    Assert.IsFalse(FFrame.btnApply.Enabled);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TZRWViewerSelectionTests);

end.
