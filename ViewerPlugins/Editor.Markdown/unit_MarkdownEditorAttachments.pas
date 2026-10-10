unit unit_MarkdownEditorAttachments;


interface

uses
  System.SysUtils;

function IsImageExt(const AExt: string): Boolean;
function BuildInsertSnippet(const ServerFilename: string;
  IsImage: Boolean): string;
function ClipboardImageFileName(AAt: TDateTime): string;

implementation

uses
  unit_MarkdownAttachmentResolver;

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


function BuildInsertSnippet(const ServerFilename: string;
  IsImage: Boolean): string;
var
  Url: string;
begin
  Url := EncodeAttachmentFileName(ServerFilename);
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
