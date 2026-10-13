unit frame_DSRViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  unit_DSRViewerPanel;

type

  TframeDSRViewer = class(TFrame)
  private
    FScrollBox: TScrollBox;
  public
    Panel: TDSCViewerPanel;
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{$R *.dfm}


constructor TframeDSRViewer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FScrollBox := TScrollBox.Create(Self);
  FScrollBox.Parent := Self;
  FScrollBox.Align := alClient;
  FScrollBox.HorzScrollBar.Visible := False;
  FScrollBox.VertScrollBar.Smooth := True;
  FScrollBox.VertScrollBar.Tracking := True;
  FScrollBox.BorderStyle := bsNone;

  Panel := TDSCViewerPanel.Create(Self);
  Panel.Parent := FScrollBox;
  Panel.Align := alTop;
  Panel.AutoSize := True;
end;

end.
