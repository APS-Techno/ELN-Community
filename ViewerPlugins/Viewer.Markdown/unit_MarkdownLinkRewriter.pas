unit unit_MarkdownLinkRewriter;


interface

function RewriteElnLinks(const AMarkdown: string): string;

implementation

uses
  System.RegularExpressions, System.SysUtils;

const
  SCHEME = 'eln';

function HtmlEscape(const S: string): string;
begin
  // `&` must be escaped first so the later replacements don't double-escape.
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

type
  // TMatchEvaluator is declared as `function(const Match: TMatch): string of object;`
  // in System.RegularExpressions, i.e. a method pointer rather than an anonymous
  // method. We wrap our stateless evaluation logic in a class method.
  TElnLinkEvaluator = class
    class function Evaluate(const M: TMatch): string;
  end;

class function TElnLinkEvaluator.Evaluate(const M: TMatch): string;
var
  Kind, Ref, EscKind, EscRef: string;
begin
  Kind := M.Groups[1].Value;
  Ref  := M.Groups[2].Value;
  EscKind := HtmlEscape(Kind);
  EscRef  := HtmlEscape(Ref);
  Result := Format(
    '<a class="eln-link" href="%s://%s/%s">%s:%s</a>',
    [SCHEME, EscKind, EscRef, EscKind, EscRef]);
end;

function RewriteElnLinks(const AMarkdown: string): string;
var
  Re: TRegEx;
begin
  // `[^\]\s]+` rejects whitespace (spaces, tabs, newlines) inside the ref slot
  // so tokens spanning lines or containing stray whitespace pass through intact.
  Re := TRegEx.Create('\[\[(item|specimen):([^\]\s]+)\]\]');
  Result := Re.Replace(AMarkdown, TElnLinkEvaluator.Evaluate);
end;

end.
