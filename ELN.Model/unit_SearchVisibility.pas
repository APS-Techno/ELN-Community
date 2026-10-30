unit unit_SearchVisibility;

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_ProjectAccessPolicy;

function SearchVisibleProjectIds(Manager: TObjectManager;
  const Policy: IProjectAccessPolicy; User: TUser): TArray<Integer>;

implementation

uses
  System.Generics.Collections,
  System.Variants,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Projections,
  unit_Project;

function AllProjectIds(Manager: TObjectManager): TArray<Integer>;
var
  Rows: TObjectList<TCriteriaResult>;
  I: Integer;
begin
  Rows := Manager.Find<TProject>
    .Select(TProjections.ProjectionList.Add(TProjections.Prop('Id').As_('Id')))
    .ListValues;
  try
    SetLength(Result, Rows.Count);
    for I := 0 to Rows.Count - 1 do
      Result[I] := Integer(Rows[I].Values['Id']);
  finally
    Rows.Free;
  end;
end;

function SearchVisibleProjectIds(Manager: TObjectManager;
  const Policy: IProjectAccessPolicy; User: TUser): TArray<Integer>;
var
  Visible: TDictionary<Integer, Boolean>;
begin
  Visible := Policy.VisibleProjectIds(Manager, User);
  if Visible = nil then
    Exit(AllProjectIds(Manager));
  try
    Result := Visible.Keys.ToArray;
  finally
    Visible.Free;
  end;
end;

end.
