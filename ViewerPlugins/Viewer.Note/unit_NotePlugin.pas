unit unit_NotePlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  unit_ELNThemeHelper,
  frame_NoteViewer;

type

  TELNNoteViewerPlugin = class(TELNBaseViewerPlugin)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    procedure DisplayText(const Caption, Text: string); override;
  end;

  procedure Register;
  procedure UnRegister;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}
var
  APlugin: TELNNoteViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNNoteViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNNoteViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TfrmNoteViewer.Create(nil);
end;

function TELNNoteViewerPlugin.GetParams: TPluginParams;
begin
  Result.PType   := ptText;
  Result.Ext     := '';
  Result.IntOpen := True;
end;

procedure TELNNoteViewerPlugin.DisplayText(const Caption, Text: string);
var
  Stream: TStringStream;
begin
  ApplyRichEditTheme(TfrmNoteViewer(FFrame).RichEdit);
  if Text.StartsWith('{\rtf') then
  begin
    Stream := TStringStream.Create(Text);
    try
      TfrmNoteViewer(FFrame).RichEdit.Lines.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
  end
  else
    TfrmNoteViewer(FFrame).RichEdit.Text := Text;
end;

end.
