unit test_ProtocolExtractionRegressions;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProtocolExtractionRegressions = class
  public
    [Test] procedure UnavailableBrowserRaises;
    [Test] procedure FailedHRESULTCannotReturnData;
    [Test] procedure MissingExtractorCannotReturnData;
    [Test] procedure StaleFailedCallbacksCannotCompleteNewRequest;
    [Test] procedure EmptyFormObjectIsValid;
  end;

implementation

uses
  Winapi.Windows, Winapi.WebView2, frame_ProtocolViewer;

procedure TProtocolExtractionRegressions.UnavailableBrowserRaises;
var
  Frame: TframeProtocolViewer;
begin
  Frame := TframeProtocolViewer.Create(nil);
  try
    Assert.WillRaise(procedure begin Frame.GetFormData; end,
      EProtocolExtractionError);
  finally
    Frame.Free;
  end;
end;

procedure TProtocolExtractionRegressions.FailedHRESULTCannotReturnData;
var
  Completion: TProtocolExtractionCompletion;
  Handler: ICoreWebView2ExecuteScriptCompletedHandler;
begin
  Completion := TProtocolExtractionCompletion.Create;
  Handler := Completion;
  Handler.Invoke(E_FAIL, PWideChar('{"body":"old"}'));
  Assert.WillRaise(procedure begin Completion.FormData; end,
    EProtocolExtractionError);
end;

procedure TProtocolExtractionRegressions.MissingExtractorCannotReturnData;
var
  Completion: TProtocolExtractionCompletion;
  Handler: ICoreWebView2ExecuteScriptCompletedHandler;
begin
  Completion := TProtocolExtractionCompletion.Create;
  Handler := Completion;
  Handler.Invoke(S_OK, PWideChar('null'));
  Assert.WillRaise(procedure begin Completion.FormData; end,
    EProtocolExtractionError);
  Completion := TProtocolExtractionCompletion.Create;
  Handler := Completion;
  Handler.Invoke(S_OK, nil);
  Assert.WillRaise(procedure begin Completion.FormData; end,
    EProtocolExtractionError);
end;

procedure TProtocolExtractionRegressions.StaleFailedCallbacksCannotCompleteNewRequest;
var
  OldHRESULT, OldNull, Current: TProtocolExtractionCompletion;
  OldHRESULTHandler, OldNullHandler, CurrentHandler: ICoreWebView2ExecuteScriptCompletedHandler;
begin
  // The old callers have timed out, but the browser still owns their native
  // callbacks. A new extraction must remain independent of either completion.
  OldHRESULT := TProtocolExtractionCompletion.Create;
  OldHRESULTHandler := OldHRESULT;
  OldNull := TProtocolExtractionCompletion.Create;
  OldNullHandler := OldNull;
  Current := TProtocolExtractionCompletion.Create;
  CurrentHandler := Current;
  OldHRESULTHandler.Invoke(E_FAIL, nil);
  Assert.IsFalse(Current.Done);
  OldNullHandler.Invoke(S_OK, PWideChar('null'));
  Assert.IsFalse(Current.Done);
  CurrentHandler.Invoke(S_OK, PWideChar('{"body":"new"}'));
  Assert.IsTrue(Current.Done);
  Assert.AreEqual('{"body":"new"}', Current.FormData);
  // A duplicate late completion cannot overwrite the accepted result.
  CurrentHandler.Invoke(E_FAIL, nil);
  Assert.AreEqual('{"body":"new"}', Current.FormData);
end;

procedure TProtocolExtractionRegressions.EmptyFormObjectIsValid;
var
  Completion: TProtocolExtractionCompletion;
  Handler: ICoreWebView2ExecuteScriptCompletedHandler;
begin
  Completion := TProtocolExtractionCompletion.Create;
  Handler := Completion;
  Handler.Invoke(S_OK, PWideChar('{}'));
  Assert.AreEqual('{}', Completion.FormData);
end;

initialization
  TDUnitX.RegisterTestFixture(TProtocolExtractionRegressions);
end.
