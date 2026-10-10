unit unit_ItemLinkMigrationSeed;

// Kept below ELN.Model so migrations and the model share one seed vocabulary
// without reversing the ELN.Model -> ELN.DB dependency.

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_LinkType;

type
  TItemLinkMigration = class
  public
    class procedure SeedLinkTypes(Mgr: TObjectManager); static;

    class function FindByForwardText(Mgr: TObjectManager;
      const AText: string): TLinkType; static;

    // Caller owns transaction lifetime.
    class procedure Run(Mgr: TObjectManager); static;

    class procedure NormalizeCaptions(Mgr: TObjectManager); static;

    class function Capitalize(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  unit_ItemLink,
  unit_TimeHelper;

type
  TLinkTypeSeed = record
    ForwardText: string;
    ReverseText: string;
    Description: string;
    SortOrder: Integer;
  end;

const
  SEED_TYPES: array[0..5] of TLinkTypeSeed = (
    (ForwardText: 'Related to';     ReverseText: 'Related to';
     Description: 'General cross-reference.';                          SortOrder: 10),
    (ForwardText: 'Derived from';   ReverseText: 'Precursor of';
     Description: 'This item was made or computed from the other.';    SortOrder: 20),
    (ForwardText: 'Uses data from'; ReverseText: 'Provided data for';
     Description: 'This item consumes the other item''s data.';        SortOrder: 30),
    (ForwardText: 'Supersedes';     ReverseText: 'Superseded by';
     Description: 'This item replaces the other.';                     SortOrder: 40),
    (ForwardText: 'Repeat of';      ReverseText: 'Repeated by';
     Description: 'A repeat run of the other item.';                   SortOrder: 50),
    (ForwardText: 'Part of';        ReverseText: 'Contains';
     Description: 'Compositional relationship.';                       SortOrder: 60)
  );

  IMPORTED_DESCRIPTION = 'Imported from free-text label';
  IMPORTED_SORTORDER   = 1000;


class function TItemLinkMigration.FindByForwardText(Mgr: TObjectManager;
  const AText: string): TLinkType;
var
  All: TLinkTypes;
  LT: TLinkType;
begin
  Result := nil;
  All := Mgr.Find<TLinkType>.List;
  try
    for LT in All do
      if SameText(Trim(LT.ForwardText), Trim(AText)) then
        Exit(LT);
  finally
    All.Free;
  end;
end;

class function TItemLinkMigration.Capitalize(const AText: string): string;
var
  S: string;
begin
  S := Trim(AText);
  if S = '' then
    Exit(S);
  Result := UpperCase(S[1]) + Copy(S, 2, MaxInt);
end;

class procedure TItemLinkMigration.NormalizeCaptions(Mgr: TObjectManager);
var
  All: TLinkTypes;
  LT: TLinkType;
  NewFwd, NewRev: string;
  Changed: Boolean;
begin
  Changed := False;
  All := Mgr.Find<TLinkType>.List;
  try
    for LT in All do
    begin
      NewFwd := Capitalize(LT.ForwardText);
      NewRev := Capitalize(LT.ReverseText);
      if (NewFwd = LT.ForwardText) and (NewRev = LT.ReverseText) then
        Continue;
      LT.ForwardText := NewFwd;
      LT.ReverseText := NewRev;
      Mgr.Update(LT);
      Changed := True;
    end;
    if Changed then
      Mgr.Flush;
  finally
    All.Free;
  end;
end;

class procedure TItemLinkMigration.SeedLinkTypes(Mgr: TObjectManager);
var
  I: Integer;
  LT: TLinkType;
begin
  for I := Low(SEED_TYPES) to High(SEED_TYPES) do
  begin
    if FindByForwardText(Mgr, SEED_TYPES[I].ForwardText) <> nil then
      Continue;

    LT := TLinkType.Create;
    LT.ForwardText := SEED_TYPES[I].ForwardText;
    LT.ReverseText := SEED_TYPES[I].ReverseText;
    LT.Description := SEED_TYPES[I].Description;
    LT.SortOrder := SEED_TYPES[I].SortOrder;
    LT.CreatedDate := UTCNow;
    Mgr.Save(LT);
    Mgr.Flush;
  end;
end;

class procedure TItemLinkMigration.Run(Mgr: TObjectManager);
var
  Links: TItemLinks;
  Link: TItemLink;
  Lbl: string;
  Target: TLinkType;
  Swap: Integer;

  // Legacy labels the application itself wrote, plus obvious synonyms. Without
  // this table 'taken from' matches no seeded caption and would wrongly fall
  // through to auto-creating a junk type.
  function ResolveAlias(const ALabel: string): string;
  begin
    if SameText(ALabel, 'taken from') or SameText(ALabel, 'copy of') or
       SameText(ALabel, 'based on') then
      Result := 'derived from'
    else if SameText(ALabel, 'related') or SameText(ALabel, 'see also') or
            SameText(ALabel, 'linked') then
      Result := 'related to'
    else
      Result := ALabel;
  end;

begin
  SeedLinkTypes(Mgr);

  Links := Mgr.Find<TItemLink>.List;
  try
    for Link in Links do
    begin
      if Assigned(Link.LinkType) then
        Continue;

      Lbl := Trim(Link.Label_);

      // Pre-fix DuplicateItem stored source = original, target = copy, which
      // reads backwards. Flip so the copy is 'derived from' the original.
      if SameText(Lbl, 'taken from') then
      begin
        Swap := Link.SourceItemId;
        Link.SourceItemId := Link.TargetItemId;
        Link.TargetItemId := Swap;
      end;

      if Lbl = '' then
        Target := FindByForwardText(Mgr, 'related to')
      else
      begin
        Target := FindByForwardText(Mgr, ResolveAlias(Lbl));
        if Target = nil then
        begin
          Target := TLinkType.Create;
          Target.ForwardText := Capitalize(Lbl);
          Target.ReverseText := Capitalize(Lbl);
          Target.Description := IMPORTED_DESCRIPTION;
          Target.SortOrder := IMPORTED_SORTORDER;
          Target.CreatedDate := UTCNow;
          Mgr.Save(Target);
          Mgr.Flush;
        end;
      end;

      Link.LinkType := Target;
      Mgr.Update(Link);
    end;
    Mgr.Flush;
  finally
    Links.Free;
  end;
end;

end.
