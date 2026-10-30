unit unit_RtfTextExtractor;

interface

uses
  System.SysUtils, unit_TextEmbedder, unit_TextExtractors;

type
  TRtfTextExtractor = class(TTextExtractorBase)
  public
    function Id: string; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

implementation

uses
  System.Math;

const
  RtfSkipDestinations = '|fonttbl|colortbl|stylesheet|info|pict|listtable|listoverridetable|rsidtbl|generator|' +
    'themedata|datastore|latentstyles|colorschememapping|filetbl|revtbl|objdata|upr|fldinst|xmlnstbl|';

type
  TRtfGroup = record
    Skip: Boolean;
    Uc: Integer;
  end;

function ParseRtf(const Text: string; Sink: TTextSink; const Cancelled: TCancelCheck): Boolean;
var
  I, N, Top, NextPoll, CodePage, EncodingCodePage, FallbackLeft, HexLen, Start, Param, Digits: Integer;
  Stack: TArray<TRtfGroup>;
  Cur: TRtfGroup;
  GroupStart, StarPending, Negative, HasParam, EncodingOwned: Boolean;
  Hex: TBytes;
  Enc: TEncoding;
  C: Char;
  Name: string;

  function IsLetter(Ch: Char): Boolean;
  begin
    Result := ((Ch >= 'a') and (Ch <= 'z')) or ((Ch >= 'A') and (Ch <= 'Z'));
  end;

  function IsDigit(Ch: Char): Boolean;
  begin
    Result := (Ch >= '0') and (Ch <= '9');
  end;

  function HexValue(Ch: Char): Integer;
  begin
    if (Ch >= '0') and (Ch <= '9') then
      Result := Ord(Ch) - Ord('0')
    else if (Ch >= 'a') and (Ch <= 'f') then
      Result := Ord(Ch) - Ord('a') + 10
    else if (Ch >= 'A') and (Ch <= 'F') then
      Result := Ord(Ch) - Ord('A') + 10
    else
      Result := -1;
  end;

  procedure ReleaseEncoding;
  begin
    if EncodingOwned then
      Enc.Free;
    Enc := nil;
    EncodingOwned := False;
  end;

  procedure FlushHex;
  begin
    if HexLen = 0 then
      Exit;
    if (Enc = nil) or (EncodingCodePage <> CodePage) then
    begin
      ReleaseEncoding;
      try
        Enc := TEncoding.GetEncoding(CodePage);
        EncodingOwned := True;
      except
        Enc := TEncoding.ANSI;
        EncodingOwned := False;
      end;
      EncodingCodePage := CodePage;
    end;
    Sink.Append(Enc.GetString(Hex, 0, HexLen));
    HexLen := 0;
  end;

  procedure PutChar(Ch: Char);
  begin
    FlushHex;
    if Cur.Skip then
      Exit;
    if FallbackLeft > 0 then
      Dec(FallbackLeft)
    else
      Sink.AppendChar(Ch);
  end;

  procedure PutText(const S: string);
  begin
    FlushHex;
    if not Cur.Skip then
      Sink.Append(S);
  end;

  procedure HandleWord;
  var
    WasGroupStart: Boolean;
  begin
    FlushHex;
    WasGroupStart := GroupStart;
    GroupStart := False;
    if (Name = 'bin') and HasParam then
    begin
      I := Min(N + 1, I + Max(0, Param));
      Exit;
    end;
    if StarPending then
    begin
      StarPending := False;
      if Name <> 'ud' then
        Cur.Skip := True;
    end
    else if WasGroupStart and (Pos('|' + Name + '|', RtfSkipDestinations) > 0) then
      Cur.Skip := True;
    if Cur.Skip then
      Exit;
    FallbackLeft := 0;
    if (Name = 'par') or (Name = 'line') or (Name = 'sect') or (Name = 'page') or (Name = 'row') then
      Sink.LineBreak
    else if (Name = 'tab') or (Name = 'cell') then
      Sink.Tab
    else if Name = 'u' then
    begin
      if Param < 0 then
        Inc(Param, 65536);
      Sink.AppendChar(Char(Param and $FFFF));
      FallbackLeft := Cur.Uc;
    end
    else if Name = 'uc' then
      Cur.Uc := Max(0, Param)
    else if Name = 'ansicpg' then
      CodePage := Param
    else if Name = 'ansi' then
      CodePage := 1252
    else if Name = 'mac' then
      CodePage := 10000
    else if Name = 'pc' then
      CodePage := 437
    else if Name = 'pca' then
      CodePage := 850
    else if Name = 'endash' then
      Sink.AppendChar(#$2013)
    else if Name = 'emdash' then
      Sink.AppendChar(#$2014)
    else if Name = 'lquote' then
      Sink.AppendChar(#$2018)
    else if Name = 'rquote' then
      Sink.AppendChar(#$2019)
    else if Name = 'ldblquote' then
      Sink.AppendChar(#$201C)
    else if Name = 'rdblquote' then
      Sink.AppendChar(#$201D)
    else if Name = 'bullet' then
      Sink.AppendChar(#$2022)
    else if (Name = 'emspace') or (Name = 'enspace') or (Name = 'qmspace') then
      Sink.AppendChar(' ');
  end;

  procedure HandleSymbol(Symbol: Char);
  var
    Hi, Lo: Integer;
  begin
    case Symbol of
      '''':
        begin
          if I + 1 <= N then
          begin
            Hi := HexValue(Text[I]);
            Lo := HexValue(Text[I + 1]);
            if (Hi >= 0) and (Lo >= 0) then
            begin
              Inc(I, 2);
              GroupStart := False;
              if Cur.Skip then
                Exit;
              if FallbackLeft > 0 then
                Dec(FallbackLeft)
              else
              begin
                if HexLen >= Length(Hex) then
                  SetLength(Hex, Max(16, Length(Hex) * 2));
                Hex[HexLen] := Hi * 16 + Lo;
                Inc(HexLen);
              end;
            end;
          end;
        end;
      '\', '{', '}':
        begin
          GroupStart := False;
          PutChar(Symbol);
        end;
      '~':
        begin
          GroupStart := False;
          PutChar(' ');
        end;
      '_':
        begin
          GroupStart := False;
          PutChar('-');
        end;
      '*':
        StarPending := True;
      #10, #13:
        begin
          GroupStart := False;
          FlushHex;
          if not Cur.Skip then
            Sink.LineBreak;
        end;
    else
      GroupStart := False;
    end;
  end;

begin
  Result := False;
  N := Length(Text);
  I := 1;
  while (I <= N) and (Text[I] <= ' ') do
    Inc(I);
  if Copy(Text, I, 5) <> '{\rtf' then
    Exit;
  Cur.Skip := False;
  Cur.Uc := 1;
  CodePage := 1252;
  Top := 0;
  HexLen := 0;
  FallbackLeft := 0;
  EncodingCodePage := 0;
  GroupStart := False;
  StarPending := False;
  NextPoll := 0;
  Enc := nil;
  EncodingOwned := False;
  try
    while I <= N do
    begin
      if I > NextPoll then
      begin
        CheckExtractCancelled(Cancelled);
        NextPoll := I + TextSliceChars;
      end;
      C := Text[I];
      case C of
        '{':
          begin
            FlushHex;
            if Top >= Length(Stack) then
              SetLength(Stack, Max(16, Length(Stack) * 2));
            Stack[Top] := Cur;
            Inc(Top);
            GroupStart := True;
            Inc(I);
          end;
        '}':
          begin
            FlushHex;
            if Top > 0 then
            begin
              Dec(Top);
              Cur := Stack[Top];
            end;
            GroupStart := False;
            FallbackLeft := 0;
            Inc(I);
          end;
        '\':
          begin
            Inc(I);
            if I > N then
              Break;
            C := Text[I];
            if IsLetter(C) then
            begin
              Start := I;
              while (I <= N) and IsLetter(Text[I]) and (I - Start < 32) do
                Inc(I);
              Name := Copy(Text, Start, I - Start);
              HasParam := False;
              Negative := False;
              Param := 0;
              if (I < N) and (Text[I] = '-') and IsDigit(Text[I + 1]) then
              begin
                Negative := True;
                Inc(I);
              end;
              Digits := 0;
              while (I <= N) and IsDigit(Text[I]) and (Digits < 9) do
              begin
                HasParam := True;
                Param := Param * 10 + (Ord(Text[I]) - Ord('0'));
                Inc(I);
                Inc(Digits);
              end;
              if Negative then
                Param := -Param;
              if (I <= N) and (Text[I] = ' ') then
                Inc(I);
              HandleWord;
            end
            else
            begin
              Inc(I);
              HandleSymbol(C);
            end;
          end;
        #13, #10:
          Inc(I);
      else
        PutChar(C);
        GroupStart := False;
        Inc(I);
      end;
    end;
    FlushHex;
  finally
    ReleaseEncoding;
  end;
  Result := True;
end;

function TRtfTextExtractor.Id: string;
begin
  Result := 'rtf-text';
end;

function TRtfTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
begin
  if TryRejectTextBytes(Bytes, Result) then
    Exit;
  Sink := TTextSink.Create(FMaxChars);
  try
    if not ParseRtf(DecodeTextBytes(Bytes), Sink, Cancelled) then
      Exit(MakeExtractResult(eoCorrupt, '', 'not an RTF document'));
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

end.
