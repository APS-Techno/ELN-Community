unit dlg_Note;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  RzLabel, RzButton, RzPanel, RzEdit, Vcl.Mask,
  unit_Protocol;

type
  TdlgNote = class(TForm)
    pnlBottom: TRzPanel;
    btnOK: TRzButton;
    btnCancel: TRzButton;
    pnlMain: TRzPanel;
    lblTitle: TRzLabel;
    edtTitle: TRzEdit;
    pnlToolbar: TRzPanel;
    btnBold: TRzButton;
    btnItalic: TRzButton;
    btnUnderline: TRzButton;
    reContent: TRichEdit;
    procedure btnOKClick(Sender: TObject);
    procedure btnBoldClick(Sender: TObject);
    procedure btnItalicClick(Sender: TObject);
    procedure btnUnderlineClick(Sender: TObject);
  private
    procedure ToggleStyle(AStyle: TFontStyle);
    procedure LoadRtf(const Rtf: string);
    function SaveRtf: string;
  public
    class function Execute(Protocol: TProtocol): Boolean;
    class function RtfToPlainText(const Rtf: string): string;
  end;

implementation

{$R *.dfm}


class function TdlgNote.Execute(Protocol: TProtocol): Boolean;
var
  Dialog: TdlgNote;
begin
  Dialog := TdlgNote.Create(nil);
  try
    Dialog.edtTitle.Text := Protocol.Title;

    if Protocol.FormData <> '' then
      Dialog.LoadRtf(Protocol.FormData);

    Result := Dialog.ShowModal = mrOk;

    if Result then
    begin
      Protocol.Title := Dialog.edtTitle.Text;
      Protocol.FormData := Dialog.SaveRtf;
    end;
  finally
    Dialog.Free;
  end;
end;

class function TdlgNote.RtfToPlainText(const Rtf: string): string;
var
  Helper: TRichEdit;
  Stream: TStringStream;
begin
  Result := '';
  if Rtf = '' then Exit;

  Helper := TRichEdit.Create(nil);
  try
    Helper.Parent := Application.MainForm;
    Helper.Visible := False;
    Stream := TStringStream.Create(Rtf);
    try
      Helper.Lines.LoadFromStream(Stream);
      // If it loaded as RTF, .Text gives plain text; if not, it's already plain
      Result := Helper.Text;
    finally
      Stream.Free;
    end;
  finally
    Helper.Free;
  end;
end;

procedure TdlgNote.LoadRtf(const Rtf: string);
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(Rtf);
  try
    reContent.Lines.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

function TdlgNote.SaveRtf: string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('');
  try
    reContent.Lines.SaveToStream(Stream);
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

procedure TdlgNote.ToggleStyle(AStyle: TFontStyle);
begin
  if AStyle in reContent.SelAttributes.Style then
    reContent.SelAttributes.Style := reContent.SelAttributes.Style - [AStyle]
  else
    reContent.SelAttributes.Style := reContent.SelAttributes.Style + [AStyle];
  reContent.SetFocus;
end;

procedure TdlgNote.btnBoldClick(Sender: TObject);
begin
  ToggleStyle(fsBold);
end;

procedure TdlgNote.btnItalicClick(Sender: TObject);
begin
  ToggleStyle(fsItalic);
end;

procedure TdlgNote.btnUnderlineClick(Sender: TObject);
begin
  ToggleStyle(fsUnderline);
end;

procedure TdlgNote.btnOKClick(Sender: TObject);
begin
  if Trim(edtTitle.Text) = '' then
  begin
    MessageDlg('Note title cannot be empty.', mtError, [mbOK], 0);
    edtTitle.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

end.
