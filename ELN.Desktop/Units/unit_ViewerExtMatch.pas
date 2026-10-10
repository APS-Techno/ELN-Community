unit unit_ViewerExtMatch;

{ Match dotted suffixes, not ExtractFileExt, so compound extensions win over
  generic ones independently of package load order. The leading dot prevents partial-extension matches. }

interface

function ExtMatchScore(const AFileName, APluginExts: string): Integer;

implementation

uses
  System.SysUtils, System.StrUtils;

function ExtMatchScore(const AFileName, APluginExts: string): Integer;
var
  Raw, Token, Name: string;
begin
  Result := 0;
  // Ext = '' is the shell-preview fallback plugin; it is selected by its own
  // explicit branch in the hosts, never by scoring.
  if (AFileName = '') or (APluginExts = '') then Exit;

  Name := ExtractFileName(AFileName);
  for Raw in APluginExts.Split([';']) do
  begin
    Token := Trim(Raw);
    if (Token = '') or (Length(Token) <= Result) then Continue;
    if EndsText(Token, Name) then
      Result := Length(Token);
  end;
end;

end.
