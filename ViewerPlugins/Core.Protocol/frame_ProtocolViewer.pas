unit frame_ProtocolViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Edge, Winapi.ActiveX, Winapi.WebView2;

type
  EProtocolExtractionError = class(Exception);

  // A native callback owns one extraction result, never the viewer or a later
  // request. WebView2 may retain it after the waiting caller has timed out.
  TProtocolExtractionCompletion = class(TInterfacedObject,
    ICoreWebView2ExecuteScriptCompletedHandler)
  private
    FDone: Boolean;
    FData, FError: string;
  public
    function Invoke(ErrorCode: HRESULT; AJson: PWideChar): HRESULT; stdcall;
    function FormData: string;
    property Done: Boolean read FDone;
  end;

  TframeProtocolViewer = class(TFrame)
  private
    FBrowser: TEdgeBrowser;
    FWebViewReady: Boolean;
    FDocumentReady: Boolean;
    FDocumentRevision: UInt64;
    FPendingHtml: string;
    FReadOnly: Boolean;
    FScriptBusy: Boolean;
    FTemplatesPath: string;
    FOnDirty: TNotifyEvent;
    FDirtyFired: Boolean;
    procedure EnsureBrowser;
    procedure HandleWebViewCreated(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure HandleNavigationStarting(Sender: TCustomEdgeBrowser;
      Args: TNavigationStartingEventArgs);
    procedure HandleNavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure HandleWebMessage(Sender: TCustomEdgeBrowser;
      Args: TWebMessageReceivedEventArgs);
    procedure DisplayHtml(const HtmlCode: string);
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    function GetTemplatesPath: string;
    function LoadFile(const FileName: string): string;
    function ApplySection(const Html, SectionName, Value: string): string;
    function InjectScript(const Html, ScriptTag: string): string;
    function BuildViewerHTML(const Title, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, EquipModel, EquipManufacturer, EquipLocation: string): string;
    function BuildViewerTemplateHTML(const Title, ProtocolType, Status,
      CreatedDate, ModifiedDate, FormData, TemplateHtml,
      EquipModel, EquipManufacturer, EquipLocation: string): string;
    function BuildEditorTemplateHTML(const TemplateHtml, FormData: string): string;
    function BuildEditorFreeTextHTML(const FormData: string): string;
    function HtmlEscape(const S: string): string;
    function EscapeJsString(const S: string): string;
  public
    procedure ShowProtocol(const Title, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, EquipModel, EquipManufacturer, EquipLocation: string);
    procedure ShowProtocolWithTemplate(const Title, ProtocolType, Status,
      CreatedDate, ModifiedDate, FormData, TemplateHtml,
      EquipModel, EquipManufacturer, EquipLocation: string);

    procedure LoadTemplate(const TemplateHtml: string; const FormData: string = '');
    procedure LoadFreeText(const FormData: string = '');
    function GetFormData: string;

    { Call before reparenting to close WebView2 session;
      CMShowingChanged will reinitialize it in the new parent }
    procedure PrepareForReparent;

    property ReadOnly: Boolean read FReadOnly write FReadOnly default True;
    // Fired once after the first user edit in an editor build. Re-armed by
    // every LoadTemplate / LoadFreeText call (a fresh navigation re-installs
    // the listener). Not fired in viewer builds (inputs are disabled).
    property OnDirty: TNotifyEvent read FOnDirty write FOnDirty;
  end;


implementation

uses
  System.IOUtils, System.JSON, unit_ELNThemeHelper;

{$R *.dfm}

function TProtocolExtractionCompletion.Invoke(ErrorCode: HRESULT;
  AJson: PWideChar): HRESULT;
var
  Root: TJSONValue;
begin
  Result := S_OK;
  if FDone then Exit;
  try
    if Failed(ErrorCode) then
      FError := Format('Protocol extraction failed (HRESULT %.8x).', [ErrorCode])
    else
    begin
      Root := TJSONObject.ParseJSONValue(string(AJson));
      try
        if not (Root is TJSONObject) then
          FError := 'Protocol extraction returned invalid form data.'
        else
          FData := Root.ToJSON;
      finally
        Root.Free;
      end;
    end;
  except
    // Do not let a Delphi exception cross the native callback boundary.
    on E: Exception do
      FError := E.Message;
  end;
  FDone := True;
end;

function TProtocolExtractionCompletion.FormData: string;
begin
  if not FDone then
    raise EProtocolExtractionError.Create('Protocol extraction has not completed.');
  if FError <> '' then
    raise EProtocolExtractionError.Create(FError);
  Result := FData;
end;


function TframeProtocolViewer.GetTemplatesPath: string;
begin
  if FTemplatesPath = '' then
    FTemplatesPath := IncludeTrailingPathDelimiter(
      ExtractFilePath(Application.ExeName)) +
      'Plugins' + PathDelim + 'Templates' + PathDelim;
  Result := FTemplatesPath;
end;

function TframeProtocolViewer.LoadFile(const FileName: string): string;
begin
  Result := TFile.ReadAllText(GetTemplatesPath + FileName, TEncoding.UTF8);
end;

function TframeProtocolViewer.ApplySection(const Html, SectionName, Value: string): string;
var
  StartTag, EndTag: string;
  P1, P2: Integer;
begin
  Result := Html;
  StartTag := '{{?' + SectionName + '}}';
  EndTag := '{{/' + SectionName + '}}';
  P1 := Pos(StartTag, Result);
  P2 := Pos(EndTag, Result);
  if (P1 > 0) and (P2 > P1) then
  begin
    if Value <> '' then
    begin
      Delete(Result, P2, Length(EndTag));
      Delete(Result, P1, Length(StartTag));
      Result := StringReplace(Result, '{{' + SectionName + '}}', Value, []);
    end
    else
      Delete(Result, P1, P2 + Length(EndTag) - P1);
  end;
end;


procedure TframeProtocolViewer.EnsureBrowser;
var
  EdgePath, DataFolder: string;
begin
  if FBrowser <> nil then
    Exit;

  EdgePath := FindWebView2RuntimeFolder;
  DataFolder := TPath.Combine(TPath.GetTempPath, 'ELN_ProtocolViewer_WebView2');

  FBrowser := TEdgeBrowser.Create(Self);
  if EdgePath <> '' then
    FBrowser.BrowserExecutableFolder := EdgePath;
  FBrowser.UserDataFolder := DataFolder;
  FBrowser.OnCreateWebViewCompleted := HandleWebViewCreated;
  FBrowser.OnWebMessageReceived := HandleWebMessage;
  FBrowser.OnNavigationStarting := HandleNavigationStarting;
  FBrowser.OnNavigationCompleted := HandleNavigationCompleted;

  Self.HandleNeeded;
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.HandleNeeded;

  // If frame is already visible, CMShowingChanged won't fire again,
  // so trigger WebView creation directly
  if Showing then
    FBrowser.CreateWebView;
end;

procedure TframeProtocolViewer.HandleWebViewCreated(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  if not Succeeded(AResult) then
    OutputDebugString(PChar(Format('[ProtocolViewer] WebView2 creation failed hr=%.8x folder=%s',
      [AResult, FBrowser.BrowserExecutableFolder])));
  FWebViewReady := Succeeded(AResult);

  if FWebViewReady then
    ApplyBrowserColorScheme(FBrowser.DefaultInterface);

  if FWebViewReady and (FPendingHtml <> '') then
  begin
    FBrowser.NavigateToString(FPendingHtml);
    FPendingHtml := '';
  end;
end;


procedure TframeProtocolViewer.HandleNavigationStarting(
  Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
begin
  FDocumentReady := False;
  Inc(FDocumentRevision);
end;

procedure TframeProtocolViewer.HandleNavigationCompleted(
  Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
  FDocumentReady := IsSuccess;
end;

procedure TframeProtocolViewer.HandleWebMessage(Sender: TCustomEdgeBrowser;
  Args: TWebMessageReceivedEventArgs);
var
  Msg: PWideChar;
  Intf: ICoreWebView2WebMessageReceivedEventArgs;
begin
  // protocol.js posts the literal string "dirty" once on the first user edit.
  // The wrapper class uses interface delegation, so the COM methods are only
  // reachable via the underlying interface.
  Intf := Args.ArgsInterface;
  if (Intf = nil) or (not Succeeded(Intf.TryGetWebMessageAsString(Msg))) then
    Exit;
  try
    if FDirtyFired or (Msg = nil) then
      Exit;
    if string(Msg) = 'dirty' then
    begin
      FDirtyFired := True;
      if Assigned(FOnDirty) then
        FOnDirty(Self);
    end;
  finally
    CoTaskMemFree(Msg);
  end;
end;

procedure TframeProtocolViewer.CMShowingChanged(var Message: TMessage);
begin
  inherited;
  if Showing and (FBrowser <> nil) and not FWebViewReady then
    FBrowser.CreateWebView;
end;

procedure TframeProtocolViewer.DisplayHtml(const HtmlCode: string);
begin
  FDocumentReady := False;
  Inc(FDocumentRevision);
  if FWebViewReady then
    FBrowser.NavigateToString(HtmlCode)
  else
    FPendingHtml := HtmlCode;
end;


function TframeProtocolViewer.HtmlEscape(const S: string): string;
begin
  Result := StringReplace(S,  '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function TframeProtocolViewer.EscapeJsString(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '\''', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  // Neutralize '</script>' (and any '</...') breakout. The result is spliced
  // into an inline <script> block, where the HTML parser ends the script at the
  // literal characters '</script>' regardless of JS string quoting. '<\/' is an
  // equivalent JS string ('/'), but the parser no longer sees a closing tag.
  // Done last so the backslash it introduces is not re-escaped.
  Result := StringReplace(Result, '</', '<\/', [rfReplaceAll]);
end;

function TframeProtocolViewer.InjectScript(const Html, ScriptTag: string): string;
var
  P: Integer;
begin
  Result := Html;
  P := Pos('</head>', LowerCase(Result));
  if P > 0 then
    System.Insert(ScriptTag, Result, P)
  else
  begin
    P := Pos('</body>', LowerCase(Result));
    if P > 0 then
      System.Insert(ScriptTag, Result, P)
    else
      Result := Result + ScriptTag;
  end;
end;


function TframeProtocolViewer.BuildViewerHTML(const Title, ProtocolType, Status,
  CreatedDate, ModifiedDate, FormData, EquipModel, EquipManufacturer,
  EquipLocation: string): string;
var
  FormDataEsc, HasEquip: string;
begin
  Result := LoadFile('viewer.html');
  Result := StringReplace(Result, '{{CSS}}', LoadFile('protocol.css'), []);
  Result := StringReplace(Result, '{{TITLE}}', HtmlEscape(Title), []);
  Result := StringReplace(Result, '{{TYPE}}', HtmlEscape(ProtocolType), []);
  Result := StringReplace(Result, '{{STATUS}}', HtmlEscape(Status), []);
  Result := StringReplace(Result, '{{CREATED}}', HtmlEscape(CreatedDate), []);
  Result := ApplySection(Result, 'MODIFIED', HtmlEscape(ModifiedDate));

  if EquipModel <> '' then
    HasEquip := 'yes'
  else
    HasEquip := '';
  Result := StringReplace(Result, '{{EQUIP_MODEL}}', HtmlEscape(EquipModel), [rfReplaceAll]);
  Result := StringReplace(Result, '{{EQUIP_MANUFACTURER}}', HtmlEscape(EquipManufacturer), [rfReplaceAll]);
  Result := ApplySection(Result, 'EQUIP_LOCATION', HtmlEscape(EquipLocation));
  Result := ApplySection(Result, 'EQUIPMENT', HasEquip);

  if Trim(FormData) <> '' then
    FormDataEsc := HtmlEscape(FormData)
  else
    FormDataEsc := '';
  Result := ApplySection(Result, 'FORMDATA', FormDataEsc);
end;

function TframeProtocolViewer.BuildViewerTemplateHTML(const Title, ProtocolType,
  Status, CreatedDate, ModifiedDate, FormData, TemplateHtml,
  EquipModel, EquipManufacturer, EquipLocation: string): string;
var
  MetaHeader, HasEquip: string;
  P: Integer;
begin
  MetaHeader := LoadFile('viewer_header.html');
  MetaHeader := StringReplace(MetaHeader, '{{TITLE}}', HtmlEscape(Title), []);
  MetaHeader := StringReplace(MetaHeader, '{{TYPE}}', HtmlEscape(ProtocolType), []);
  MetaHeader := StringReplace(MetaHeader, '{{STATUS}}', HtmlEscape(Status), []);
  MetaHeader := StringReplace(MetaHeader, '{{CREATED}}', HtmlEscape(CreatedDate), []);
  MetaHeader := ApplySection(MetaHeader, 'MODIFIED', HtmlEscape(ModifiedDate));

  if EquipModel <> '' then
    HasEquip := 'yes'
  else
    HasEquip := '';
  MetaHeader := StringReplace(MetaHeader, '{{EQUIP_MODEL}}', HtmlEscape(EquipModel), [rfReplaceAll]);
  MetaHeader := StringReplace(MetaHeader, '{{EQUIP_MANUFACTURER}}', HtmlEscape(EquipManufacturer), [rfReplaceAll]);
  MetaHeader := ApplySection(MetaHeader, 'EQUIP_LOCATION', HtmlEscape(EquipLocation));
  MetaHeader := ApplySection(MetaHeader, 'EQUIPMENT', HasEquip);

  Result := TemplateHtml;
  Result := InjectScript(Result,
    '<script>' + LoadFile('protocol.js') + '</script>');

  P := Pos('<body>', LowerCase(Result));
  if P > 0 then
    System.Insert(MetaHeader, Result, P + 6)
  else
    Result := MetaHeader + Result;

  P := Pos('</body>', LowerCase(Result));
  if P > 0 then
    System.Insert(
      '<script>window.onload=function(){' +
      'setFormData(''' + EscapeJsString(FormData) + ''');' +
      'disableAllInputs();' +
      '};</script>',
      Result, P);
end;

procedure TframeProtocolViewer.ShowProtocol(const Title, ProtocolType, Status,
  CreatedDate, ModifiedDate, FormData, EquipModel, EquipManufacturer,
  EquipLocation: string);
begin
  EnsureBrowser;
  DisplayHtml(BuildViewerHTML(Title, ProtocolType, Status, CreatedDate,
    ModifiedDate, FormData, EquipModel, EquipManufacturer, EquipLocation));
end;

procedure TframeProtocolViewer.ShowProtocolWithTemplate(const Title,
  ProtocolType, Status, CreatedDate, ModifiedDate, FormData,
  TemplateHtml, EquipModel, EquipManufacturer, EquipLocation: string);
begin
  EnsureBrowser;

  if Trim(TemplateHtml) = '' then
  begin
    ShowProtocol(Title, ProtocolType, Status, CreatedDate, ModifiedDate,
      FormData, EquipModel, EquipManufacturer, EquipLocation);
    Exit;
  end;

  DisplayHtml(BuildViewerTemplateHTML(Title, ProtocolType, Status, CreatedDate,
    ModifiedDate, FormData, TemplateHtml, EquipModel, EquipManufacturer, EquipLocation));
end;


function TframeProtocolViewer.BuildEditorTemplateHTML(
  const TemplateHtml, FormData: string): string;
var
  P: Integer;
  OnLoadJs: string;
begin
  Result := TemplateHtml;
  Result := InjectScript(Result, '<script>' + LoadFile('protocol.js') + '</script>');

  // Restore form data (if any) and arm dirty tracking. Programmatic
  // setFormData does NOT fire input/change events, so arming order is safe.
  OnLoadJs := 'window.onload=function(){';
  if FormData <> '' then
    OnLoadJs := OnLoadJs + 'setFormData(''' + EscapeJsString(FormData) + ''');';
  OnLoadJs := OnLoadJs + 'armDirtyTracking();}';

  P := Pos('</body>', LowerCase(Result));
  if P > 0 then
    System.Insert('<script>' + OnLoadJs + '</script>', Result, P);
end;

function TframeProtocolViewer.BuildEditorFreeTextHTML(const FormData: string): string;
var
  P: Integer;
  OnLoadJs: string;
begin
  Result := LoadFile('editor_freetext.html');
  Result := StringReplace(Result, '{{JS}}', LoadFile('protocol.js'), []);

  if (FormData <> '') and (FormData[1] = '{') then
    Result := StringReplace(Result, '{{FORMDATA}}', '', [])
  else if FormData <> '' then
    // Legacy plain text — put directly in textarea (no input/change event,
    // so the user must still type to trigger dirty)
    Result := StringReplace(Result, '{{FORMDATA}}', HtmlEscape(FormData), [])
  else
    Result := StringReplace(Result, '{{FORMDATA}}', '', []);

  OnLoadJs := 'window.onload=function(){';
  if (FormData <> '') and (FormData[1] = '{') then
    OnLoadJs := OnLoadJs + 'setFormData(''' + EscapeJsString(FormData) + ''');';
  OnLoadJs := OnLoadJs + 'armDirtyTracking();}';

  P := Pos('</body>', LowerCase(Result));
  if P > 0 then
    System.Insert('<script>' + OnLoadJs + '</script>', Result, P);
end;

procedure TframeProtocolViewer.LoadTemplate(const TemplateHtml: string;
  const FormData: string);
begin
  EnsureBrowser;
  FDirtyFired := False;  // re-arm: a fresh navigation reinstalls JS listener

  if Trim(TemplateHtml) = '' then
  begin
    LoadFreeText(FormData);
    Exit;
  end;

  DisplayHtml(BuildEditorTemplateHTML(TemplateHtml, FormData));
end;

procedure TframeProtocolViewer.LoadFreeText(const FormData: string);
begin
  EnsureBrowser;
  FDirtyFired := False;  // re-arm
  DisplayHtml(BuildEditorFreeTextHTML(FormData));
end;

procedure TframeProtocolViewer.PrepareForReparent;
begin
  FDocumentReady := False;
  Inc(FDocumentRevision);
  // Close the WebView2 session but keep the TEdgeBrowser control alive.
  // After reparenting, CMShowingChanged will call CreateWebView to
  // reinitialize in the new parent context.
  if (FBrowser <> nil) and FWebViewReady then
  begin
    FBrowser.CloseBrowserProcess;
    FWebViewReady := False;
  end;
end;

function TframeProtocolViewer.GetFormData: string;
const
  SCRIPT_TIMEOUT_MS = 8000;
var
  Deadline, Revision: UInt64;
  Completion: TProtocolExtractionCompletion;
  Handler: ICoreWebView2ExecuteScriptCompletedHandler;
  Status: HRESULT;
begin
  if FScriptBusy then
    raise EProtocolExtractionError.Create('Protocol extraction is already in progress.');
  if not FWebViewReady or not FDocumentReady or (FBrowser = nil) or
    (FBrowser.DefaultInterface = nil) then
    raise EProtocolExtractionError.Create('Protocol editor is not ready. The form was not saved.');

  Completion := TProtocolExtractionCompletion.Create;
  Handler := Completion;
  FScriptBusy := True;
  try
    Revision := FDocumentRevision;
    // A separate native completion object correlates failures too, including
    // HRESULT/null results that carry no JavaScript request identifier.
    try
      Status := FBrowser.DefaultInterface.ExecuteScript(
        PWideChar('extractFormData()'), Handler);
      if Failed(Status) then
        raise EProtocolExtractionError.CreateFmt(
          'Protocol extraction could not start (HRESULT %.8x).', [Status]);
    except
      on E: Exception do
        raise EProtocolExtractionError.Create('Protocol extraction failed: ' + E.Message);
    end;
    Deadline := GetTickCount64 + SCRIPT_TIMEOUT_MS;
    while not Completion.Done do
    begin
      Application.ProcessMessages;
      if GetTickCount64 > Deadline then
        raise EProtocolExtractionError.Create('Protocol extraction timed out. The form was not saved.');
      if not FWebViewReady or not FDocumentReady or
        (Revision <> FDocumentRevision) then
        raise EProtocolExtractionError.Create('Protocol editor changed during extraction.');
    end;
    Result := Completion.FormData;
  finally
    FScriptBusy := False;
  end;
end;

end.
