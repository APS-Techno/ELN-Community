{-------------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: SynHighlighterIni.pas, released 2000-04-21.
The Original Code is based on the izIniSyn.pas file from the
mwEdit component suite by Martin Waldenburg and other developers, the Initial
Author of this file is Igor P. Zenkov.
Unicode translation by Maël Hörz.
All Rights Reserved.

Contributors to the SynEdit and mwEdit projects are listed in the
Notices/SynEdit/Contributors.txt file in this repository.

Alternatively, the contents of this file may be used under the terms of the
GNU General Public License Version 2 or later (the "GPL"), in which case
the provisions of the GPL are applicable instead of those above.
If you wish to allow use of your version of this file only under the terms
of the GPL and not to allow others to use your version of this file
under the MPL, indicate your decision by deleting the provisions above and
replace them with the notice and other provisions required by the GPL.
If you do not delete the provisions above, a recipient may use your version
of this file under either the MPL or the GPL.

This Markdown highlighter is derived from the Original Code named above.
APS distributes this separate derived file through the MPL-1.1 option.
Recorded introduction: 2026-04-27 (Git author date).
Notice restoration: 2026-10-07. Runtime logic is unchanged by this restoration.
See Notices/SynEdit/CHANGES.txt and Notices/SynEdit/MPL-1.1.txt.
-------------------------------------------------------------------------------}

unit unit_SynHighlighterMd;

// Phase 6.3: minimal markdown syntax highlighter for the editor's
// SynEdit. SynEditDR doesn't ship a markdown highlighter, so this
// is a small TSynCustomHighlighter descendant covering ATX headings,
// fenced + inline code, bold/italic (* and _), links, block quotes,
// and list markers. Single cross-line state: "inside fenced block".
//
// Modelled after SynHighlighterIni.pas (smallest reference highlighter
// in the SynEdit-12 source tree).

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics,
  SynEditTypes,
  SynEditHighlighter;

type
  TtkTokenKind = (
    tkUnknown,
    tkText,
    tkSpace,
    tkHeading,
    tkBold,
    tkItalic,
    tkCode,
    tkLink,
    tkUrl,
    tkQuote,
    tkList,
    tkNull);

  TRangeState = (rsNormal, rsCodeBlock);

  TSynMarkdownSyn = class(TSynCustomHighlighter)
  private
    FRange: TRangeState;
    FTokenID: TtkTokenKind;

    FAttrText:    TSynHighlighterAttributes;
    FAttrSpace:   TSynHighlighterAttributes;
    FAttrHeading: TSynHighlighterAttributes;
    FAttrBold:    TSynHighlighterAttributes;
    FAttrItalic:  TSynHighlighterAttributes;
    FAttrCode:    TSynHighlighterAttributes;
    FAttrLink:    TSynHighlighterAttributes;
    FAttrUrl:     TSynHighlighterAttributes;
    FAttrQuote:   TSynHighlighterAttributes;
    FAttrList:    TSynHighlighterAttributes;

    procedure NullProc;
    procedure CRProc;
    procedure LFProc;
    procedure CodeBlockProc;
    procedure NormalProc;

    function IsFenceLine: Boolean;
  public
    constructor Create(AOwner: TComponent); override;

    class function GetLanguageName: string; override;
    class function GetFriendlyLanguageName: string; override;

    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetEol: Boolean; override;
    procedure Next; override;

    function GetRange: Pointer; override;
    procedure SetRange(Value: Pointer); override;
    procedure ResetRange; override;
  published
    property TextAttri:    TSynHighlighterAttributes read FAttrText    write FAttrText;
    property SpaceAttri:   TSynHighlighterAttributes read FAttrSpace   write FAttrSpace;
    property HeadingAttri: TSynHighlighterAttributes read FAttrHeading write FAttrHeading;
    property BoldAttri:    TSynHighlighterAttributes read FAttrBold    write FAttrBold;
    property ItalicAttri:  TSynHighlighterAttributes read FAttrItalic  write FAttrItalic;
    property CodeAttri:    TSynHighlighterAttributes read FAttrCode    write FAttrCode;
    property LinkAttri:    TSynHighlighterAttributes read FAttrLink    write FAttrLink;
    property UrlAttri:     TSynHighlighterAttributes read FAttrUrl     write FAttrUrl;
    property QuoteAttri:   TSynHighlighterAttributes read FAttrQuote   write FAttrQuote;
    property ListAttri:    TSynHighlighterAttributes read FAttrList    write FAttrList;
  end;

implementation

{ TSynMarkdownSyn }

constructor TSynMarkdownSyn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FAttrText := TSynHighlighterAttributes.Create('Text', 'Text');
  AddAttribute(FAttrText);

  FAttrSpace := TSynHighlighterAttributes.Create('Space', 'Space');
  AddAttribute(FAttrSpace);

  FAttrHeading := TSynHighlighterAttributes.Create('Heading', 'Heading');
  FAttrHeading.Foreground := $00B05030; // dark blue-ish
  FAttrHeading.Style := [fsBold];
  AddAttribute(FAttrHeading);

  FAttrBold := TSynHighlighterAttributes.Create('Bold', 'Bold');
  FAttrBold.Style := [fsBold];
  AddAttribute(FAttrBold);

  FAttrItalic := TSynHighlighterAttributes.Create('Italic', 'Italic');
  FAttrItalic.Style := [fsItalic];
  AddAttribute(FAttrItalic);

  FAttrCode := TSynHighlighterAttributes.Create('Code', 'Code');
  FAttrCode.Foreground := $00006080;
  FAttrCode.Background := $00F0F0F0;
  AddAttribute(FAttrCode);

  FAttrLink := TSynHighlighterAttributes.Create('Link', 'Link');
  FAttrLink.Foreground := $00C04020;
  FAttrLink.Style := [fsUnderline];
  AddAttribute(FAttrLink);

  FAttrUrl := TSynHighlighterAttributes.Create('Url', 'Url');
  FAttrUrl.Foreground := $00808080;
  AddAttribute(FAttrUrl);

  FAttrQuote := TSynHighlighterAttributes.Create('Quote', 'Quote');
  FAttrQuote.Foreground := $00808080;
  FAttrQuote.Style := [fsItalic];
  AddAttribute(FAttrQuote);

  FAttrList := TSynHighlighterAttributes.Create('List', 'List');
  FAttrList.Foreground := $00B05030;
  FAttrList.Style := [fsBold];
  AddAttribute(FAttrList);

  SetAttributesOnChange(DefHighlightChange);

  fDefaultFilter := 'Markdown Files (*.md)|*.md';
  FRange := rsNormal;
end;

class function TSynMarkdownSyn.GetLanguageName: string;
begin
  Result := 'Markdown';
end;

class function TSynMarkdownSyn.GetFriendlyLanguageName: string;
begin
  Result := 'Markdown';
end;

function TSynMarkdownSyn.GetDefaultAttribute(
  Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT:    Result := FAttrQuote;
    SYN_ATTR_KEYWORD:    Result := FAttrHeading;
    SYN_ATTR_STRING:     Result := FAttrCode;
    SYN_ATTR_WHITESPACE: Result := FAttrSpace;
    SYN_ATTR_SYMBOL:     Result := FAttrBold;
    SYN_ATTR_IDENTIFIER: Result := FAttrText;
  else
    Result := nil;
  end;
end;

function TSynMarkdownSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  case FTokenID of
    tkHeading: Result := FAttrHeading;
    tkBold:    Result := FAttrBold;
    tkItalic:  Result := FAttrItalic;
    tkCode:    Result := FAttrCode;
    tkLink:    Result := FAttrLink;
    tkUrl:     Result := FAttrUrl;
    tkQuote:   Result := FAttrQuote;
    tkList:    Result := FAttrList;
    tkSpace:   Result := FAttrSpace;
    tkText:    Result := FAttrText;
  else
    Result := FAttrText;
  end;
end;

function TSynMarkdownSyn.GetTokenKind: Integer;
begin
  Result := Ord(FTokenID);
end;

function TSynMarkdownSyn.GetEol: Boolean;
begin
  Result := Run = fLineLen + 1;
end;

function TSynMarkdownSyn.GetRange: Pointer;
begin
  Result := Pointer(Ord(FRange));
end;

procedure TSynMarkdownSyn.SetRange(Value: Pointer);
begin
  FRange := TRangeState(NativeInt(Value));
end;

procedure TSynMarkdownSyn.ResetRange;
begin
  FRange := rsNormal;
end;

procedure TSynMarkdownSyn.NullProc;
begin
  FTokenID := tkNull;
  Inc(Run);
end;

procedure TSynMarkdownSyn.CRProc;
begin
  FTokenID := tkSpace;
  if fLine[Run + 1] = #10 then
    Inc(Run, 2)
  else
    Inc(Run);
end;

procedure TSynMarkdownSyn.LFProc;
begin
  FTokenID := tkSpace;
  Inc(Run);
end;

function TSynMarkdownSyn.IsFenceLine: Boolean;
// Returns True if the current Run position is at column 0 of a line
// that begins with three backticks. We accept ``` followed by anything
// (typically a language tag like ```python).
begin
  Result := (Run = 0)
        and (fLine[0] = '`')
        and (fLine[1] = '`')
        and (fLine[2] = '`');
end;

procedure TSynMarkdownSyn.CodeBlockProc;
// Inside a fenced code block. If this line opens with ```, it CLOSES the
// block and we revert to rsNormal. Otherwise the entire line is `tkCode`.
begin
  if IsFenceLine then
  begin
    FRange := rsNormal;
    FTokenID := tkCode;
    while not IsLineEnd(Run) do
      Inc(Run);
    Exit;
  end;

  FTokenID := tkCode;
  while not IsLineEnd(Run) do
    Inc(Run);
end;

procedure TSynMarkdownSyn.NormalProc;
// Single-line markdown tokenization at the current Run position.
// Always advances Run by at least 1 to avoid infinite loops.
var
  StartRun: Integer;
  I: Integer;
begin
  // Detect fenced code-block OPEN at column 0
  if IsFenceLine then
  begin
    FRange := rsCodeBlock;
    FTokenID := tkCode;
    while not IsLineEnd(Run) do
      Inc(Run);
    Exit;
  end;

  // Block-level constructs only fire at column 0
  if Run = 0 then
  begin
    // ATX heading
    if fLine[0] = '#' then
    begin
      FTokenID := tkHeading;
      while not IsLineEnd(Run) do
        Inc(Run);
      Exit;
    end;

    // Block quote
    if fLine[0] = '>' then
    begin
      FTokenID := tkQuote;
      while not IsLineEnd(Run) do
        Inc(Run);
      Exit;
    end;

    // Bullet list: `- `, `+ `, `* `
    if ((fLine[0] = '-') or (fLine[0] = '+') or (fLine[0] = '*'))
       and (fLine[1] = ' ') then
    begin
      FTokenID := tkList;
      Inc(Run, 2);
      Exit;
    end;

    // Numbered list: `123. `
    if (fLine[0] >= '0') and (fLine[0] <= '9') then
    begin
      I := 0;
      while (fLine[I] >= '0') and (fLine[I] <= '9') do
        Inc(I);
      if (fLine[I] = '.') and (fLine[I + 1] = ' ') then
      begin
        FTokenID := tkList;
        Run := I + 2;
        Exit;
      end;
    end;
  end;

  // Inline `code`
  if fLine[Run] = '`' then
  begin
    FTokenID := tkCode;
    Inc(Run);
    while (fLine[Run] <> #0) and (fLine[Run] <> '`')
          and (fLine[Run] <> #10) and (fLine[Run] <> #13) do
      Inc(Run);
    if fLine[Run] = '`' then
      Inc(Run);
    Exit;
  end;

  // **bold** / ***bold-italic*** / *italic*
  if fLine[Run] = '*' then
  begin
    if (fLine[Run + 1] = '*') then
    begin
      FTokenID := tkBold;
      Inc(Run, 2);
      while (fLine[Run] <> #0)
            and (fLine[Run] <> #10) and (fLine[Run] <> #13)
            and not ((fLine[Run] = '*') and (fLine[Run + 1] = '*')) do
        Inc(Run);
      if (fLine[Run] = '*') and (fLine[Run + 1] = '*') then
        Inc(Run, 2);
      Exit;
    end
    else
    begin
      FTokenID := tkItalic;
      Inc(Run);
      while (fLine[Run] <> #0) and (fLine[Run] <> '*')
            and (fLine[Run] <> #10) and (fLine[Run] <> #13) do
        Inc(Run);
      if fLine[Run] = '*' then
        Inc(Run);
      Exit;
    end;
  end;

  // _italic_
  if fLine[Run] = '_' then
  begin
    FTokenID := tkItalic;
    Inc(Run);
    while (fLine[Run] <> #0) and (fLine[Run] <> '_')
          and (fLine[Run] <> #10) and (fLine[Run] <> #13) do
      Inc(Run);
    if fLine[Run] = '_' then
      Inc(Run);
    Exit;
  end;

  // [link text](url) — simplified: tokenize bracket span as tkLink, then
  // immediately following parenthesized URL as tkUrl.
  if fLine[Run] = '[' then
  begin
    FTokenID := tkLink;
    Inc(Run);
    while (fLine[Run] <> #0) and (fLine[Run] <> ']')
          and (fLine[Run] <> #10) and (fLine[Run] <> #13) do
      Inc(Run);
    if fLine[Run] = ']' then
      Inc(Run);
    // If a `(...)` follows, consume it as a URL token in a SINGLE next
    // call. Right now we end the link-text token here and let Next pick
    // up the `(` on the following call.
    Exit;
  end;

  // (url) — only treated as URL if it was preceded by a closing `]`.
  // We detect this by looking back at the byte before fTokenPos.
  if (fLine[Run] = '(') and (Run > 0) and (fLine[Run - 1] = ']') then
  begin
    FTokenID := tkUrl;
    Inc(Run);
    while (fLine[Run] <> #0) and (fLine[Run] <> ')')
          and (fLine[Run] <> #10) and (fLine[Run] <> #13) do
      Inc(Run);
    if fLine[Run] = ')' then
      Inc(Run);
    Exit;
  end;

  // Default: plain text run until we hit a markdown special char.
  StartRun := Run;
  FTokenID := tkText;
  while (fLine[Run] <> #0)
        and (fLine[Run] <> #10) and (fLine[Run] <> #13)
        and (fLine[Run] <> '*') and (fLine[Run] <> '_')
        and (fLine[Run] <> '`') and (fLine[Run] <> '[') do
    Inc(Run);
  // Safety: every Next call must advance Run.
  if Run = StartRun then
    Inc(Run);
end;

procedure TSynMarkdownSyn.Next;
begin
  fTokenPos := Run;

  case fLine[Run] of
    #0:
      NullProc;
    #10:
      LFProc;
    #13:
      CRProc;
  else
    if FRange = rsCodeBlock then
      CodeBlockProc
    else
      NormalProc;
  end;

  inherited;
end;

end.
