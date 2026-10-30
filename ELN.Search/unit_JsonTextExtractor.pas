unit unit_JsonTextExtractor;

interface

uses
  System.SysUtils, unit_TextEmbedder, unit_TextExtractors;

type
  TJsonTextExtractor = class(TTextExtractorBase)
  public
    function Id: string; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

implementation

uses
  System.Math;

function ParseJsonStrings(const Text: string; Sink: TTextSink; const Cancelled: TCancelCheck): Boolean;
type
  TJsonState = (jsValue, jsValueOrEnd, jsKeyOrEnd, jsKey, jsColon, jsAfterValue, jsEnd);
var
  I, N, Depth, NextPoll: Integer;
  Stack: TArray<Boolean>;
  State: TJsonState;
  Value: TStringBuilder;
  C: Char;

  function IsDigit(Ch: Char): Boolean;
  begin
    Result := (Ch >= '0') and (Ch <= '9');
  end;

  function ReadString: Boolean;
  var
    Code, K, Digit: Integer;
    Ch: Char;
  begin
    Value.Clear;
    Inc(I);
    while I <= N do
    begin
      Ch := Text[I];
      if Ch = '"' then
      begin
        Inc(I);
        Exit(True);
      end;
      if Ch = '\' then
      begin
        Inc(I);
        if I > N then
          Exit(False);
        case Text[I] of
          '"', '\', '/': Value.Append(Text[I]);
          'b': Value.Append(#8);
          'f': Value.Append(#12);
          'n': Value.Append(#10);
          'r': Value.Append(#13);
          't': Value.Append(#9);
          'u':
            begin
              if I + 4 > N then
                Exit(False);
              Code := 0;
              for K := 1 to 4 do
              begin
                Ch := Text[I + K];
                if (Ch >= '0') and (Ch <= '9') then
                  Digit := Ord(Ch) - Ord('0')
                else if (Ch >= 'a') and (Ch <= 'f') then
                  Digit := Ord(Ch) - Ord('a') + 10
                else if (Ch >= 'A') and (Ch <= 'F') then
                  Digit := Ord(Ch) - Ord('A') + 10
                else
                  Exit(False);
                Code := Code * 16 + Digit;
              end;
              Value.Append(Char(Code));
              Inc(I, 4);
            end;
        else
          Exit(False);
        end;
        Inc(I);
      end
      else
      begin
        Value.Append(Ch);
        Inc(I);
      end;
    end;
    Result := False;
  end;

  function ReadNumber: Boolean;
  var
    J: Integer;
  begin
    J := I;
    if Text[J] = '-' then
      Inc(J);
    if J > N then
      Exit(False);
    if Text[J] = '0' then
      Inc(J)
    else if IsDigit(Text[J]) then
      while (J <= N) and IsDigit(Text[J]) do
        Inc(J)
    else
      Exit(False);
    if (J <= N) and (Text[J] = '.') then
    begin
      Inc(J);
      if (J > N) or not IsDigit(Text[J]) then
        Exit(False);
      while (J <= N) and IsDigit(Text[J]) do
        Inc(J);
    end;
    if (J <= N) and ((Text[J] = 'e') or (Text[J] = 'E')) then
    begin
      Inc(J);
      if (J <= N) and ((Text[J] = '+') or (Text[J] = '-')) then
        Inc(J);
      if (J > N) or not IsDigit(Text[J]) then
        Exit(False);
      while (J <= N) and IsDigit(Text[J]) do
        Inc(J);
    end;
    I := J;
    Result := True;
  end;

  function ReadLiteral(const Word: string): Boolean;
  begin
    Result := Copy(Text, I, Length(Word)) = Word;
    if Result then
      Inc(I, Length(Word));
  end;

  procedure Emit;
  begin
    if not Sink.Full and (Trim(Value.ToString) <> '') then
    begin
      Sink.Append(Value.ToString);
      Sink.LineBreak;
    end;
  end;

  procedure Push(IsObject: Boolean);
  begin
    if Depth >= Length(Stack) then
      SetLength(Stack, Max(16, Length(Stack) * 2));
    Stack[Depth] := IsObject;
    Inc(Depth);
    Inc(I);
  end;

  procedure ValueDone;
  begin
    if Depth = 0 then
      State := jsEnd
    else
      State := jsAfterValue;
  end;

  procedure CloseContainer;
  begin
    Dec(Depth);
    Inc(I);
    ValueDone;
  end;

begin
  Result := False;
  N := Length(Text);
  I := 1;
  Depth := 0;
  NextPoll := 0;
  State := jsValue;
  Value := TStringBuilder.Create;
  try
    while I <= N do
    begin
      if I > NextPoll then
      begin
        CheckExtractCancelled(Cancelled);
        NextPoll := I + TextSliceChars;
      end;
      C := Text[I];
      if (C = ' ') or (C = #9) or (C = #10) or (C = #13) or ((I = 1) and (C = #$FEFF)) then
      begin
        Inc(I);
        Continue;
      end;
      case State of
        jsValue, jsValueOrEnd:
          if C = '"' then
          begin
            if not ReadString then
              Exit;
            Emit;
            ValueDone;
          end
          else if C = '{' then
          begin
            Push(True);
            State := jsKeyOrEnd;
          end
          else if C = '[' then
          begin
            Push(False);
            State := jsValueOrEnd;
          end
          else if (State = jsValueOrEnd) and (C = ']') then
            CloseContainer
          else if (C = '-') or IsDigit(C) then
          begin
            if not ReadNumber then
              Exit;
            ValueDone;
          end
          else if C = 't' then
          begin
            if not ReadLiteral('true') then
              Exit;
            ValueDone;
          end
          else if C = 'f' then
          begin
            if not ReadLiteral('false') then
              Exit;
            ValueDone;
          end
          else if C = 'n' then
          begin
            if not ReadLiteral('null') then
              Exit;
            ValueDone;
          end
          else
            Exit;
        jsKeyOrEnd, jsKey:
          if C = '"' then
          begin
            if not ReadString then
              Exit;
            Emit;
            State := jsColon;
          end
          else if (State = jsKeyOrEnd) and (C = '}') then
            CloseContainer
          else
            Exit;
        jsColon:
          if C = ':' then
          begin
            Inc(I);
            State := jsValue;
          end
          else
            Exit;
        jsAfterValue:
          if C = ',' then
          begin
            Inc(I);
            if Stack[Depth - 1] then
              State := jsKey
            else
              State := jsValue;
          end
          else if (C = ']') and not Stack[Depth - 1] then
            CloseContainer
          else if (C = '}') and Stack[Depth - 1] then
            CloseContainer
          else
            Exit;
        jsEnd:
          Exit;
      end;
    end;
    Result := State = jsEnd;
  finally
    Value.Free;
  end;
end;

function TJsonTextExtractor.Id: string;
begin
  Result := 'json-text';
end;

function TJsonTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
begin
  if TryRejectTextBytes(Bytes, Result) then
    Exit;
  Sink := TTextSink.Create(FMaxChars);
  try
    if not ParseJsonStrings(DecodeTextBytes(Bytes), Sink, Cancelled) then
      Exit(MakeExtractResult(eoCorrupt, '', 'invalid JSON'));
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

end.
