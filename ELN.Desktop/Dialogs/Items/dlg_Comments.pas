unit dlg_Comments;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Dialogs,
  unit_Comment;

type
  TdlgComments = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    lblCount: TLabel;
    lvComments: TListView;
    pnlInput: TPanel;
    memoComment: TMemo;
    btnAdd: TButton;
    pnlBottom: TPanel;
    btnEdit: TButton;
    btnDelete: TButton;
    btnClose: TButton;
    procedure btnAddClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure lvCommentsCustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
  private
    FItemId: Integer;
    FItemTitle: string;
    FUserId: Integer;
    FUserName: string;
    procedure LoadComments;
  public
    class procedure ShowComments(ItemId: Integer; const ItemTitle: string;
      UserId: Integer; const UserName: string);
  end;

implementation

uses
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

{ TdlgComments }

procedure TdlgComments.lvCommentsCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  if [cdsSelected, cdsFocused] * State <> [] then
    Exit;
  if (Item.SubItems.Count > 0) and SameText(Item.SubItems[0], FUserName) then
    Sender.Canvas.Brush.Color := $FFFCE8
  else
    Sender.Canvas.Brush.Color := $F0FAFA;
end;

procedure TdlgComments.LoadComments;
var
  Comments: TComments;
  Comment: TComment;
  LI: TListItem;
begin
  lvComments.Items.Clear;
  Comments := Model.Comments.GetComments(FItemId);
  try
    for Comment in Comments do
    begin
      LI := lvComments.Items.Add;
      LI.Caption := DateTimeToStr(FromUTC(Comment.CreatedDate));
      LI.SubItems.Add(Comment.UserName);
      LI.SubItems.Add(Comment.Text);
      LI.Data := Pointer(Comment.Id);
    end;
    lblCount.Caption := IntToStr(Comments.Count) + ' comments';
  finally
    Comments.Free;
  end;
end;

procedure TdlgComments.btnAddClick(Sender: TObject);
var
  CommentText: string;
begin
  CommentText := Trim(memoComment.Text);
  if CommentText = '' then
  begin
    MessageDlg('Please enter a comment.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Model.Comments.AddComment(FItemId, FUserId, FUserName, CommentText);
  memoComment.Clear;
  LoadComments;
end;

procedure TdlgComments.btnEditClick(Sender: TObject);
var
  LI: TListItem;
  CommentId: Integer;
  Comment: TComment;
  Comments: TComments;
  C: TComment;
  NewText: string;
begin
  LI := lvComments.Selected;
  if not Assigned(LI) then Exit;

  CommentId := Integer(LI.Data);
  Comments := Model.Comments.GetComments(FItemId);
  try
    Comment := nil;
    for C in Comments do
      if C.Id = CommentId then
      begin
        Comment := C;
        Break;
      end;
    if not Assigned(Comment) then Exit;

    if Comment.UserId <> FUserId then
    begin
      MessageDlg('You can only edit your own comments.', mtWarning, [mbOK], 0);
      Exit;
    end;

    NewText := Comment.Text;
    if InputQuery('Edit Comment', 'Comment:', NewText) and (Trim(NewText) <> '') then
    begin
      Comment.Text := Trim(NewText);
      Model.Comments.UpdateComment(Comment);
      LoadComments;
    end;
  finally
    Comments.Free;
  end;
end;

procedure TdlgComments.btnDeleteClick(Sender: TObject);
var
  LI: TListItem;
  CommentId: Integer;
begin
  LI := lvComments.Selected;
  if not Assigned(LI) then Exit;

  CommentId := Integer(LI.Data);

  if MessageDlg('Delete this comment?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    Model.Comments.DeleteComment(CommentId);
    LoadComments;
  end;
end;

class procedure TdlgComments.ShowComments(ItemId: Integer;
  const ItemTitle: string; UserId: Integer; const UserName: string);
var
  Dlg: TdlgComments;
begin
  Dlg := TdlgComments.Create(Application);
  try
    Dlg.FItemId := ItemId;
    Dlg.FItemTitle := ItemTitle;
    Dlg.FUserId := UserId;
    Dlg.FUserName := UserName;
    Dlg.Caption := 'Comments - ' + ItemTitle;
    Dlg.lblTitle.Caption := 'Discussion for "' + ItemTitle + '"';
    Dlg.LoadComments;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
