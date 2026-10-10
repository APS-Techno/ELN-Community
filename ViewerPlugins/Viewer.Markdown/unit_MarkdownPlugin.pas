unit unit_MarkdownPlugin;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  frame_MarkdownViewer,
  unit_MarkdownLinkRewriter,
  unit_MarkdownAttachmentResolver,
  unit_MarkdownPreviewRender;

type
  TELNMarkdownViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IDetailedInfoProvider, IItemContextAware, IHostToolbarAware)
  private
    FRawMd: string;
    FSourceFile: string;
    FItemId: Integer;
    FFileId: Int64;
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetDetailedInfo: string;
    procedure SetItemContext(ItemId: Integer; FileId: Int64);
    function ShowHostToolbar: Boolean;
  end;

procedure Register;
procedure UnRegister;

implementation

var
  APlugin: TELNMarkdownViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNMarkdownViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNMarkdownViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeMarkdownViewer.Create(nil);
end;

function TELNMarkdownViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.md';
  Result.PType   := ptFile;
  Result.IntOpen := False;
  Result.AcceptsPartialLoad := True;
end;

function TELNMarkdownViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  Raw, Rendered, BaseHref, Dir: string;
  Files: TArray<string>;
begin
  Result := False;
  FRawMd := '';
  FSourceFile := '';
  if not FileExists(AFileName) then
    Exit;

  Dir := ExtractFilePath(AFileName);
  Raw := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  // Strip a leading UTF-8 BOM (U+FEFF) if present — some legacy pages were
  // written by an earlier code path that emitted one.
  if (Length(Raw) > 0) and (Raw[1] = #$FEFF) then
    Delete(Raw, 1, 1);
  FRawMd := Raw;
  FSourceFile := AFileName;

  // Sibling images may not be downloaded beside the markdown working copy.
  // The host supplies canonical names and makes the files available for rendering.
  Files := nil;
  if (FItemId > 0) and Assigned(ElnFileEnumerator) then
    Files := ElnFileEnumerator.EnsureItemFilesInDir(FItemId, Dir);

  Rendered := RewriteAttachmentRefs(Raw, Dir, Files);
  Rendered := RewriteElnLinks(Rendered);
  BaseHref := MarkdownFileUrl(IncludeTrailingPathDelimiter(Dir));
  TframeMarkdownViewer(FFrame).RenderMarkdown(Rendered, BaseHref);
  TframeMarkdownViewer(FFrame).SetEditContext(FSourceFile, FItemId, FFileId);
  Result := True;
end;

procedure TELNMarkdownViewerPlugin.SetItemContext(ItemId: Integer; FileId: Int64);
begin
  FItemId := ItemId;
  FFileId := FileId;
  if Assigned(FFrame) and (FSourceFile <> '') then
    TframeMarkdownViewer(FFrame).SetEditContext(FSourceFile, FItemId, FFileId);
end;

function TELNMarkdownViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := nil;

  // Preferred: capture the page the user is actually looking at. Only viable
  // when the viewer is on screen and the WebView2 has finished rendering —
  // in practice the "Update Preview" button.
  if Assigned(FFrame) and TframeMarkdownViewer(FFrame).ContentRendered then
    Result := TframeMarkdownViewer(FFrame).CaptureBitmap(MaxWidth, MaxHeight);
  if Assigned(Result) then
    Exit;

  // Fallback: draw the source ourselves. This is the path the batch preview
  // queue takes — it calls LoadFromFile then GetPreview with no message pump
  // in between, so the browser has never rendered and cannot be captured.
  if FRawMd <> '' then
    Result := RenderMarkdownPreview(FRawMd, MaxWidth, MaxHeight);
end;

function TELNMarkdownViewerPlugin.GetDetailedInfo: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('body_md', FRawMd);
    Obj.AddPair('source_file', ExtractFileName(FSourceFile));
    Obj.AddPair('byte_length', TJSONNumber.Create(Length(TEncoding.UTF8.GetBytes(FRawMd))));
    if FItemId <> 0 then
      Obj.AddPair('item_id', TJSONNumber.Create(FItemId));
    if FFileId <> 0 then
      Obj.AddPair('file_id', TJSONNumber.Create(FFileId));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TELNMarkdownViewerPlugin.ShowHostToolbar: Boolean;
begin
  Result := False;
end;

end.
