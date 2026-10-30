unit unit_TextStreamDecoder;

interface

uses
  System.SysUtils;

type
  TTextStreamDecoder = class
  private
    FMode: Integer;
    FNeed: Integer;
    FCodePoint: Cardinal;
    FHasOddByte: Boolean;
    FOddByte: Byte;
  public
    function Decode(const Buffer: TBytes; Count: Integer; First: Boolean): string;
  end;

implementation

function TTextStreamDecoder.Decode(const Buffer: TBytes; Count: Integer; First: Boolean): string;
var
  Chars: TArray<Char>;
  I, O: Integer;
  B: Byte;
  Unit16: Word;

  procedure Emit(Code: Cardinal);
  begin
    if (Code > $10FFFF) or ((Code >= $D800) and (Code <= $DFFF)) then
      Code := $FFFD;
    if Code < $10000 then
    begin
      Chars[O] := Char(Code);
      Inc(O);
    end
    else
    begin
      Dec(Code, $10000);
      Chars[O] := Char($D800 + (Code shr 10));
      Chars[O + 1] := Char($DC00 + (Code and $3FF));
      Inc(O, 2);
    end;
  end;

begin
  I := 0;
  if First then
  begin
    if (Count >= 3) and (Buffer[0] = $EF) and (Buffer[1] = $BB) and (Buffer[2] = $BF) then
      I := 3
    else if (Count >= 2) and (Buffer[0] = $FF) and (Buffer[1] = $FE) then
    begin
      FMode := 1;
      I := 2;
    end
    else if (Count >= 2) and (Buffer[0] = $FE) and (Buffer[1] = $FF) then
    begin
      FMode := 2;
      I := 2;
    end;
  end;
  SetLength(Chars, Count + 2);
  O := 0;
  if FMode <> 0 then
  begin
    while I < Count do
    begin
      if not FHasOddByte then
      begin
        FOddByte := Buffer[I];
        FHasOddByte := True;
      end
      else
      begin
        if FMode = 1 then
          Unit16 := FOddByte or (Buffer[I] shl 8)
        else
          Unit16 := (FOddByte shl 8) or Buffer[I];
        Chars[O] := Char(Unit16);
        Inc(O);
        FHasOddByte := False;
      end;
      Inc(I);
    end;
  end
  else
  begin
    while I < Count do
    begin
      B := Buffer[I];
      Inc(I);
      if FNeed > 0 then
      begin
        if (B and $C0) = $80 then
        begin
          FCodePoint := (FCodePoint shl 6) or (B and $3F);
          Dec(FNeed);
          if FNeed = 0 then
            Emit(FCodePoint);
        end
        else
        begin
          Emit($FFFD);
          FNeed := 0;
          Dec(I);
        end;
      end
      else if B < $80 then
        Emit(B)
      else if (B >= $C2) and (B <= $DF) then
      begin
        FNeed := 1;
        FCodePoint := B and $1F;
      end
      else if (B and $F0) = $E0 then
      begin
        FNeed := 2;
        FCodePoint := B and $0F;
      end
      else if (B >= $F0) and (B <= $F4) then
      begin
        FNeed := 3;
        FCodePoint := B and $07;
      end
      else
        Emit($FFFD);
    end;
  end;
  SetString(Result, PChar(Chars), O);
end;

end.
