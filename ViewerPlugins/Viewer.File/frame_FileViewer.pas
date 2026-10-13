unit frame_FileViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls,
  JamFilePreview;

type

  TframeFileViewer = class(TFrame)
    JamFilePreview: TJamFilePreview;
  private
  public
  end;

implementation

{$R *.dfm}

end.
