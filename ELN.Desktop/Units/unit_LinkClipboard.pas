unit unit_LinkClipboard;

// Holds the item most recently marked as a link target, so "Link to '<Title>'"
// keeps working after the user navigates elsewhere to find the second item.
//
// Deliberately a unit-level singleton rather than a field on TframeItemTree:
// the item tree is rebuilt on every project/folder change, and the whole point
// of the copy/paste flow is that you copy a target, go somewhere else, and link
// from there.

interface

type
  TLinkClipboard = class
  private
    FItemId: Integer;
    FTitle: string;
  public
    procedure SetTarget(AItemId: Integer; const ATitle: string);
    procedure Clear;
    function HasTarget: Boolean;
    property ItemId: Integer read FItemId;
    property Title: string read FTitle;
  end;

var
  LinkClipboard: TLinkClipboard;

implementation

{ TLinkClipboard }

procedure TLinkClipboard.SetTarget(AItemId: Integer; const ATitle: string);
begin
  FItemId := AItemId;
  FTitle := ATitle;
end;

procedure TLinkClipboard.Clear;
begin
  FItemId := 0;
  FTitle := '';
end;

function TLinkClipboard.HasTarget: Boolean;
begin
  Result := FItemId > 0;
end;

initialization
  LinkClipboard := TLinkClipboard.Create;

finalization
  LinkClipboard.Free;

end.
