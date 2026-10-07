unit unit_MarkdownAttachmentResolver;

// Rewrites inline markdown image/link URLs so they match ELN's on-disk
// attachment naming convention.
//
// ELN stores attachments flat inside the item folder as
//     "[{fileId}]{title}.{ext}"    e.g.  "[1046]dcpulseg3f.png"
// but wiki authors write them by their logical name:
//     ![](dcpulseg3f.png)
// Against the viewer's file:/// base href the browser would fetch
//     file:///.../dcpulseg3f.png                 -> 404
// instead of
//     file:///.../[1046]dcpulseg3f.png           -> the real file.
//
// This unit enumerates the item folder, builds a case-insensitive
// {logicalName -> actualFileName} map, and rewrites inline
// [text](url) / ![alt](url) tokens whose URL:
//   * has no URL scheme (http://, https://, file://, eln://, mailto:, data:)
//   * is not absolute (/foo, \foo, C:\foo)
//   * is not a fragment (#anchor)
// by replacing the URL with the "[ID]name.ext" variant, URL-encoding the
// brackets as %5B/%5D so markdown-it emits a valid href/src.
//
// Tokens with URLs that don't resolve to a known file are left untouched,
// which preserves any current behavior for subpaths or external refs.

interface

uses
  System.SysUtils;

// AFiles, when non-empty, is used as the authoritative list of "[ID]name.ext"
// filenames (host-supplied via IElnFileEnumerator). Otherwise the function
// falls back to enumerating ADir. ADir is still required for the fallback
// path (standalone tests, PluginTestApp).
function RewriteAttachmentRefs(const AMarkdown, ADir: string;
  const AFiles: TArray<string> = nil): string;

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

function EncodeBrackets(const S: string): string;
begin
  Result := StringReplace(S, '[', '%5B', [rfReplaceAll]);
  Result := StringReplace(Result, ']', '%5D', [rfReplaceAll]);
end;

function BuildLogicalMapFromList(const AFiles: TArray<string>): TLogicalMap;
var
  FilePath, Name: string;
  M: TMatch;
begin
  Result := TLogicalMap.Create;
  for FilePath in AFiles do
  begin
    // Tolerate full paths or bare names — the host-supplied list uses bare
    // "[ID]name.ext", but disk enumeration returns full paths.
    Name := ExtractFileName(FilePath);
    M := TRegEx.Match(Name, '^\[\d+\](.+)$');
    if M.Success then
      Result.AddOrSetValue(LowerCase(M.Groups[1].Value), Name);
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
  Prefix, AltText, Url, TitlePart, Actual, DecodedKey, IdPrefix: string;
  PrefixMatch: TMatch;
begin
  Prefix    := M.Groups[1].Value;
  AltText   := M.Groups[2].Value;
  Url       := M.Groups[3].Value;
  TitlePart := M.Groups[4].Value;

  if IsRemoteOrAbsolute(Url) then Exit(M.Value);

  // Look up by the decoded logical name so authors can write either
  // "photo with spaces.png" (won't match — spec forbids unquoted spaces)
  // or "photo%20with%20spaces.png" (decodes and matches).
  DecodedKey := LowerCase(TNetEncoding.URL.Decode(Url));
  if not FMap.TryGetValue(DecodedKey, Actual) then Exit(M.Value);

  // Keep the author's original URL (encoding and all) — only inject the
  // "[ID]" prefix as %5BID%5D so markdown-it's URL parser stays happy.
  PrefixMatch := TRegEx.Match(Actual, '^(\[\d+\]).+$');
  if not PrefixMatch.Success then Exit(M.Value);
  IdPrefix := PrefixMatch.Groups[1].Value;

  Result := Format('%s[%s](%s%s%s)',
    [Prefix, AltText, EncodeBrackets(IdPrefix), Url, TitlePart]);
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
