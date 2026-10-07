unit unit_CommentModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Comment,
  unit_ELNDB_Dictionary;

type
  TCommentModel = class
  private
    FManager: TObjectManager;
    FDic: TCommentDictionary;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    function AddComment(ItemId, UserId: Integer; const UserName, CommentText: string): TComment;
    procedure UpdateComment(Comment: TComment);
    procedure DeleteComment(CommentId: Integer);
    function GetComments(ItemId: Integer): TComments;
    function GetCommentCount(ItemId: Integer): Integer;
    function GetCommentedItemIds(const ItemIds: TList<Integer>): TDictionary<Integer, Integer>;
    function GetLatestComment(ItemId: Integer): TComment;
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_TimeHelper;

{ TCommentModel }

constructor TCommentModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TCommentDictionary.Create;
end;

destructor TCommentModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TCommentModel.AddComment(ItemId, UserId: Integer;
  const UserName, CommentText: string): TComment;
begin
  Result := TComment.Create;
  Result.ItemId := ItemId;
  Result.UserId := UserId;
  Result.UserName := UserName;
  Result.Text := CommentText;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

procedure TCommentModel.UpdateComment(Comment: TComment);
begin
  Comment.ModifiedDate := UTCNow;
  FManager.Flush;
end;

procedure TCommentModel.DeleteComment(CommentId: Integer);
var
  Comment: TComment;
begin
  Comment := FManager.Find<TComment>(CommentId);
  if Assigned(Comment) then
  begin
    FManager.Remove(Comment);
    FManager.Flush;
  end;
end;

function TCommentModel.GetComments(ItemId: Integer): TComments;
begin
  Result := FManager.Find<TComment>
    .Where(FDic.ItemId = ItemId)
    .OrderBy(FDic.CreatedDate)
    .List;
end;

function TCommentModel.GetCommentCount(ItemId: Integer): Integer;
var
  Comments: TComments;
begin
  Comments := FManager.Find<TComment>
    .Where(FDic.ItemId = ItemId)
    .List;
  try
    Result := Comments.Count;
  finally
    Comments.Free;
  end;
end;

function TCommentModel.GetCommentedItemIds(const ItemIds: TList<Integer>): TDictionary<Integer, Integer>;
var
  AllComments: TComments;
  Comment: TComment;
  Count: Integer;
  Ids: TArray<Variant>;
  I: Integer;
begin
  Result := TDictionary<Integer, Integer>.Create;
  if (ItemIds = nil) or (ItemIds.Count = 0) then
    Exit;

  // Push the ItemId filter into SQL instead of loading the entire Comments
  // table and filtering in Pascal — this function is called on every tree
  // navigation and the full-scan form was the dominant latency on folders
  // with thousands of comments.
  SetLength(Ids, ItemIds.Count);
  for I := 0 to ItemIds.Count - 1 do
    Ids[I] := ItemIds[I];

  AllComments := FManager.Find<TComment>
    .Where(FDic.ItemId._In(Ids))
    .List;
  try
    for Comment in AllComments do
      if Result.TryGetValue(Comment.ItemId, Count) then
        Result[Comment.ItemId] := Count + 1
      else
        Result.Add(Comment.ItemId, 1);
  finally
    AllComments.Free;
  end;
end;

function TCommentModel.GetLatestComment(ItemId: Integer): TComment;
var
  Comments: TComments;
begin
  Result := nil;
  Comments := FManager.Find<TComment>
    .Where(FDic.ItemId = ItemId)
    .OrderBy(FDic.CreatedDate, False)
    .Take(1)
    .List;
  try
    if Comments.Count > 0 then
      Result := Comments[0];
  finally
    Comments.Free;
  end;
end;

end.
