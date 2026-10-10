unit unit_MarkdownAttachmentResolver;

// Logical attachment names omit the stored "[ID]" prefix. Resolve them against
// the authoritative file list before the browser uses the attachment directory.

interface

uses
  System.SysUtils;

// Non-empty AFiles is authoritative; otherwise enumerate ADir.
function RewriteAttachmentRefs(const AMarkdown, ADir: string;
  const AFiles: TArray<string> = nil): string;

// Input is a raw filename/path, never an already encoded URL.
function EncodeAttachmentFileName(const AName: string): string;
function MarkdownFileUrl(const APath: string): string;
function IsMarkdownShellUrl(const AUrl, AShellUrl: string): Boolean;

implementation

uses
  System.RegularExpressions, System.IOUtils, System.StrUtils,
  System.NetEncoding, System.Generics.Collections;

type
  TLogicalMap = TDictionary<string, string>;

  // TMatchEvaluator is declared `of object` in System.RegularExpressions, so
  // an instance method is a valid callback.
  TAttachmentEvaluator = class
  private
    FMap: TLogicalMap;
  public
    constructor Create(AMap: TLogicalMap);
    function Evaluate(const M: TMatch): string;
  end;

constructor TAttachmentEvaluator.Create(AMap: TLogicalMap);
begin
  inherited Create;
  FMap := AMap;
end;

function IsRemoteOrAbsolute(const AUrl: string): Boolean;
const
  Schemes: array[0..5] of string = (
    'http://', 'https://', 'file://', 'eln://', 'mailto:', 'data:');
var
  Lower, Scheme: string;
begin
  if AUrl = '' then Exit(True);
  case AUrl[1] of
    '/', '\', '#': Exit(True);
  end;
  if (Length(AUrl) >= 2) and (AUrl[2] = ':') and
     CharInSet(AUrl[1], ['A'..'Z', 'a'..'z']) then
    Exit(True);
  Lower := LowerCase(AUrl);
  for Scheme in Schemes do
    if StartsStr(Scheme, Lower) then Exit(True);
  Result := False;
end;

function EncodeAttachmentFileName(const AName: string): string;
var
  Bytes: TBytes;
  B: Byte;
  Builder: TStringBuilder;
begin
  Bytes := TEncoding.UTF8.GetBytes(AName);
  Builder := TStringBuilder.Create;
  try
    for B in Bytes do
      if CharInSet(Char(B), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~']) then
        Builder.Append(Char(B))
      else
        Builder.Append('%' + IntToHex(B, 2));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function MarkdownFileUrl(const APath: string): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  Parts := StringReplace(APath, '\', '/', [rfReplaceAll]).Split(['/']);
  for I := 0 to High(Parts) do
    // Preserve the Windows drive separator, not filename punctuation.
    if not ((I = 0) and (Length(Parts[I]) = 2) and (Parts[I][2] = ':')) then
      Parts[I] := EncodeAttachmentFileName(Parts[I]);
  Result := string.Join('/', Parts);
  if StartsStr('//', Result) then
    Result := 'file:' + Result
  else
    Result := 'file:///' + Result;
end;

function IsMarkdownShellUrl(const AUrl, AShellUrl: string): Boolean;
var
  Url: string;
  Fragment: Integer;
begin
  Url := AUrl;
  Fragment := Pos('#', Url);
  if Fragment > 0 then SetLength(Url, Fragment - 1);
  Result := SameText(TNetEncoding.URL.Decode(
    StringReplace(Url, '+', '%2B', [rfReplaceAll])),
    TNetEncoding.URL.Decode(
    StringReplace(AShellUrl, '+', '%2B', [rfReplaceAll])));
end;

function BuildLogicalMapFromList(const AFiles: TArray<string>): TLogicalMap;
var
  FilePath, Name: string;
  M: TMatch;
begin
  Result := TLogicalMap.Create;
  for FilePath in AFiles do
  begin
    Name := ExtractFileName(FilePath);
    M := TRegEx.Match(Name, '^\[\d+\](.+)$');
    if M.Success then
    begin
      Result.AddOrSetValue(LowerCase(M.Groups[1].Value), Name);
      Result.AddOrSetValue(LowerCase(Name), Name);
    end;
  end;
end;

function BuildLogicalMapFromDir(const ADir: string): TLogicalMap;
begin
  if (ADir = '') or (not TDirectory.Exists(ADir)) then
    Exit(TLogicalMap.Create);
  Result := BuildLogicalMapFromList(TDirectory.GetFiles(ADir));
end;

function TAttachmentEvaluator.Evaluate(const M: TMatch): string;
var
  Prefix, AltText, Url, TitlePart, Actual, DecodedKey: string;
begin
  Prefix    := M.Groups[1].Value;
  AltText   := M.Groups[2].Value;
  Url       := M.Groups[3].Value;
  TitlePart := M.Groups[4].Value;

  if IsRemoteOrAbsolute(Url) then Exit(M.Value);

  // URL.Decode treats '+' as a form space; a path's literal '+' is not a space.
  DecodedKey := TNetEncoding.URL.Decode(
    StringReplace(Url, '+', '%2B', [rfReplaceAll]));
  if not FMap.TryGetValue(LowerCase(DecodedKey), Actual) then Exit(M.Value);
  if not SameText(DecodedKey, Actual) then
    DecodedKey := Copy(Actual, 1, Pos(']', Actual)) + DecodedKey;

  Result := Format('%s[%s](%s%s)',
    [Prefix, AltText, EncodeAttachmentFileName(DecodedKey), TitlePart]);
end;

function RewriteAttachmentRefs(const AMarkdown, ADir: string;
  const AFiles: TArray<string>): string;
var
  Map: TLogicalMap;
  Evaluator: TAttachmentEvaluator;
  Re: TRegEx;
begin
  if Length(AFiles) > 0 then
    Map := BuildLogicalMapFromList(AFiles)
  else
    Map := BuildLogicalMapFromDir(ADir);
  try
    if Map.Count = 0 then Exit(AMarkdown);
    Evaluator := TAttachmentEvaluator.Create(Map);
    try
      // (!?)                 optional image marker
      // \[([^\]]*)\]         [alt] / [text]
      // \(                   literal (
      // ([^\s)]+)            URL (no whitespace, no close paren)
      // ((?:\s+[^)]*)?)      optional " title" section incl. leading ws
      // \)                   literal )
      Re := TRegEx.Create('(!?)\[([^\]]*)\]\(([^\s)]+)((?:\s+[^)]*)?)\)');
      Result := Re.Replace(AMarkdown, Evaluator.Evaluate);
    finally
      Evaluator.Free;
    end;
  finally
    Map.Free;
  end;
end;

end.
