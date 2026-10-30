unit unit_XmlTextScanner;

interface

uses
  System.SysUtils;

type
  TMarkupHandler = class
  public
    procedure OpenTag(const Name: string); virtual;
    procedure Attribute(const Name, Value: string); virtual;
    procedure TagReady; virtual;
    procedure CloseTag(const Name: string); virtual;
    procedure Text(const S: string); virtual;
    function Done: Boolean; virtual;
  end;

  TScanState = (msText, msTagOpen, msStartName, msEndName, msEndSkip, msBeforeAttr, msAttrName,
    msAfterAttrName, msBeforeValue, msValueDq, msValueSq, msValueUnq, msSelfClose, msBang, msBangDash,
    msCDataStart, msComment, msCData, msDoctype, msPI, msBogus, msRawText);

  TMarkupScanner = class
  private
    FHandler: TMarkupHandler;
    FHtml: Boolean;
    FState: TScanState;
    FText: TStringBuilder;
    FName: TStringBuilder;
    FAttrName: TStringBuilder;
    FAttrValue: TStringBuilder;
    FEntity: TStringBuilder;
    FInEntity: Boolean;
    FOpenName: string;
    FRawName: string;
    FRawIndex: Integer;
    FCounter: Integer;
    FQuote: Char;
    FDepth: Integer;
    FPiQuestion: Boolean;
    FElementCount: Integer;
    procedure Step(C: Char);
    procedure FlushText;
    procedure EmitChar(C: Char);
    procedure EmitString(const S: string);
    procedure StartEntity;
    procedure ResolveEntity;
    procedure AbortEntity;
    procedure NameDone;
    procedure DeliverAttribute;
    procedure TagFinish(SelfClosing: Boolean);
    procedure StartAttribute(C: Char);
    function CurrentName(Builder: TStringBuilder): string;
  public
    constructor Create(Handler: TMarkupHandler; Html: Boolean);
    destructor Destroy; override;
    procedure Feed(S: PChar; Count: Integer); overload;
    procedure Feed(const S: string); overload;
    procedure Finish;
    property ElementCount: Integer read FElementCount;
  end;

function LocalName(const Name: string): string;

implementation

uses
  unit_MarkupEntities;

const
  NameCap = 256;
  AttrValueCap = 1024 * 1024;
  TextFlushChars = 8192;
  EntityMaxLength = 32;

  VoidElements: array[0..13] of string = ('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
    'meta', 'param', 'source', 'track', 'wbr');

procedure TMarkupHandler.OpenTag(const Name: string);
begin
end;

procedure TMarkupHandler.Attribute(const Name, Value: string);
begin
end;

procedure TMarkupHandler.TagReady;
begin
end;

procedure TMarkupHandler.CloseTag(const Name: string);
begin
end;

procedure TMarkupHandler.Text(const S: string);
begin
end;

function TMarkupHandler.Done: Boolean;
begin
  Result := False;
end;

function LocalName(const Name: string): string;
var
  P: Integer;
begin
  P := LastDelimiter(':', Name);
  if P > 0 then
    Result := Copy(Name, P + 1, MaxInt)
  else
    Result := Name;
end;

function IsSpaceChar(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #12);
end;

function IsEntityChar(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9')) or (C = '#');
end;

function LowerAscii(C: Char): Char;
begin
  if (C >= 'A') and (C <= 'Z') then
    Result := Char(Ord(C) + 32)
  else
    Result := C;
end;

constructor TMarkupScanner.Create(Handler: TMarkupHandler; Html: Boolean);
begin
  inherited Create;
  FHandler := Handler;
  FHtml := Html;
  FText := TStringBuilder.Create;
  FName := TStringBuilder.Create;
  FAttrName := TStringBuilder.Create;
  FAttrValue := TStringBuilder.Create;
  FEntity := TStringBuilder.Create;
end;

destructor TMarkupScanner.Destroy;
begin
  FEntity.Free;
  FAttrValue.Free;
  FAttrName.Free;
  FName.Free;
  FText.Free;
  inherited;
end;

function TMarkupScanner.CurrentName(Builder: TStringBuilder): string;
begin
  Result := Builder.ToString;
  if FHtml then
    Result := LowerCase(Result);
end;

procedure TMarkupScanner.FlushText;
begin
  if FText.Length > 0 then
  begin
    FHandler.Text(FText.ToString);
    FText.Clear;
  end;
end;

procedure TMarkupScanner.EmitChar(C: Char);
begin
  case FState of
    msValueDq, msValueSq, msValueUnq:
      if FAttrValue.Length < AttrValueCap then
        FAttrValue.Append(C);
  else
    FText.Append(C);
    if FText.Length >= TextFlushChars then
      FlushText;
  end;
end;

procedure TMarkupScanner.EmitString(const S: string);
var
  C: Char;
begin
  for C in S do
    EmitChar(C);
end;

procedure TMarkupScanner.StartEntity;
begin
  FInEntity := True;
  FEntity.Clear;
end;

procedure TMarkupScanner.ResolveEntity;
var
  Name, Decoded: string;
begin
  Name := FEntity.ToString;
  FInEntity := False;
  if LookupMarkupEntity(Name, FHtml, Decoded) then
    EmitString(Decoded)
  else
    EmitString('&' + Name + ';');
end;

procedure TMarkupScanner.AbortEntity;
begin
  FInEntity := False;
  EmitString('&' + FEntity.ToString);
end;

procedure TMarkupScanner.NameDone;
begin
  FOpenName := CurrentName(FName);
  Inc(FElementCount);
  FHandler.OpenTag(FOpenName);
end;

procedure TMarkupScanner.DeliverAttribute;
begin
  FHandler.Attribute(CurrentName(FAttrName), FAttrValue.ToString);
  FAttrName.Clear;
  FAttrValue.Clear;
end;

procedure TMarkupScanner.TagFinish(SelfClosing: Boolean);
var
  I: Integer;
  IsVoid: Boolean;
begin
  FHandler.TagReady;
  IsVoid := False;
  if FHtml then
    for I := Low(VoidElements) to High(VoidElements) do
      if VoidElements[I] = FOpenName then
      begin
        IsVoid := True;
        Break;
      end;
  if SelfClosing or IsVoid then
    FHandler.CloseTag(FOpenName);
  if FHtml and not SelfClosing and ((FOpenName = 'script') or (FOpenName = 'style')) then
  begin
    FRawName := FOpenName;
    FRawIndex := 0;
    FState := msRawText;
  end
  else
    FState := msText;
end;

procedure TMarkupScanner.StartAttribute(C: Char);
begin
  FAttrName.Clear;
  FAttrValue.Clear;
  FAttrName.Append(C);
  FState := msAttrName;
end;

procedure TMarkupScanner.Step(C: Char);
const
  CDataTail = 'CDATA[';
var
  Again: Boolean;
begin
  repeat
    Again := False;
    if FInEntity then
    begin
      if IsEntityChar(C) and (FEntity.Length < EntityMaxLength) then
      begin
        FEntity.Append(C);
        Exit;
      end;
      if C = ';' then
      begin
        ResolveEntity;
        Exit;
      end;
      AbortEntity;
    end;
    case FState of
      msText:
        if C = '<' then
        begin
          FlushText;
          FState := msTagOpen;
        end
        else if C = '&' then
          StartEntity
        else
          EmitChar(C);
      msTagOpen:
        if C = '/' then
        begin
          FName.Clear;
          FState := msEndName;
        end
        else if C = '!' then
          FState := msBang
        else if C = '?' then
        begin
          FPiQuestion := False;
          if FHtml then
            FState := msBogus
          else
            FState := msPI;
        end
        else if ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or
          (not FHtml and ((C = '_') or (C = ':') or (Ord(C) > 127))) then
        begin
          FName.Clear;
          FName.Append(C);
          FState := msStartName;
        end
        else
        begin
          FText.Append('<');
          FState := msText;
          Again := True;
        end;
      msStartName:
        if IsSpaceChar(C) then
        begin
          NameDone;
          FState := msBeforeAttr;
        end
        else if C = '>' then
        begin
          NameDone;
          TagFinish(False);
        end
        else if C = '/' then
        begin
          NameDone;
          FState := msSelfClose;
        end
        else if FName.Length < NameCap then
          FName.Append(C);
      msEndName:
        if C = '>' then
        begin
          FHandler.CloseTag(CurrentName(FName));
          FState := msText;
        end
        else if IsSpaceChar(C) then
        begin
          FHandler.CloseTag(CurrentName(FName));
          FState := msEndSkip;
        end
        else if FName.Length < NameCap then
          FName.Append(C);
      msEndSkip:
        if C = '>' then
          FState := msText;
      msBeforeAttr:
        if IsSpaceChar(C) then
        begin
        end
        else if C = '>' then
          TagFinish(False)
        else if C = '/' then
          FState := msSelfClose
        else
          StartAttribute(C);
      msSelfClose:
        if C = '>' then
          TagFinish(True)
        else
        begin
          FState := msBeforeAttr;
          Again := True;
        end;
      msAttrName:
        if IsSpaceChar(C) then
          FState := msAfterAttrName
        else if C = '=' then
        begin
          FAttrValue.Clear;
          FState := msBeforeValue;
        end
        else if C = '>' then
        begin
          DeliverAttribute;
          TagFinish(False);
        end
        else if C = '/' then
        begin
          DeliverAttribute;
          FState := msSelfClose;
        end
        else if FAttrName.Length < NameCap then
          FAttrName.Append(C);
      msAfterAttrName:
        if IsSpaceChar(C) then
        begin
        end
        else if C = '=' then
        begin
          FAttrValue.Clear;
          FState := msBeforeValue;
        end
        else
        begin
          DeliverAttribute;
          FState := msBeforeAttr;
          Again := True;
        end;
      msBeforeValue:
        if IsSpaceChar(C) then
        begin
        end
        else if C = '"' then
          FState := msValueDq
        else if C = '''' then
          FState := msValueSq
        else if C = '>' then
        begin
          DeliverAttribute;
          TagFinish(False);
        end
        else
        begin
          FState := msValueUnq;
          Again := True;
        end;
      msValueDq:
        if C = '"' then
        begin
          DeliverAttribute;
          FState := msBeforeAttr;
        end
        else if C = '&' then
          StartEntity
        else
          EmitChar(C);
      msValueSq:
        if C = '''' then
        begin
          DeliverAttribute;
          FState := msBeforeAttr;
        end
        else if C = '&' then
          StartEntity
        else
          EmitChar(C);
      msValueUnq:
        if IsSpaceChar(C) then
        begin
          DeliverAttribute;
          FState := msBeforeAttr;
        end
        else if C = '>' then
        begin
          DeliverAttribute;
          TagFinish(False);
        end
        else if C = '&' then
          StartEntity
        else
          EmitChar(C);
      msBang:
        if C = '-' then
          FState := msBangDash
        else if C = '[' then
        begin
          FCounter := 0;
          FState := msCDataStart;
        end
        else
        begin
          FDepth := 0;
          FQuote := #0;
          FState := msDoctype;
          Again := True;
        end;
      msBangDash:
        if C = '-' then
        begin
          FCounter := 0;
          FState := msComment;
        end
        else
        begin
          FState := msBogus;
          Again := True;
        end;
      msCDataStart:
        if C = CDataTail[FCounter + 1] then
        begin
          Inc(FCounter);
          if FCounter = Length(CDataTail) then
          begin
            FCounter := 0;
            FState := msCData;
          end;
        end
        else
        begin
          FState := msBogus;
          Again := True;
        end;
      msComment:
        if C = '-' then
        begin
          if FCounter < 2 then
            Inc(FCounter);
        end
        else if (C = '>') and (FCounter >= 2) then
        begin
          FCounter := 0;
          FState := msText;
        end
        else
          FCounter := 0;
      msCData:
        if C = ']' then
        begin
          if FCounter < 2 then
            Inc(FCounter)
          else
            FText.Append(']');
        end
        else if (C = '>') and (FCounter = 2) then
        begin
          FCounter := 0;
          FState := msText;
        end
        else
        begin
          while FCounter > 0 do
          begin
            FText.Append(']');
            Dec(FCounter);
          end;
          FText.Append(C);
          if FText.Length >= TextFlushChars then
            FlushText;
        end;
      msDoctype:
        if FQuote <> #0 then
        begin
          if C = FQuote then
            FQuote := #0;
        end
        else if (C = '"') or (C = '''') then
          FQuote := C
        else if C = '[' then
          Inc(FDepth)
        else if C = ']' then
          Dec(FDepth)
        else if (C = '>') and (FDepth <= 0) then
          FState := msText;
      msPI:
        if C = '?' then
          FPiQuestion := True
        else if (C = '>') and FPiQuestion then
          FState := msText
        else
          FPiQuestion := False;
      msBogus:
        if C = '>' then
          FState := msText;
      msRawText:
        if FRawIndex = 0 then
        begin
          if C = '<' then
            FRawIndex := 1;
        end
        else if FRawIndex = 1 then
        begin
          if C = '/' then
            FRawIndex := 2
          else if C <> '<' then
            FRawIndex := 0;
        end
        else if FRawIndex < 2 + Length(FRawName) then
        begin
          if LowerAscii(C) = FRawName[FRawIndex - 1] then
            Inc(FRawIndex)
          else if C = '<' then
            FRawIndex := 1
          else
            FRawIndex := 0;
        end
        else if IsSpaceChar(C) or (C = '/') or (C = '>') then
        begin
          FRawIndex := 0;
          FHandler.CloseTag(FRawName);
          if C = '>' then
            FState := msText
          else
            FState := msEndSkip;
        end
        else if C = '<' then
          FRawIndex := 1
        else
          FRawIndex := 0;
    end;
  until not Again;
end;

procedure TMarkupScanner.Feed(S: PChar; Count: Integer);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    Step(S[I]);
  FlushText;
end;

procedure TMarkupScanner.Feed(const S: string);
begin
  Feed(PChar(S), Length(S));
end;

procedure TMarkupScanner.Finish;
begin
  if FInEntity then
    AbortEntity;
  FlushText;
end;

end.
