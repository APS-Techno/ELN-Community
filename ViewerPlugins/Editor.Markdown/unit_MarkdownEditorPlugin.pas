unit unit_MarkdownEditorPlugin;

// The plugin framework requires a visual-plugin shell to load this editor BPL.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Forms,
  upfVisualClasses,
  unit_ELNPluginCore,
  form_MarkdownEditorWindow;

type
  TMarkdownEditorLauncher = class(TInterfacedObject, IMarkdownEditorLauncher)
  private
    FOpenWindows: TDictionary<string, TformMarkdownEditor>;
    procedure HandleEditorClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create;
    destructor Destroy; override;
    procedure LaunchEditor(const LocalPath: string;
                           ItemId: Integer; FileId: Int64;
                           OnSaved: TProc<string>);
  end;

  TELNMarkdownEditorPlugin = class(TupfVisualPlugin)
    procedure upfVisualPluginCreate(Sender: TObject);
  end;

procedure Register;
procedure UnRegister;

implementation

{$R *.DFM}

var
  APlugin:   TELNMarkdownEditorPlugin;
  ALauncher: IMarkdownEditorLauncher;  // interface ref keeps the launcher alive

procedure Register;
begin
  APlugin   := TELNMarkdownEditorPlugin.Create(nil);
  ALauncher := TMarkdownEditorLauncher.Create;
  MarkdownEditorLauncher := ALauncher;
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  MarkdownEditorLauncher := nil;
  ALauncher := nil;  // ref-counted; freed when no holder remains
  APlugin.Free;
end;


procedure TELNMarkdownEditorPlugin.upfVisualPluginCreate(Sender: TObject);
begin
end;


constructor TMarkdownEditorLauncher.Create;
begin
  inherited Create;
  FOpenWindows := TDictionary<string, TformMarkdownEditor>.Create;
end;

destructor TMarkdownEditorLauncher.Destroy;
begin
  FOpenWindows.Free;
  inherited;
end;

procedure TMarkdownEditorLauncher.HandleEditorClose(Sender: TObject;
  var Action: TCloseAction);
var
  Pair: TPair<string, TformMarkdownEditor>;
  KeyToRemove: string;
begin
  KeyToRemove := '';
  for Pair in FOpenWindows do
    if Pair.Value = Sender then
    begin
      KeyToRemove := Pair.Key;
      Break;
    end;
  if KeyToRemove <> '' then
    FOpenWindows.Remove(KeyToRemove);
  Action := caFree;
end;

procedure TMarkdownEditorLauncher.LaunchEditor(const LocalPath: string;
  ItemId: Integer; FileId: Int64; OnSaved: TProc<string>);
var
  Form: TformMarkdownEditor;
  Key, WorkingPath: string;
begin
  if FileId <> 0 then
    Key := 'file:' + IntToStr(FileId)
  else
    Key := 'path:' + LocalPath;
  // Reuse before preparation: refreshing a live editor's baseline would
  // disconnect its unsaved buffer from the remote version it was opened on.
  if FOpenWindows.TryGetValue(Key, Form) then
  begin
    if Form = nil then
      raise Exception.Create('This Markdown file is already being opened.');
    Form.SetOnSaved(OnSaved);
    Form.BringToFront;
    Form.Show;
    Exit;
  end;
  // Reserve the identity while a remote preparation pumps messages.
  FOpenWindows.Add(Key, nil);
  Form := nil;
  try
    WorkingPath := LocalPath;
    if FileId <> 0 then
    begin
      if not Assigned(ElnFileService) then
        raise Exception.Create('The host file service is not available.');
      WorkingPath := ElnFileService.PrepareLocalFile(FileId);
      if (WorkingPath = '') or not FileExists(WorkingPath) then
        raise EFileNotFoundException.Create('The complete Markdown working file is not available.');
    end;
    Form := TformMarkdownEditor.Create(nil);
    Form.OpenFile(WorkingPath, ItemId, FileId, OnSaved);
    Form.OnClose := HandleEditorClose;
    FOpenWindows[Key] := Form;
    Form.Show;
  except
    FOpenWindows.Remove(Key);
    Form.Free;
    raise;
  end;
end;

end.
