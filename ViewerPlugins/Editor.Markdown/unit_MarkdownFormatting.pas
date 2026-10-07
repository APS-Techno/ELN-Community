unit unit_MarkdownFormatting;

// Pure-function formatting helpers for the Markdown editor toolbar.
// All three helpers are idempotent: applying the same transform twice
// toggles it off. SelStart / NewSelStart use the 1-based convention
// matching SynEdit's SelStart property.
//
// Test #12 ('MixedPrefixOnlyAddsToBare') interpretation: PrefixLines
// makes a per-line decision — lines that already have the prefix get it
// stripped; lines that don't get it added. Mixed input therefore ends
// up with the prefix toggled per-line independently.

interface

type
  TWrapResult = record
    NewText:     string;
    NewSelStart: Integer;  // 1-based (SynEdit-style)
    NewSelLen:   Integer;
  end;

function WrapSelection(const Text: string;
                       SelStart, SelLen: Integer;
                       const Open, Close: string): TWrapResult;

function PrefixLines(const Text: string;
                     SelStart, SelLen: Integer;
                     const Prefix: string): TWrapResult;

function MakeHeading(const Text: string;
                     SelStart: Integer;
                     Level: Integer): TWrapResult;

implementation

uses
  System.SysUtils, System.StrUtils;

function WrapSelection(const Text: string;
                       SelStart, SelLen: Integer;
                       const Open, Close: string): TWrapResult;
var
  Before, Selected, After: string;
  OpenLen, CloseLen: Integer;
  HasOpenBefore, HasCloseAfter: Boolean;
begin
  if SelStart < 1 then
    SelStart := 1;
  if SelLen < 0 then
    SelLen := 0;

  OpenLen := Length(Open);
  CloseLen := Length(Close);

  Before   := Copy(Text, 1, SelStart - 1);
  Selected := Copy(Text, SelStart, SelLen);
  After    := Copy(Text, SelStart + SelLen, MaxInt);

  // Idempotent toggle: if the chars immediately surrounding the selection
  // are already Open/Close, strip them instead of adding another layer.
  HasOpenBefore  := (OpenLen > 0)  and (Length(Before) >= OpenLen) and
                    (Copy(Before, Length(Before) - OpenLen + 1, OpenLen) = Open);
  HasCloseAfter  := (CloseLen > 0) and (Length(After) >= CloseLen) and
                    (Copy(After, 1, CloseLen) = Close);

  if HasOpenBefore and HasCloseAfter then
  begin
    // Strip the wrappers: drop trailing Open from Before, leading Close from After.
    Before := Copy(Before, 1, Length(Before) - OpenLen);
    After  := Copy(After, CloseLen + 1, MaxInt);
    Result.NewText     := Before + Selected + After;
    Result.NewSelStart := Length(Before) + 1;
    Result.NewSelLen   := Length(Selected);
    Exit;
  end;

  // Add the wrappers.
  Result.NewText     := Before + Open + Selected + Close + After;
  Result.NewSelStart := Length(Before) + OpenLen + 1;
  Result.NewSelLen   := Length(Selected);
end;

// --- helpers for line-oriented operations ---

// Splits Text into segments at CRLF/LF/CR boundaries. Each entry pairs the
// line content with its terminator (the terminator is empty for the final
// line if Text doesn't end in a newline). Reconstructing by concatenating
// Content + Terminator for each entry exactly reproduces the input.
type
  TLineSeg = record
    Content:    string;
    Terminator: string;
    StartPos:   Integer;  // 1-based position of Content[1] in original Text
  end;
  TLineSegArray = array of TLineSeg;

function SplitIntoLines(const Text: string): TLineSegArray;
var
  I, LineStart, ContentEnd, Count: Integer;
  Term: string;
begin
  Result := nil;
  Count := 0;
  I := 1;
  LineStart := 1;
  while I <= Length(Text) do
  begin
    if (Text[I] = #13) or (Text[I] = #10) then
    begin
      ContentEnd := I - 1;
      if (Text[I] = #13) and (I < Length(Text)) and (Text[I + 1] = #10) then
      begin
        Term := #13#10;
        Inc(I, 2);
      end
      else
      begin
        Term := Text[I];
        Inc(I);
      end;
      SetLength(Result, Count + 1);
      Result[Count].Content    := Copy(Text, LineStart, ContentEnd - LineStart + 1);
      Result[Count].Terminator := Term;
      Result[Count].StartPos   := LineStart;
      Inc(Count);
      LineStart := I;
    end
    else
      Inc(I);
  end;
  // Trailing line (with or without content). Always emit it even if empty,
  // unless the entire input was empty AND we want a single empty entry to
  // represent it — yes, do that too so PrefixLines on '' still works.
  SetLength(Result, Count + 1);
  Result[Count].Content    := Copy(Text, LineStart, Length(Text) - LineStart + 1);
  Result[Count].Terminator := '';
  Result[Count].StartPos   := LineStart;
end;

function PrefixLines(const Text: string;
                     SelStart, SelLen: Integer;
                     const Prefix: string): TWrapResult;
var
  Lines: TLineSegArray;
  I: Integer;
  SelEnd, LineEnd: Integer;
  Touched: Boolean;
  PrefixLen: Integer;
  SB: TStringBuilder;
  NewStart, NewLen: Integer;
  RangeStart, RangeEnd: Integer;
begin
  if SelStart < 1 then
    SelStart := 1;
  if SelLen < 0 then
    SelLen := 0;
  SelEnd := SelStart + SelLen - 1;
  if SelLen = 0 then
    SelEnd := SelStart;  // empty selection still touches the line at SelStart

  PrefixLen := Length(Prefix);
  Lines := SplitIntoLines(Text);

  RangeStart := MaxInt;
  RangeEnd   := -1;

  SB := TStringBuilder.Create;
  try
    for I := 0 to High(Lines) do
    begin
      LineEnd := Lines[I].StartPos + Length(Lines[I].Content) - 1;
      // A line is "touched" if the selection range overlaps the line.
      // For an empty selection the cursor is between chars at SelStart;
      // we count it as touching the line whose StartPos <= SelStart <= LineEnd+1.
      if SelLen = 0 then
        Touched := (Lines[I].StartPos <= SelStart) and (SelStart <= LineEnd + 1)
      else
        Touched := (LineEnd >= SelStart) and (Lines[I].StartPos <= SelEnd);

      if Touched then
      begin
        if (PrefixLen > 0) and StartsStr(Prefix, Lines[I].Content) then
          Lines[I].Content := Copy(Lines[I].Content, PrefixLen + 1, MaxInt)
        else
          Lines[I].Content := Prefix + Lines[I].Content;

        if SB.Length < RangeStart then
          RangeStart := SB.Length;  // captured below after the append
      end;

      if Touched and (RangeStart = MaxInt) then
        RangeStart := SB.Length + 1
      else if Touched and (RangeStart > SB.Length + 1) then
        RangeStart := SB.Length + 1;

      SB.Append(Lines[I].Content);
      if Touched then
        RangeEnd := SB.Length;
      SB.Append(Lines[I].Terminator);
    end;

    Result.NewText := SB.ToString;
  finally
    SB.Free;
  end;

  if RangeEnd < 0 then
  begin
    NewStart := SelStart;
    NewLen   := 0;
  end
  else
  begin
    NewStart := RangeStart;
    if NewStart < 1 then
      NewStart := 1;
    NewLen := RangeEnd - NewStart + 1;
    if NewLen < 0 then
      NewLen := 0;
  end;

  Result.NewSelStart := NewStart;
  Result.NewSelLen   := NewLen;
end;

function MakeHeading(const Text: string;
                     SelStart: Integer;
                     Level: Integer): TWrapResult;
var
  Lines: TLineSegArray;
  I, ChosenIdx: Integer;
  LineEnd: Integer;
  Content: string;
  HashCount, P: Integer;
  ExistingLevel: Integer;
  SB: TStringBuilder;
  NewLineContent: string;
  RangeStart, RangeEnd: Integer;
begin
  if SelStart < 1 then
    SelStart := 1;
  if Level < 0 then
    Level := 0
  else if Level > 6 then
    Level := 6;

  Lines := SplitIntoLines(Text);

  // Find the line containing SelStart.
  ChosenIdx := 0;
  for I := 0 to High(Lines) do
  begin
    LineEnd := Lines[I].StartPos + Length(Lines[I].Content) - 1;
    if (Lines[I].StartPos <= SelStart) and (SelStart <= LineEnd + 1) then
    begin
      ChosenIdx := I;
      Break;
    end;
    // Cursor past last line: stay on last line.
    if I = High(Lines) then
      ChosenIdx := I;
  end;

  Content := Lines[ChosenIdx].Content;

  // Strip existing leading '#' run (and the single space that follows it,
  // if any) to determine the existing heading level.
  HashCount := 0;
  P := 1;
  while (P <= Length(Content)) and (Content[P] = '#') do
  begin
    Inc(HashCount);
    Inc(P);
  end;
  if (HashCount > 0) and (HashCount <= 6) and
     (P <= Length(Content)) and (Content[P] = ' ') then
  begin
    ExistingLevel := HashCount;
    Inc(P);  // consume the single space
  end
  else if (HashCount > 0) and (HashCount <= 6) and
          (P > Length(Content)) then
  begin
    // Heading marker at line end with no content: still counts as that level.
    ExistingLevel := HashCount;
  end
  else
  begin
    ExistingLevel := 0;
    P := 1;  // no heading to strip
  end;

  Content := Copy(Content, P, MaxInt);

  // Toggle: same level twice -> Level 0.
  if (Level > 0) and (Level = ExistingLevel) then
    Level := 0;

  if Level = 0 then
    NewLineContent := Content
  else
    NewLineContent := StringOfChar('#', Level) + ' ' + Content;

  Lines[ChosenIdx].Content := NewLineContent;

  RangeStart := -1;
  RangeEnd   := -1;
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(Lines) do
    begin
      if I = ChosenIdx then
        RangeStart := SB.Length + 1;
      SB.Append(Lines[I].Content);
      if I = ChosenIdx then
        RangeEnd := SB.Length;
      SB.Append(Lines[I].Terminator);
    end;
    Result.NewText := SB.ToString;
  finally
    SB.Free;
  end;

  if RangeStart < 1 then
    RangeStart := 1;
  Result.NewSelStart := RangeStart;
  Result.NewSelLen   := RangeEnd - RangeStart + 1;
  if Result.NewSelLen < 0 then
    Result.NewSelLen := 0;
end;

end.
