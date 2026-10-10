unit form_MarkdownEditorWindow;


interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Win.Registry,
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs, Vcl.Clipbrd, Vcl.Imaging.PngImage,
  RzPanel, RzButton, RzRadGrp, RzStatus, RzCommon,
  SynEdit,
  unit_SynHighlighterMd,
  unit_MarkdownFormatting,
  unit_ELNPluginCore,
  frame_MarkdownViewer,
  unit_MarkdownLinkRewriter,
  unit_MarkdownAttachmentResolver,
  unit_MarkdownEditorAttachments;

const
  REG_KEY_PATH = 'Software\ELN3\Plugins\Editor.Markdown';

type
  TformMarkdownEditor = class(TForm)
    pnlTop: TRzPanel;
    tbActions: TRzToolbar;
    btnSave: TRzToolButton;
    btnReload: TRzToolButton;
    tbFormat: TRzToolbar;
    btnBold: TRzToolButton;
    btnItalic: TRzToolButton;
    btnHeading: TRzToolButton;
    btnList: TRzToolButton;
    btnCode: TRzToolButton;
    btnLink: TRzToolButton;
    btnImage: TRzToolButton;
    rgMode: TRzRadioGroup;
    sbStatus: TRzStatusBar;
    pneFile: TRzStatusPane;
    pneChars: TRzStatusPane;
    pneState: TRzStatusPane;
    splPreview: TSplitter;
    pnlPreview: TPanel;
    edSrc: TSynEdit;

    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

    procedure DoSaveClick(Sender: TObject);
    procedure DoReloadClick(Sender: TObject);
    procedure DoBoldClick(Sender: TObject);
    procedure DoItalicClick(Sender: TObject);
    procedure DoCodeClick(Sender: TObject);
    procedure DoListClick(Sender: TObject);
    procedure DoHeadingClick(Sender: TObject);
    procedure DoLinkClick(Sender: TObject);
    procedure DoImageClick(Sender: TObject);
    procedure DoModeChange(Sender: TObject);
  private
    FLocalPath: string;
    FItemId: Integer;
    FFileId: Int64;
    FOnSaved: TProc<string>;
    FSaving: Boolean;

    // Runtime-created children (kept out of the DFM to avoid registering
    // the markdown highlighter / preview frame as design-time classes).
    FHighlighter: TSynMarkdownSyn;
    FPreview: TframeMarkdownViewer;
    FRefreshTimer: TTimer;

    procedure EnsurePreview;
    procedure RefreshTimerTick(Sender: TObject);
    procedure RenderPreview;
    procedure ApplyResult(const R: TWrapResult);
    procedure SrcChange(Sender: TObject);
    procedure UpdateTitleAndStatus;
    procedure SetSaveStatus(const Msg: string);
    procedure DoSave(Force: Boolean);
    procedure DoReload;
    function HandleConflict: Boolean;
    procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
    function TryPasteClipboardImage: Boolean;
    procedure LoadWindowState;
    procedure SaveWindowState;
  public
    procedure OpenFile(const ALocalPath: string;
                       AItemId: Integer; AFileId: Int64;
                       AOnSaved: TProc<string>);
    procedure SetOnSaved(AOnSaved: TProc<string>);

    property LocalPath: string read FLocalPath;
    property ItemId: Integer read FItemId;
    property FileId: Int64 read FFileId;
  end;

implementation

{$R *.dfm}

procedure TformMarkdownEditor.FormCreate(Sender: TObject);
begin
  edSrc.Options := edSrc.Options + [eoSmartTabs, eoTabsToSpaces, eoTrimTrailingSpaces];

  FHighlighter := TSynMarkdownSyn.Create(Self);
  edSrc.Highlighter := FHighlighter;

  FRefreshTimer := TTimer.Create(Self);
  FRefreshTimer.Interval := 250;
  FRefreshTimer.Enabled  := False;
  FRefreshTimer.OnTimer  := RefreshTimerTick;

  // Wire SrcChange after DFM streaming so the dirty marker tracks user
  // edits (and not whatever empty content the form streamed).
  edSrc.OnChange := SrcChange;

  LoadWindowState;

  // HandleNeeded gives DragAcceptFiles a real HWND to register.
  HandleNeeded;
  Winapi.ShellAPI.DragAcceptFiles(Handle, True);
end;

procedure TformMarkdownEditor.LoadWindowState;
var
  Reg: TRegistry;
  L, T, W, H, Mode, SplitW: Integer;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(REG_KEY_PATH) then Exit;
    try
      L := IfThen(Reg.ValueExists('L'), Reg.ReadInteger('L'), Self.Left);
      T := IfThen(Reg.ValueExists('T'), Reg.ReadInteger('T'), Self.Top);
      W := IfThen(Reg.ValueExists('W'), Reg.ReadInteger('W'), Self.Width);
      H := IfThen(Reg.ValueExists('H'), Reg.ReadInteger('H'), Self.Height);
      if W < 600 then W := 600;
      if H < 400 then H := 400;
      Self.SetBounds(L, T, W, H);

      if Reg.ValueExists('Mode') then
      begin
        Mode := Reg.ReadInteger('Mode');
        if (Mode >= 0) and (Mode <= 2) then
        begin
          rgMode.ItemIndex := Mode;
          DoModeChange(rgMode);
        end;
      end;

      if Reg.ValueExists('SplitWidth') then
      begin
        SplitW := Reg.ReadInteger('SplitWidth');
        if pnlPreview.Visible and (rgMode.ItemIndex = 2) then
          if (SplitW > 100) and (SplitW < Self.ClientWidth - 200) then
            pnlPreview.Width := SplitW;
      end;
    except
      // Corrupt/old data - ignore, keep defaults.
    end;
  finally
    Reg.CloseKey;
    Reg.Free;
  end;
end;

procedure TformMarkdownEditor.SaveWindowState;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(REG_KEY_PATH, True) then Exit;
    try
      Reg.WriteInteger('L', Self.Left);
      Reg.WriteInteger('T', Self.Top);
      Reg.WriteInteger('W', Self.Width);
      Reg.WriteInteger('H', Self.Height);
      Reg.WriteInteger('Mode', rgMode.ItemIndex);
      if pnlPreview.Visible then
        Reg.WriteInteger('SplitWidth', pnlPreview.Width);
    except
      // Don't surface registry write failures to the user.
    end;
  finally
    Reg.CloseKey;
    Reg.Free;
  end;
end;

procedure TformMarkdownEditor.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveWindowState;
end;

procedure TformMarkdownEditor.ApplyResult(const R: TWrapResult);
begin
  edSrc.BeginUpdate;
  try
    edSrc.Text      := R.NewText;
    edSrc.SelStart  := R.NewSelStart - 1;  // 1-based -> 0-based
    edSrc.SelLength := R.NewSelLen;
  finally
    edSrc.EndUpdate;
  end;
end;

procedure TformMarkdownEditor.DoBoldClick(Sender: TObject);
begin
  ApplyResult(WrapSelection(edSrc.Text, edSrc.SelStart + 1, edSrc.SelLength, '**', '**'));
end;

procedure TformMarkdownEditor.DoItalicClick(Sender: TObject);
begin
  ApplyResult(WrapSelection(edSrc.Text, edSrc.SelStart + 1, edSrc.SelLength, '*', '*'));
end;

procedure TformMarkdownEditor.DoCodeClick(Sender: TObject);
begin
  ApplyResult(WrapSelection(edSrc.Text, edSrc.SelStart + 1, edSrc.SelLength, '`', '`'));
end;

procedure TformMarkdownEditor.DoListClick(Sender: TObject);
begin
  ApplyResult(PrefixLines(edSrc.Text, edSrc.SelStart + 1, edSrc.SelLength, '- '));
end;

procedure TformMarkdownEditor.DoHeadingClick(Sender: TObject);
begin
  ApplyResult(MakeHeading(edSrc.Text, edSrc.SelStart + 1, 2));
end;

procedure TformMarkdownEditor.DoLinkClick(Sender: TObject);
var
  Sel: string;
begin
  if edSrc.SelLength > 0 then
  begin
    Sel := edSrc.SelText;
    edSrc.SelText := '[' + Sel + '](url)';
  end
  else
  begin
    edSrc.SelText := '[](url)';
    edSrc.SelStart := edSrc.SelStart - 6;  // place caret between [ and ]
  end;
end;

procedure TformMarkdownEditor.DoImageClick(Sender: TObject);
var
  Sel: string;
begin
  if edSrc.SelLength > 0 then
  begin
    Sel := edSrc.SelText;
    edSrc.SelText := '![' + Sel + '](url)';
  end
  else
  begin
    edSrc.SelText := '![](url)';
    edSrc.SelStart := edSrc.SelStart - 6;
  end;
end;

procedure TformMarkdownEditor.EnsurePreview;
begin
  if Assigned(FPreview) then Exit;

  FPreview := TframeMarkdownViewer.Create(pnlPreview);
  FPreview.Parent := pnlPreview;
  FPreview.Align  := alClient;
  // Hide the embedded viewer's own Edit toolbar — it makes no sense inside
  // the editor itself.
  FPreview.HideToolBar;
end;

procedure TformMarkdownEditor.DoModeChange(Sender: TObject);
begin
  case rgMode.ItemIndex of
    0: // Source
      begin
        splPreview.Visible := False;
        pnlPreview.Visible := False;
        edSrc.Visible := True;
        edSrc.Align   := alClient;
      end;
    1: // Preview
      begin
        EnsurePreview;
        edSrc.Visible      := False;
        splPreview.Visible := False;
        pnlPreview.Align   := alClient;
        pnlPreview.Visible := True;
        RenderPreview;
      end;
    2: // Split
      begin
        EnsurePreview;
        pnlPreview.Align := alRight;
        if pnlPreview.Width <= 0 then
          pnlPreview.Width := Self.ClientWidth div 2;
        pnlPreview.Visible := True;
        splPreview.Align   := alRight;
        splPreview.Visible := True;
        edSrc.Visible := True;
        edSrc.Align   := alClient;
        RenderPreview;
      end;
  end;
end;

procedure TformMarkdownEditor.RefreshTimerTick(Sender: TObject);
begin
  FRefreshTimer.Enabled := False;
  RenderPreview;
end;


procedure TformMarkdownEditor.RenderPreview;
var
  Rendered, BaseHref, Dir: string;
begin
  if not Assigned(FPreview) then Exit;
  if not (rgMode.ItemIndex in [1, 2]) then Exit;

  Dir := ExtractFilePath(FLocalPath);
  Rendered := RewriteAttachmentRefs(edSrc.Text, Dir);
  Rendered := RewriteElnLinks(Rendered);
  if Dir <> '' then
    BaseHref := MarkdownFileUrl(IncludeTrailingPathDelimiter(Dir))
  else
    BaseHref := '';
  FPreview.RenderMarkdown(Rendered, BaseHref);
end;

procedure TformMarkdownEditor.OpenFile(const ALocalPath: string;
  AItemId: Integer; AFileId: Int64; AOnSaved: TProc<string>);
var
  Body: string;
begin
  FLocalPath := ALocalPath;
  FItemId    := AItemId;
  FFileId    := AFileId;
  FOnSaved   := AOnSaved;

  // Read the local file into SynEdit. Strip a UTF-8 BOM if present —
  // legacy wiki pages were written with one (mirror Viewer.Markdown).
  if FileExists(ALocalPath) then
    Body := TFile.ReadAllText(ALocalPath, TEncoding.UTF8)
  else
    Body := '';
  if (Length(Body) > 0) and (Body[1] = #$FEFF) then
    Delete(Body, 1, 1);

  edSrc.OnChange := nil;          // suppress dirty during initial load
  try
    edSrc.Text := Body;
    edSrc.Modified := False;
  finally
    edSrc.OnChange := SrcChange;
  end;

  pneFile.Caption := ExtractFileName(ALocalPath);

  UpdateTitleAndStatus;
end;

procedure TformMarkdownEditor.SetOnSaved(AOnSaved: TProc<string>);
begin
  FOnSaved := AOnSaved;
end;

procedure TformMarkdownEditor.SrcChange(Sender: TObject);
begin
  UpdateTitleAndStatus;
  // Debounce preview re-render only when preview is visible (modes 1/2).
  // Disable then re-enable to restart the 250 ms countdown.
  if Assigned(FRefreshTimer) and (rgMode.ItemIndex in [1, 2]) then
  begin
    FRefreshTimer.Enabled := False;
    FRefreshTimer.Enabled := True;
  end;
end;

procedure TformMarkdownEditor.UpdateTitleAndStatus;
var
  Base: string;
begin
  Base := ExtractFileName(FLocalPath);
  if FItemId <> 0 then
    Base := Base + ' [' + IntToStr(FItemId) + ']';
  if edSrc.Modified then
    Caption := '* ' + Base
  else
    Caption := Base;

  pneChars.Caption := IntToStr(Length(edSrc.Text)) + ' chars';
end;

procedure TformMarkdownEditor.SetSaveStatus(const Msg: string);
begin
  pneState.Caption := Msg;
end;

procedure TformMarkdownEditor.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
var
  Resp: Integer;
begin
  CanClose := True;
  if not edSrc.Modified then
    Exit;

  Resp := MessageDlg(
    Format('Save changes to %s?', [ExtractFileName(FLocalPath)]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);

  case Resp of
    mrYes:
      begin
        DoSave(False);
        CanClose := not edSrc.Modified;
      end;
    mrNo:     CanClose := True;
    mrCancel: CanClose := False;
  else
    CanClose := False;
  end;
end;

procedure TformMarkdownEditor.DoSave(Force: Boolean);
var
  Err:       string;
  SaveRes:   TSaveResult;
  Bytes:     TBytes;
begin
  if FSaving then Exit;
  FSaving := True;
  try
    // GetBytes omits the BOM that TFile.WriteAllText with UTF8 would prepend.
    Bytes := TEncoding.UTF8.GetBytes(edSrc.Text);
    try
      TFile.WriteAllBytes(FLocalPath, Bytes);
    except
      on E: Exception do
      begin
        SetSaveStatus('ERR ' + E.Message);
        ShowMessage('Could not write local file: ' + E.Message);
        Exit;
      end;
    end;

    if not Assigned(ElnFileService) then
    begin
      edSrc.Modified := False;
      UpdateTitleAndStatus;
      SetSaveStatus('Saved locally ' + FormatDateTime('hh:nn:ss', Now) +
        ' (no host service)');
      if Assigned(FOnSaved) then FOnSaved(edSrc.Text);
      Exit;
    end;

    repeat
      if Force then
        SaveRes := ElnFileService.SaveLocalFileForce(FFileId, FLocalPath, Err)
      else
        SaveRes := ElnFileService.SaveLocalFile(FFileId, FLocalPath, Err);

      if SaveRes = srConflict then
      begin
        SetSaveStatus('Conflict - server changed');
        if not HandleConflict then Exit;
        // Keep the guard while the explicit force decision is executed.
        Force := True;
      end;
    until SaveRes <> srConflict;

    case SaveRes of
      srOk:
        begin
          edSrc.Modified := False;
          UpdateTitleAndStatus;
          SetSaveStatus('Saved ' + FormatDateTime('hh:nn:ss', Now));
          if Assigned(FOnSaved) then FOnSaved(edSrc.Text);
        end;
      srError:
        begin
          SetSaveStatus('ERR ' + Err);
          ShowMessage('Save failed: ' + Err);
        end;
    end;
  finally
    FSaving := False;
  end;
end;

procedure TformMarkdownEditor.DoSaveClick(Sender: TObject);
begin
  DoSave(False);
end;

function TformMarkdownEditor.HandleConflict: Boolean;
var
  TD: TTaskDialog;
  ButtonReload, ButtonSaveAnyway, ButtonCancel: TTaskDialogBaseButtonItem;
begin
  Result := False;
  TD := TTaskDialog.Create(Self);
  try
    TD.Caption       := 'File changed on server';
    TD.Title         := 'Conflict';
    TD.Text          := 'This file was changed on the server since you opened it.';
    TD.CommonButtons := [];

    ButtonReload     := TD.Buttons.Add;
    ButtonReload.Caption := 'Reload (discard my edits)';
    ButtonSaveAnyway := TD.Buttons.Add;
    ButtonSaveAnyway.Caption := 'Save Anyway (overwrite server)';
    ButtonCancel     := TD.Buttons.Add;
    ButtonCancel.Caption := 'Cancel';

    TD.MainIcon := tdiWarning;

    if TD.Execute then
    begin
      if TD.ModalResult = ButtonReload.ModalResult then
        DoReload
      else if TD.ModalResult = ButtonSaveAnyway.ModalResult then
        Result := True;
    end;
  finally
    TD.Free;
  end;
end;

procedure TformMarkdownEditor.DoReload;
var
  Err, Body: string;
begin
  if not Assigned(ElnFileService) then
  begin
    SetSaveStatus('Reload unavailable (no host service)');
    Exit;
  end;

  if not ElnFileService.ReloadLocalFile(FFileId, FLocalPath, Err) then
  begin
    SetSaveStatus('Reload failed: ' + Err);
    ShowMessage('Reload failed: ' + Err);
    Exit;
  end;

  if FileExists(FLocalPath) then
    Body := TFile.ReadAllText(FLocalPath, TEncoding.UTF8)
  else
    Body := '';
  if (Length(Body) > 0) and (Body[1] = #$FEFF) then
    Delete(Body, 1, 1);

  edSrc.OnChange := nil;
  try
    edSrc.Text := Body;
    edSrc.Modified := False;
  finally
    edSrc.OnChange := SrcChange;
  end;

  UpdateTitleAndStatus;
  SetSaveStatus('Reloaded ' + FormatDateTime('hh:nn:ss', Now));
  if Assigned(FOnSaved) then FOnSaved(edSrc.Text);
end;

procedure TformMarkdownEditor.DoReloadClick(Sender: TObject);
var
  Resp: Integer;
begin
  if edSrc.Modified then
  begin
    Resp := MessageDlg(
      'Reload will discard your unsaved edits. Continue?',
      mtConfirmation, [mbYes, mbNo], 0);
    if Resp <> mrYes then Exit;
  end;
  DoReload;
end;

procedure TformMarkdownEditor.WMDropFiles(var Msg: TWMDropFiles);
var
  I, FileCount: Integer;
  Buf: array[0..MAX_PATH] of Char;
  LocalPath, Server, Snippet: string;
  IsImg: Boolean;
begin
  FileCount := DragQueryFile(Msg.Drop, $FFFFFFFF, nil, 0);
  try
    for I := 0 to FileCount - 1 do
    begin
      DragQueryFile(Msg.Drop, I, Buf, Length(Buf));
      LocalPath := Buf;
      IsImg     := IsImageExt(ExtractFileExt(LocalPath));
      try
        if Assigned(ElnFileService) then
          Server := ElnFileService.UploadAttachment(FItemId, LocalPath, '')
        else
          Server := ExtractFileName(LocalPath);
        Snippet := BuildInsertSnippet(Server, IsImg);
        // Newline-prefix when the cursor is mid-line so the snippet doesn't
        // get glued to existing text.
        if (edSrc.SelStart > 0) and (edSrc.Lines.Text <> '') and
           (edSrc.CaretX > 1) then
          edSrc.SelText := sLineBreak + Snippet
        else
          edSrc.SelText := Snippet;
      except
        on E: ENotImplemented do
          SetSaveStatus('Drop: UploadAttachment not yet wired by host (' +
            E.Message + ')');
        on E: Exception do
          SetSaveStatus('Drop failed: ' + E.Message);
      end;
    end;
  finally
    DragFinish(Msg.Drop);
  end;
  Msg.Result := 0;
end;

procedure TformMarkdownEditor.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  Handled: Boolean;
begin
  if (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    case Key of
      Ord('S'): begin DoSave(False);      Key := 0; end;
      Ord('B'): begin DoBoldClick(nil);   Key := 0; end;
      Ord('I'): begin DoItalicClick(nil); Key := 0; end;
      Ord('K'): begin DoLinkClick(nil);   Key := 0; end;
      Ord('V'):
        begin
          Handled := TryPasteClipboardImage;
          if Handled then Key := 0;
        end;
    end;
  end;
end;

function TformMarkdownEditor.TryPasteClipboardImage: Boolean;
var
  Bmp:      TBitmap;
  Png:      TPngImage;
  TempName: string;
  TempPath: string;
  Server:   string;
  Snippet:  string;
begin
  Result := False;
  if not Clipboard.HasFormat(CF_BITMAP) and not Clipboard.HasFormat(CF_DIB) then
    Exit;
  // If the clipboard ALSO has CF_TEXT/CF_UNICODETEXT, prefer text paste
  // (matches the standard editor convention; avoids "I copied a screenshot
  // earlier and now my text paste turns into an image" surprises).
  if Clipboard.HasFormat(CF_TEXT) or Clipboard.HasFormat(CF_UNICODETEXT) then
    Exit;

  TempName := ClipboardImageFileName(Now);
  TempPath := TPath.Combine(TPath.GetTempPath, TempName);

  Bmp := TBitmap.Create;
  try
    Bmp.Assign(Clipboard);
    if (Bmp.Width = 0) or (Bmp.Height = 0) then Exit;

    Png := TPngImage.Create;
    try
      Png.Assign(Bmp);
      Png.SaveToFile(TempPath);
    finally
      Png.Free;
    end;
  finally
    Bmp.Free;
  end;

  try
    if Assigned(ElnFileService) then
      Server := ElnFileService.UploadAttachment(FItemId, TempPath, TempName)
    else
      Server := TempName;
    Snippet := BuildInsertSnippet(Server, True);
    edSrc.SelText := Snippet;
    Result := True;
  except
    on E: ENotImplemented do
    begin
      SetSaveStatus('Paste-image: UploadAttachment not yet wired (' +
        E.Message + ')');
      // Still mark Result = True because we DID handle it (don't fall through
      // to text paste, which would paste nothing useful for a bitmap clipboard).
      Result := True;
    end;
    on E: Exception do
    begin
      SetSaveStatus('Paste-image failed: ' + E.Message);
      Result := True;
    end;
  end;

  try TFile.Delete(TempPath); except end;
end;

end.
