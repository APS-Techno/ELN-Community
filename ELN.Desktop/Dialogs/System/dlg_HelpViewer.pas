unit dlg_HelpViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Edge,
  RzPanel, RzButton,
  unit_ELNPluginCore;

type
  TdlgHelpViewer = class(TForm)
    pnlContent: TRzPanel;
    pnlBottom: TRzPanel;
    btnClose: TRzButton;
    procedure btnCloseClick(Sender: TObject);
  private
    FHtmlViewer: IViewerPlugin;
    FSavedParent: TWinControl;
    class function FindEdgeBrowser(AParent: TWinControl): TEdgeBrowser; static;
  public
    class procedure ShowHelp(const AFileName: string; HtmlViewer: IViewerPlugin;
      const ACaption: string = 'Help');
  end;

implementation

{$R *.dfm}

class function TdlgHelpViewer.FindEdgeBrowser(AParent: TWinControl): TEdgeBrowser;
var
  I: Integer;
  Child: TControl;
begin
  Result := nil;
  for I := 0 to AParent.ControlCount - 1 do
  begin
    Child := AParent.Controls[I];
    if Child is TEdgeBrowser then
      Exit(TEdgeBrowser(Child));
    if Child is TWinControl then
    begin
      Result := FindEdgeBrowser(TWinControl(Child));
      if Assigned(Result) then Exit;
    end;
  end;
end;

class procedure TdlgHelpViewer.ShowHelp(const AFileName: string;
  HtmlViewer: IViewerPlugin; const ACaption: string);
var
  Dialog: TdlgHelpViewer;
begin
  if not Assigned(HtmlViewer) then
    raise EInvalidOperation.Create('The HTML viewer plugin is not available.');
  if not FileExists(AFileName) then
  begin
    MessageDlg('Help file not found: ' + AFileName, mtError, [mbOK], 0);
    Exit;
  end;

  Dialog := TdlgHelpViewer.Create(Application);
  try
    Dialog.Caption := ACaption;

    Dialog.FHtmlViewer := HtmlViewer;
    if Assigned(Dialog.FHtmlViewer) then
    begin
      Dialog.FSavedParent := Dialog.FHtmlViewer.Frame.Parent;
      Dialog.FHtmlViewer.Frame.Parent := Dialog.pnlContent;
      Dialog.FHtmlViewer.Frame.Align := alClient;
      Dialog.FHtmlViewer.LoadFromFile(AFileName);
      Dialog.ActiveControl := FindEdgeBrowser(Dialog.pnlContent);
    end;

    Dialog.ShowModal;
  finally
    if Assigned(Dialog.FHtmlViewer) and Assigned(Dialog.FSavedParent) then
    begin
      Dialog.FHtmlViewer.Frame.Parent := Dialog.FSavedParent;
      Dialog.FHtmlViewer.Frame.Align := alClient;
    end;
    Dialog.Free;
  end;
end;

procedure TdlgHelpViewer.btnCloseClick(Sender: TObject);
begin
  ModalResult := mrClose;
end;

end.
