unit unit_ItemLinkModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_ItemLink,
  unit_LinkType,
  unit_ELNDB_Dictionary;

type
  TItemLinkInfo = record
    LinkId: Integer;
    LinkedItemId: Integer;
    LinkedItemTitle: string;
    LinkedItemProjectId: Integer;
    LinkedProjectName: string;
    LinkTypeId: Integer;
    /// <summary>The relation phrase as read from the queried item's end:
    /// the type's forward caption when this item is the source, its reverse
    /// caption when it is the target. Resolved here so no caller ever has to
    /// reason about link direction.</summary>
    RelationText: string;
    /// <summary>Legacy free-text label, kept for provenance. Not for display.</summary>
    Label_: string;
    Notes: string;
    CreatedDate: TDateTime;
    IsSource: Boolean;
  end;

  TItemLinkModel = class
  private
    FManager: TObjectManager;
    FDic: TItemLinkDictionary;
    FAccessibleProjects: TDictionary<Integer, Boolean>;
    FUnrestricted: Boolean;
    function CanSeeProject(AProjectId: Integer): Boolean;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    /// <summary>Restricts which links are returned to those whose far end sits
    /// in a readable project. Without this the model is unrestricted, which is
    /// how non-UI callers (tests, migrations) get the raw view.</summary>
    procedure SetAccessFilter(const AProjectIds: TArray<Integer>;
      AUnrestricted: Boolean);

    function AddLink(SourceId, TargetId, LinkTypeId: Integer;
      const ANotes: string; CreatedBy: Integer): TItemLink;
    /// <summary>For callers that know the relation by caption rather than by id
    /// — the duplicate-item flow, which always means 'derived from'. Returns nil
    /// when the caption is not in the vocabulary.</summary>
    function AddLinkByForwardText(SourceId, TargetId: Integer;
      const AForwardText, ANotes: string; CreatedBy: Integer): TItemLink;
    procedure UpdateLink(LinkId, LinkTypeId: Integer; const ANotes: string);
    procedure RemoveLink(LinkId: Integer);
    function GetLinksForItem(ItemId: Integer): TArray<TItemLinkInfo>;
    function GetLinkCount(ItemId: Integer): Integer;
    function IsLinked(ItemId1, ItemId2: Integer): Boolean;
    procedure RemoveAllLinks(ItemId: Integer);
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_Item,
  unit_Project,
  unit_ItemLinkMigrationSeed,
  unit_TimeHelper;

{ TItemLinkModel }

constructor TItemLinkModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TItemLinkDictionary.Create;
  FAccessibleProjects := TDictionary<Integer, Boolean>.Create;
  // Unrestricted until a caller says otherwise, so behaviour is unchanged for
  // every caller that does not care about per-project visibility.
  FUnrestricted := True;
end;

destructor TItemLinkModel.Destroy;
begin
  FreeAndNil(FAccessibleProjects);
  FreeAndNil(FDic);
  inherited;
end;

procedure TItemLinkModel.SetAccessFilter(const AProjectIds: TArray<Integer>;
  AUnrestricted: Boolean);
var
  Id: Integer;
begin
  FUnrestricted := AUnrestricted;
  FAccessibleProjects.Clear;
  for Id in AProjectIds do
    FAccessibleProjects.AddOrSetValue(Id, True);
end;

function TItemLinkModel.CanSeeProject(AProjectId: Integer): Boolean;
begin
  Result := FUnrestricted or FAccessibleProjects.ContainsKey(AProjectId);
end;

function TItemLinkModel.AddLink(SourceId, TargetId, LinkTypeId: Integer;
  const ANotes: string; CreatedBy: Integer): TItemLink;
var
  LinkType: TLinkType;
begin
  if SourceId = TargetId then
    Exit(nil);
  if IsLinked(SourceId, TargetId) then
    Exit(nil);

  LinkType := FManager.Find<TLinkType>(LinkTypeId);
  if not Assigned(LinkType) then
    Exit(nil);

  Result := TItemLink.Create;
  Result.SourceItemId := SourceId;
  Result.TargetItemId := TargetId;
  Result.LinkType := LinkType;
  // Label is still Required on the table. Written as a snapshot of the caption
  // at creation time so the row stays readable on its own; never read back for
  // display, which always resolves through LinkType.
  Result.Label_ := LinkType.ForwardText;
  Result.Notes := ANotes;
  Result.CreatedBy := CreatedBy;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

function TItemLinkModel.AddLinkByForwardText(SourceId, TargetId: Integer;
  const AForwardText, ANotes: string; CreatedBy: Integer): TItemLink;
var
  LinkType: TLinkType;
begin
  LinkType := TItemLinkMigration.FindByForwardText(FManager, AForwardText);
  if not Assigned(LinkType) then
    Exit(nil);
  Result := AddLink(SourceId, TargetId, LinkType.Id, ANotes, CreatedBy);
end;

procedure TItemLinkModel.UpdateLink(LinkId, LinkTypeId: Integer;
  const ANotes: string);
var
  Link: TItemLink;
  LinkType: TLinkType;
begin
  Link := FManager.Find<TItemLink>(LinkId);
  if not Assigned(Link) then Exit;

  LinkType := FManager.Find<TLinkType>(LinkTypeId);
  if Assigned(LinkType) then
  begin
    Link.LinkType := LinkType;
    Link.Label_ := LinkType.ForwardText;
  end;
  Link.Notes := ANotes;
  FManager.Update(Link);
  FManager.Flush;
end;

procedure TItemLinkModel.RemoveLink(LinkId: Integer);
var
  Link: TItemLink;
begin
  Link := FManager.Find<TItemLink>(LinkId);
  if Assigned(Link) then
  begin
    FManager.Remove(Link);
    FManager.Flush;
  end;
end;

function TItemLinkModel.GetLinksForItem(ItemId: Integer): TArray<TItemLinkInfo>;
var
  SourceLinks, TargetLinks: TItemLinks;
  Link: TItemLink;
  Info: TItemLinkInfo;
  List: TList<TItemLinkInfo>;
  LinkedItem: TItem;
  Project: TProject;

  // Resolves the far end and applies the access filter. Returns False when the
  // link must be hidden. A far item that cannot be found at all is kept: the
  // row carries no project to judge, and orphan rows behaved this way before
  // the filter existed.
  function ResolveFarEnd(AFarItemId: Integer; var AInfo: TItemLinkInfo): Boolean;
  begin
    Result := True;
    LinkedItem := FManager.Find<TItem>(AFarItemId);
    if not Assigned(LinkedItem) then Exit;

    if not CanSeeProject(LinkedItem.ProjectID) then
      Exit(False);

    AInfo.LinkedItemTitle := LinkedItem.Title;
    AInfo.LinkedItemProjectId := LinkedItem.ProjectID;
    Project := FManager.Find<TProject>(LinkedItem.ProjectID);
    if Assigned(Project) then
      AInfo.LinkedProjectName := Project.Title;
  end;

begin
  List := TList<TItemLinkInfo>.Create;
  try
    // Links where this item is the source: the forward caption reads correctly.
    SourceLinks := FManager.Find<TItemLink>
      .Where(FDic.SourceItemId = ItemId)
      .List;
    try
      for Link in SourceLinks do
      begin
        Info := Default(TItemLinkInfo);
        Info.LinkId := Link.Id;
        Info.LinkedItemId := Link.TargetItemId;
        Info.Label_ := Link.Label_;
        Info.Notes := Link.Notes;
        Info.CreatedDate := Link.CreatedDate;
        Info.IsSource := True;

        if Assigned(Link.LinkType) then
        begin
          Info.LinkTypeId := Link.LinkType.Id;
          Info.RelationText := Link.LinkType.ForwardText;
        end;

        if ResolveFarEnd(Link.TargetItemId, Info) then
          List.Add(Info);
      end;
    finally
      SourceLinks.Free;
    end;

    // Links where this item is the target: the reverse caption reads correctly.
    TargetLinks := FManager.Find<TItemLink>
      .Where(FDic.TargetItemId = ItemId)
      .List;
    try
      for Link in TargetLinks do
      begin
        Info := Default(TItemLinkInfo);
        Info.LinkId := Link.Id;
        Info.LinkedItemId := Link.SourceItemId;
        Info.Label_ := Link.Label_;
        Info.Notes := Link.Notes;
        Info.CreatedDate := Link.CreatedDate;
        Info.IsSource := False;

        if Assigned(Link.LinkType) then
        begin
          Info.LinkTypeId := Link.LinkType.Id;
          Info.RelationText := Link.LinkType.ReverseText;
        end;

        if ResolveFarEnd(Link.SourceItemId, Info) then
          List.Add(Info);
      end;
    finally
      TargetLinks.Free;
    end;

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// Derived from the same query the list uses, so the tree badge can never
// disagree with what the details panel shows.
function TItemLinkModel.GetLinkCount(ItemId: Integer): Integer;
begin
  Result := Length(GetLinksForItem(ItemId));
end;

function TItemLinkModel.IsLinked(ItemId1, ItemId2: Integer): Boolean;
var
  Links: TItemLinks;
begin
  // Check source->target direction
  Links := FManager.Find<TItemLink>
    .Where(
      (FDic.SourceItemId = ItemId1) and
      (FDic.TargetItemId = ItemId2))
    .Take(1)
    .List;
  try
    if Links.Count > 0 then
      Exit(True);
  finally
    Links.Free;
  end;

  // Check target->source direction
  Links := FManager.Find<TItemLink>
    .Where(
      (FDic.SourceItemId = ItemId2) and
      (FDic.TargetItemId = ItemId1))
    .Take(1)
    .List;
  try
    Result := Links.Count > 0;
  finally
    Links.Free;
  end;
end;

procedure TItemLinkModel.RemoveAllLinks(ItemId: Integer);
var
  Links: TItemLinks;
  Link: TItemLink;
begin
  Links := FManager.Find<TItemLink>
    .Where(
      (FDic.SourceItemId = ItemId) or
      (FDic.TargetItemId = ItemId))
    .List;
  try
    for Link in Links do
      FManager.Remove(Link);
    FManager.Flush;
  finally
    Links.Free;
  end;
end;

end.
