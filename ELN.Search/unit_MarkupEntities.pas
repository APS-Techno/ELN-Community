unit unit_MarkupEntities;

interface

function LookupMarkupEntity(const Name: string; Html: Boolean; out Decoded: string): Boolean;

implementation

uses
  System.SysUtils;

const
  Latin1EntityNames: array[0..95] of string = (
    'nbsp', 'iexcl', 'cent', 'pound', 'curren', 'yen', 'brvbar', 'sect', 'uml', 'copy', 'ordf', 'laquo', 'not',
    'shy', 'reg', 'macr', 'deg', 'plusmn', 'sup2', 'sup3', 'acute', 'micro', 'para', 'middot', 'cedil', 'sup1',
    'ordm', 'raquo', 'frac14', 'frac12', 'frac34', 'iquest', 'Agrave', 'Aacute', 'Acirc', 'Atilde', 'Auml',
    'Aring', 'AElig', 'Ccedil', 'Egrave', 'Eacute', 'Ecirc', 'Euml', 'Igrave', 'Iacute', 'Icirc', 'Iuml', 'ETH',
    'Ntilde', 'Ograve', 'Oacute', 'Ocirc', 'Otilde', 'Ouml', 'times', 'Oslash', 'Ugrave', 'Uacute', 'Ucirc',
    'Uuml', 'Yacute', 'THORN', 'szlig', 'agrave', 'aacute', 'acirc', 'atilde', 'auml', 'aring', 'aelig',
    'ccedil', 'egrave', 'eacute', 'ecirc', 'euml', 'igrave', 'iacute', 'icirc', 'iuml', 'eth', 'ntilde',
    'ograve', 'oacute', 'ocirc', 'otilde', 'ouml', 'divide', 'oslash', 'ugrave', 'uacute', 'ucirc', 'uuml',
    'yacute', 'thorn', 'yuml');

type
  TNamedEntity = record
    Name: string;
    Code: Integer;
  end;

const
  OtherEntities: array[0..69] of TNamedEntity = (
    (Name: 'quot'; Code: 34), (Name: 'amp'; Code: 38), (Name: 'apos'; Code: 39), (Name: 'lt'; Code: 60),
    (Name: 'gt'; Code: 62), (Name: 'ensp'; Code: 8194), (Name: 'emsp'; Code: 8195), (Name: 'thinsp'; Code: 8201),
    (Name: 'zwnj'; Code: 8204), (Name: 'zwj'; Code: 8205), (Name: 'ndash'; Code: 8211), (Name: 'mdash'; Code: 8212),
    (Name: 'lsquo'; Code: 8216), (Name: 'rsquo'; Code: 8217), (Name: 'sbquo'; Code: 8218),
    (Name: 'ldquo'; Code: 8220), (Name: 'rdquo'; Code: 8221), (Name: 'bdquo'; Code: 8222),
    (Name: 'dagger'; Code: 8224), (Name: 'Dagger'; Code: 8225), (Name: 'bull'; Code: 8226),
    (Name: 'hellip'; Code: 8230), (Name: 'permil'; Code: 8240), (Name: 'prime'; Code: 8242),
    (Name: 'Prime'; Code: 8243), (Name: 'lsaquo'; Code: 8249), (Name: 'rsaquo'; Code: 8250),
    (Name: 'euro'; Code: 8364), (Name: 'trade'; Code: 8482), (Name: 'larr'; Code: 8592), (Name: 'uarr'; Code: 8593),
    (Name: 'rarr'; Code: 8594), (Name: 'darr'; Code: 8595), (Name: 'harr'; Code: 8596), (Name: 'part'; Code: 8706),
    (Name: 'sum'; Code: 8721), (Name: 'minus'; Code: 8722), (Name: 'radic'; Code: 8730), (Name: 'infin'; Code: 8734),
    (Name: 'int'; Code: 8747), (Name: 'asymp'; Code: 8776), (Name: 'ne'; Code: 8800), (Name: 'le'; Code: 8804),
    (Name: 'ge'; Code: 8805), (Name: 'Alpha'; Code: 913), (Name: 'Beta'; Code: 914), (Name: 'Gamma'; Code: 915),
    (Name: 'Delta'; Code: 916), (Name: 'Epsilon'; Code: 917), (Name: 'Zeta'; Code: 918), (Name: 'Eta'; Code: 919),
    (Name: 'Theta'; Code: 920), (Name: 'Lambda'; Code: 923), (Name: 'Pi'; Code: 928), (Name: 'Sigma'; Code: 931),
    (Name: 'Phi'; Code: 934), (Name: 'Psi'; Code: 936), (Name: 'Omega'; Code: 937), (Name: 'alpha'; Code: 945),
    (Name: 'beta'; Code: 946), (Name: 'gamma'; Code: 947), (Name: 'delta'; Code: 948), (Name: 'epsilon'; Code: 949),
    (Name: 'theta'; Code: 952), (Name: 'lambda'; Code: 955), (Name: 'mu'; Code: 956), (Name: 'pi'; Code: 960),
    (Name: 'sigma'; Code: 963), (Name: 'phi'; Code: 966), (Name: 'omega'; Code: 969));

function CodePointToString(Code: Cardinal): string;
begin
  if Code < $10000 then
    Result := Char(Code)
  else
  begin
    Dec(Code, $10000);
    Result := Char($D800 + (Code shr 10)) + Char($DC00 + (Code and $3FF));
  end;
end;

function LookupMarkupEntity(const Name: string; Html: Boolean; out Decoded: string): Boolean;
var
  I, Code: Integer;
  Digits: string;
  Value: Int64;
  C: Char;
begin
  Decoded := '';
  Result := False;
  if Name = '' then
    Exit;
  if Name[1] = '#' then
  begin
    if (Length(Name) > 2) and ((Name[2] = 'x') or (Name[2] = 'X')) then
    begin
      Digits := Copy(Name, 3, MaxInt);
      Value := 0;
      for C in Digits do
      begin
        if (C >= '0') and (C <= '9') then
          Value := Value * 16 + (Ord(C) - Ord('0'))
        else if (C >= 'a') and (C <= 'f') then
          Value := Value * 16 + (Ord(C) - Ord('a') + 10)
        else if (C >= 'A') and (C <= 'F') then
          Value := Value * 16 + (Ord(C) - Ord('A') + 10)
        else
          Exit;
        if Value > $10FFFF then
          Exit;
      end;
    end
    else
    begin
      Digits := Copy(Name, 2, MaxInt);
      if Digits = '' then
        Exit;
      Value := 0;
      for C in Digits do
      begin
        if (C < '0') or (C > '9') then
          Exit;
        Value := Value * 10 + (Ord(C) - Ord('0'));
        if Value > $10FFFF then
          Exit;
      end;
    end;
    if (Value = 0) or ((Value >= $D800) and (Value <= $DFFF)) then
      Exit;
    Decoded := CodePointToString(Value);
    Exit(True);
  end;
  for I := 0 to 4 do
    if OtherEntities[I].Name = Name then
    begin
      Decoded := Char(OtherEntities[I].Code);
      Exit(True);
    end;
  if not Html then
    Exit;
  for I := Low(Latin1EntityNames) to High(Latin1EntityNames) do
    if Latin1EntityNames[I] = Name then
    begin
      Decoded := Char(160 + I);
      Exit(True);
    end;
  for I := 5 to High(OtherEntities) do
  begin
    Code := OtherEntities[I].Code;
    if OtherEntities[I].Name = Name then
    begin
      Decoded := Char(Code);
      Exit(True);
    end;
  end;
end;

end.
