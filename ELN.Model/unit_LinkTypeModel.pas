unit unit_LinkTypeModel;

interface

uses
  SysUtils,
  Aurelius.Bind.Dataset,
  Aurelius.Engine.ObjectManager,
  System.Generics.Collections,
  unit_TELNModel,
  unit_LinkType,
  unit_ItemLink,
  unit_ItemLinkMigrationSeed,
  unit_TimeHelper;

type
  TLinkTypeModel = class(TELNModel)
    private
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      procedure OpenDataSet; override;

      function GetLinkTypes: TLinkTypes;
      function GetType(const ID: Integer): TLinkType;
      function FindByForwardText(const AText: string): TLinkType;
      function Add(const AForward, AReverse, ADescription: string;
        ASortOrder: Integer): TLinkType;
      function CanDelete(ID: Integer): string;
      procedure CreateDefaultData;
  end;

implementation

{ TLinkTypeModel }

constructor TLinkTypeModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
end;

function TLinkTypeModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

procedure TLinkTypeModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TLinkType>);
  FDataSet.Open;
end;

function TLinkTypeModel.GetLinkTypes: TLinkTypes;
begin
  Result := FManager.Find<TLinkType>.OrderBy('SortOrder').List;
end;

function TLinkTypeModel.GetType(const ID: Integer): TLinkType;
begin
  Result := FManager.Find<TLinkType>(ID);
end;

// Case-insensitive, trimmed lookup. Delegated so the schema migration and the
// running application resolve captions by identical rules.
function TLinkTypeModel.FindByForwardText(const AText: string): TLinkType;
begin
  Result := TItemLinkMigration.FindByForwardText(FManager, AText);
end;

function TLinkTypeModel.Add(const AForward, AReverse, ADescription: string;
  ASortOrder: Integer): TLinkType;
begin
  Result := TLinkType.Create;
  Result.ForwardText := AForward;
  Result.ReverseText := AReverse;
  Result.Description := ADescription;
  Result.SortOrder := ASortOrder;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

function TLinkTypeModel.CanDelete(ID: Integer): string;
var
  AllLinks: TItemLinks;
  Link: TItemLink;
  UseCount: Integer;
begin
  Result := '';
  UseCount := 0;
  AllLinks := FManager.Find<TItemLink>.List;
  try
    for Link in AllLinks do
      if Assigned(Link.LinkType) and (Link.LinkType.Id = ID) then
        Inc(UseCount);
  finally
    AllLinks.Free;
  end;

  if UseCount > 0 then
    Result := Format('Cannot delete: used by %d link(s).', [UseCount]);
end;

// Delegated to the ELN.DB seed unit, which owns the canonical vocabulary so a
// fresh install and an upgraded database get byte-identical relation captions.
// Insert-if-absent: re-running against a database whose vocabulary an admin has
// edited neither duplicates entries nor resurrects deleted ones.
procedure TLinkTypeModel.CreateDefaultData;
begin
  TItemLinkMigration.SeedLinkTypes(FManager);
end;

end.
