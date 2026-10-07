unit unit_ViewerExtMatch;

{ Scores how specifically a viewer plugin's GetParams.Ext declaration claims a
  file. Tokens are tested as suffixes of the file NAME rather than compared to
  ExtractFileExt, so compound extensions work:

    ExtMatchScore('Deposition_RuC_2026-08-12_09-14-03.depo.json',
                  '.tsv;.depo.json')  = 10
    ExtMatchScore(same, '.json')                                =  5

  Hosts pick the highest-scoring plugin, so '.depo.json' beats '.json' and BPL
  load order no longer decides routing.

  A bare extension is a valid input - ExtMatchScore('.html', '.html;.htm') = 5 -
  so existing FindPlugin('.html') callers keep working unchanged.

  Every declared token starts with '.', which is what keeps suffix matching from
  aliasing: 'run.metadata' does not end with '.data', and 'build.cmd' does not
  end with '.md'. See test_ViewerExtMatch. }

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
