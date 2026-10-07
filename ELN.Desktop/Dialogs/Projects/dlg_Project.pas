unit dlg_Project;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, RzButton, Vcl.ExtCtrls, RzPanel,
  Vcl.StdCtrls, Vcl.Mask, RzEdit, RzLabel, unit_DlgConstants;

type
  TdlgProject = class(TForm)
    RzPanel1: TRzPanel;
    RzPanel2: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    RzLabel1: TRzLabel;
    RzLabel2: TRzLabel;
    edTitle: TRzEdit;
    edComment: TRzEdit;
    cbArchived: TCheckBox;
    procedure edTitleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

  function ShowProjectDialog(const Mode: TDlgMode; Item: string;
    var Title, Comment: string; IsArchived: PBoolean = nil): boolean;

implementation

uses
  unit_DialogHelper;

{$R *.dfm}

function ShowProjectDialog(const Mode: TDlgMode; Item: string;
  var Title, Comment: string; IsArchived: PBoolean = nil): boolean;
var
  TitleValue, CommentValue: string;
  ArchivedValue: Boolean;
  ArchivedPtr: PBoolean;
begin
  // Copy var parameters to local variables for anonymous method capture
  TitleValue := Title;
  CommentValue := Comment;
  ArchivedPtr := IsArchived;
  if Assigned(ArchivedPtr) then
    ArchivedValue := ArchivedPtr^
  else
    ArchivedValue := False;

  Result := ExecuteDialog(TdlgProject,
    // Setup procedure
    procedure(Dialog: TForm)
    var
      D: TdlgProject;
    begin
      D := TdlgProject(Dialog);
      D.RzLabel1.Caption := UpperCase(Item[1]) + Copy(Item, 2) + ' title';
      D.cbArchived.Visible := Assigned(ArchivedPtr) and (Mode = dmEdit);
      D.cbArchived.Checked := ArchivedValue;
      case Mode of
        dmNew: begin
                 D.Caption := 'Add new ' + Item;
               end;
        dmEdit: begin
                  D.Caption := 'Edit ' + Item;
                  D.edTitle.Text := TitleValue;
                  D.edComment.Text := CommentValue;
                end;
      end;
    end,
    // Extract procedure
    procedure(Dialog: TForm)
    var
      D: TdlgProject;
    begin
      D := TdlgProject(Dialog);
      TitleValue   := D.edTitle.Text;
      CommentValue := D.edComment.Text;
      ArchivedValue := D.cbArchived.Checked;
    end
  );

  // Copy back to var parameters
  if Result then
  begin
    Title := TitleValue;
    Comment := CommentValue;
    if Assigned(IsArchived) then
      IsArchived^ := ArchivedValue;
  end;
end;

procedure TdlgProject.edTitleKeyDown(Sender: TObject; var Key: Word; Shift:
    TShiftState);
begin
  if Key = VK_RETURN then
    ModalResult := mrOk;
end;


end.
