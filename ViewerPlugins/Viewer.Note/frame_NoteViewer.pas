unit frame_NoteViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ComCtrls, RzEdit, RzButton, RzLabel, Vcl.ExtCtrls, RzPanel;

type
  TfrmNoteViewer = class(TFrame)
    RzPanel1: TRzPanel;
    lblLogTitle: TRzLabel;
    RichEdit: TRzRichEdit;
  private
  public
  end;

implementation

{$R *.dfm}

end.
