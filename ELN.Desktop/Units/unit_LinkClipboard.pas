unit unit_LinkClipboard;

// Keep the clipboard outside the item tree, which is rebuilt on project or folder changes.

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
