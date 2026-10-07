unit unit_MarkdownEditorAttachments;

// Pure-function helpers for the markdown editor's drop / paste-image
// handlers (Tasks 10.2 and 10.3). UI-free and deterministic.
//
// IsImageExt              -> classify a server filename as image / non-image.
// BuildInsertSnippet      -> render the `![](...)` or `[name](...)` markdown
//                            snippet to insert at the caret. URL-encoding is
//                            minimal (spaces only); brackets in [ID]-prefixed
//                            filenames stay literal so the existing
//                            unit_MarkdownAttachmentResolver continues to do
//                            its [ID] -> %5B%5D rewrite at render time.
// ClipboardImageFileName  -> generate a stable 'paste-YYYYMMDD-HHMMSS.png'
//                            name for clipboard-image uploads.

interface

uses
  System.SysUtils;

function IsImageExt(const AExt: string): Boolean;
function BuildInsertSnippet(const ServerFilename: string;
  IsImage: Boolean): string;
function ClipboardImageFileName(AAt: TDateTime): string;

implementation

function IsImageExt(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  if (E <> '') and (E[1] = '.') then
    Delete(E, 1, 1);
  Result := (E = 'png') or (E = 'jpg') or (E = 'jpeg') or (E = 'gif')
         or (E = 'webp') or (E = 'svg') or (E = 'bmp');
end;

// Encodes only the characters that would break a markdown URL. We keep the
// encoding minimal so user-edited source stays readable. Spaces -> %20; the
// rest of the typical ASCII filename charset stays literal. (Brackets in the
// name remain literal — the resolver handles its own [ID] prefix at render
// time, and ElnFileService.UploadAttachment returns a bare server filename
// that the user can comfortably re-edit by hand.)
function MinimalUrlEncode(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if Ch = ' ' then
      Result := Result + '%20'
    else
      Result := Result + Ch;
  end;
end;

function BuildInsertSnippet(const ServerFilename: string;
  IsImage: Boolean): string;
var
  Url: string;
begin
  Url := MinimalUrlEncode(ServerFilename);
  if IsImage then
    Result := '![](' + Url + ')'
  else
    Result := '[' + ServerFilename + '](' + Url + ')';
end;

function ClipboardImageFileName(AAt: TDateTime): string;
begin
  // Note: 'nn' is Delphi's date-format token for minutes. 'mm' would emit
  // months and produce silently-wrong filenames at certain times of day.
  Result := 'paste-' + FormatDateTime('yyyymmdd-hhnnss', AAt) + '.png';
end;

end.
