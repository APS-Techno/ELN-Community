unit unit_MarkdownEditorPlugin;

// Editor.Markdown plugin entry point.
//
// This BPL doesn't render files (it's not an IViewerPlugin). Its purpose is
// to provide an out-of-pane markdown editor window, exposed to the rest of
// the system via the global IMarkdownEditorLauncher (from unit_ELNPluginCore).
// Viewer.Markdown's Edit toolbar button (Task 9.1) reads that global at
// click time and asks the launcher to open the editor for a given local file.
//
// The TupfVisualPlugin shell (TELNMarkdownEditorPlugin) exists solely because
// the TMS plugin framework loads BPLs by registering visual plugins; the
// shell has no frame, no params, no LoadFromFile. Real work lives in
// TMarkdownEditorLauncher and TformMarkdownEditor.

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
                           ItemId, FileId: Integer;
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

{ TELNMarkdownEditorPlugin }

procedure TELNMarkdownEditorPlugin.upfVisualPluginCreate(Sender: TObject);
begin
  // No frame; nothing to construct.
end;

{ TMarkdownEditorLauncher }

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
  // Find the entry whose value is Sender; remove it. (Reverse-lookup is OK
  // because the registry is small - one entry per open editor window.)
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
  ItemId, FileId: Integer; OnSaved: TProc<string>);
var
  Form: TformMarkdownEditor;
begin
  if FOpenWindows.TryGetValue(LocalPath, Form) then
  begin
    Form.SetOnSaved(OnSaved);
    Form.BringToFront;
    Form.Show;
    Exit;
  end;
  Form := TformMarkdownEditor.Create(nil);
  Form.OpenFile(LocalPath, ItemId, FileId, OnSaved);
  Form.OnClose := HandleEditorClose;
  FOpenWindows.Add(LocalPath, Form);
  Form.Show;
end;

end.
