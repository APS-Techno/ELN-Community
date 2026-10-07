unit dlg_About;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TdlgAbout = class(TForm)
    imgIcon: TImage;
    lblAppName: TLabel;
    lblVersion: TLabel;
    lblCopyright: TLabel;
    bvlSeparator: TBevel;
    btnOK: TButton;
    procedure FormCreate(Sender: TObject);
  public
    class procedure ShowAbout(const Version: string; CopyrightYear: Integer);
  end;

implementation

{$R *.dfm}


procedure TdlgAbout.FormCreate(Sender: TObject);
begin
  imgIcon.Picture.Icon.Assign(Application.Icon);
end;

class procedure TdlgAbout.ShowAbout(const Version: string; CopyrightYear: Integer);
var
  Dialog: TdlgAbout;
begin
  Dialog := TdlgAbout.Create(nil);
  try
    Dialog.lblVersion.Caption := 'Version ' + Version;
    Dialog.lblCopyright.Caption := Format('Copyright %s %d APS Technology',
      [#169, CopyrightYear]);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
