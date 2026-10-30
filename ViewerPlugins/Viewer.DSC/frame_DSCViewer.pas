unit frame_DSCViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  SynEditHighlighter, SynHighlighterGeneral, SynEdit, RzLabel, Vcl.ExtCtrls,
  RzPanel,
  unit_ELNPluginCore, unit_ELNPluginTypes;

type

  TframeDSCViewer = class(TFrame)
    Editor: TSynEdit;
    Syn: TSynGeneralSyn;
    RzPanel1: TRzPanel;
    lblTitle: TRzLabel;
  private
  public
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
  end;

implementation

uses
  System.Generics.Collections, System.JSON, System.Character,
  unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}


function TframeDSCViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  i, Y, LineH, MaxLines: Integer;
begin
  Result := nil;
  if Editor.Lines.Count = 0 then
    Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    Large.Canvas.Brush.Color := ThemePanelColor;
    Large.Canvas.FillRect(Rect(0, 0, 800, 600));
    Large.Canvas.Font.Name := Editor.Font.Name;
    Large.Canvas.Font.Size := Editor.Font.Size;
    Large.Canvas.Font.Color := ThemeTextColor;

    LineH := Large.Canvas.TextHeight('Wg') + 2;
    MaxLines := 600 div LineH;
    if MaxLines > Editor.Lines.Count then
      MaxLines := Editor.Lines.Count;

    Y := 4;
    for i := 0 to MaxLines - 1 do
    begin
      Large.Canvas.TextOut(4, Y, Editor.Lines[i]);
      Y := Y + LineH;
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

type
  TDSCPulseKind = (pkUnknown, pkMicroseconds, pkPercent);

function PulseKindOfCommand(const Target, Command: string): TDSCPulseKind;
var
  Cmd: string;
begin
  Cmd := LowerCase(Command);
  if (Cmd = 'pd') or (Cmd = 'pulseduration') or (Cmd = 'pulsetime') then
    Result := pkMicroseconds
  else if Cmd = 'duty' then
    Result := pkPercent
  else if Cmd = 'dutycycle' then
  begin
    if LowerCase(Target).Contains('dc4001') then
      Result := pkMicroseconds
    else
      Result := pkPercent;
  end
  else
    Result := pkUnknown;
end;

procedure CollectPulseUsage(Lines: TStrings; Usage: TDictionary<string, TDSCPulseKind>);
var
  I: Integer;
  InScript: Boolean;
  Statement, Key: string;
  Tokens: TArray<string>;
  Kind, Seen: TDSCPulseKind;
begin
  InScript := False;
  for I := 0 to Lines.Count - 1 do
  begin
    if not InScript then
    begin
      InScript := Trim(Lines[I]).StartsWith('start', True);
      Continue;
    end;
    for Statement in Lines[I].Split([';']) do
    begin
      Tokens := Trim(Statement).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      if (Length(Tokens) < 4) or not SameText(Tokens[0], 'set') then
        Continue;
      Kind := PulseKindOfCommand(Tokens[1], Tokens[2]);
      if Kind = pkUnknown then
        Continue;
      Key := LowerCase(Tokens[3]);
      if Usage.TryGetValue(Key, Seen) and (Seen <> Kind) then
        Usage[Key] := pkUnknown
      else
        Usage.AddOrSetValue(Key, Kind);
    end;
  end;
end;

procedure ParseDSCVar(const VarName: string; VarValue: Double; Kind: TDSCPulseKind;
  out AName, AUnits, ADesc: string);
var
  Lo: string;

  function ExtractSuffix(const Prefix: string; out Suffix: string): Boolean;
  begin
    Result := Lo.StartsWith(Prefix);
    if Result then
      Suffix := Copy(VarName, Length(Prefix) + 1, MaxInt);
  end;

  function FormatSuffix(const Raw: string): string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 1 to Length(Raw) do
    begin
      if (I > 1) and Raw[I].IsUpper and not Raw[I-1].IsUpper then
        Result := Result + ' ';
      Result := Result + Raw[I];
    end;
  end;

var
  Suffix: string;
  Qualify: Boolean;
begin
  AName := VarName;
  AUnits := '';
  ADesc := '';
  Lo := LowerCase(VarName);
  Qualify := True;

  if ExtractSuffix('current', Suffix) then
  begin
    AName := 'Current';
    AUnits := 'mA';
    ADesc := FormatSuffix(Suffix);
  end
  else if ExtractSuffix('time', Suffix) then
  begin
    AName := 'Time';
    AUnits := 's';
    ADesc := FormatSuffix(Suffix);
  end
  else if ExtractSuffix('cleaningpressure', Suffix) then
  begin
    AName := 'Pressure';
    AUnits := 'Pa';
    ADesc := 'Cleaning';
  end
  else if ExtractSuffix('cleaningtime', Suffix) then
  begin
    AName := 'Time';
    AUnits := 's';
    ADesc := 'Cleaning';
  end
  else if ExtractSuffix('warmuptime', Suffix) then
  begin
    AName := 'Time';
    AUnits := 'min';
    ADesc := 'Warm-up';
  end
  else if Lo = 'p' then
  begin
    AName := 'Pressure';
    AUnits := 'Pa';
  end
  else if Lo = 'n' then
  begin
    AName := 'N';
    ADesc := 'repeats';
    Qualify := False;
  end
  else if ExtractSuffix('mfc_', Suffix) then
  begin
    AName := 'MFC';
    AUnits := 'sccm';
    ADesc := 'Ch.' + Suffix;
  end
  else if ExtractSuffix('dcfreq', Suffix) then
  begin
    AName := 'DC Freq';
    AUnits := 'kHz';
    ADesc := FormatSuffix(Suffix);
  end
  else if ExtractSuffix('dcpulseduty', Suffix) or ExtractSuffix('dcpulsetime', Suffix) then
  begin
    if (Kind = pkUnknown) and Lo.StartsWith('dcpulseduty') then
      Kind := pkPercent;
    case Kind of
      pkMicroseconds:
        begin
          AName := 'DC Pulse Time';
          AUnits := 'us';
        end;
      pkPercent:
        begin
          AName := 'DC Duty';
          AUnits := '%';
        end;
    else
      AName := 'DC Pulse';
      AUnits := '';
    end;
    ADesc := FormatSuffix(Suffix);
  end;

  if Qualify and (ADesc <> '') then
    AName := AName + '.' + ADesc;
end;

function TframeDSCViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  I: Integer;
  Line, VarName, ValStr: string;
  V: Double;
  SpacePos: Integer;
  Code: Integer;
  Used: TDictionary<string, Integer>;
  Count: Integer;
  Usage: TDictionary<string, TDSCPulseKind>;
  PulseKind: TDSCPulseKind;
begin
  Result := nil;
  if Editor.Lines.Count = 0 then
    Exit;

  List := TList<TPluginKeyValue>.Create;
  Used := TDictionary<string, Integer>.Create;
  Usage := TDictionary<string, TDSCPulseKind>.Create;
  try
    CollectPulseUsage(Editor.Lines, Usage);
    for I := 0 to Editor.Lines.Count - 1 do
    begin
      Line := Trim(Editor.Lines[I]);
      if not Line.StartsWith('var ', True) then
      begin
        if Line.StartsWith('start', True) then
          Break;
        Continue;
      end;

      // Parse: var <name> <value>
      Line := Trim(Copy(Line, 5, MaxInt));
      SpacePos := Pos(' ', Line);
      if SpacePos = 0 then
        Continue;

      VarName := Copy(Line, 1, SpacePos - 1);
      ValStr := Trim(Copy(Line, SpacePos + 1, MaxInt));
      Val(ValStr, V, Code);
      if Code <> 0 then
        Continue;

      if not Usage.TryGetValue(LowerCase(VarName), PulseKind) then
        PulseKind := pkUnknown;
      ParseDSCVar(VarName, V, PulseKind, KV.Name, KV.Units, KV.Description);
      if Used.TryGetValue(KV.Name, Count) then
      begin
        Inc(Count);
        Used[KV.Name] := Count;
        KV.Name := KV.Name + '#' + IntToStr(Count);
      end
      else
        Used.Add(KV.Name, 1);
      KV.Value := V;
      KV.RecType := prCondition;
      KV.IsKey := False;
      List.Add(KV);
    end;

    Result := List.ToArray;
  finally
    Usage.Free;
    Used.Free;
    List.Free;
  end;
end;

function TframeDSCViewer.GetDetailedInfo: string;
var
  J: TJSONObject;
  JVars: TJSONObject;
  I: Integer;
  Line, VarName, ValStr: string;
  V: Double;
  SpacePos, Code: Integer;
  HasScript: Boolean;
  Script: TStringList;
begin
  Result := '';
  if Editor.Lines.Count = 0 then
    Exit;

  J := TJSONObject.Create;
  JVars := TJSONObject.Create;
  Script := TStringList.Create;
  try
    HasScript := False;

    for I := 0 to Editor.Lines.Count - 1 do
    begin
      Line := Trim(Editor.Lines[I]);

      if HasScript then
      begin
        Script.Add(Line);
        Continue;
      end;

      if Line.StartsWith('start', True) then
      begin
        HasScript := True;
        Continue;
      end;

      if not Line.StartsWith('var ', True) then
        Continue;

      Line := Trim(Copy(Line, 5, MaxInt));
      SpacePos := Pos(' ', Line);
      if SpacePos = 0 then
        Continue;

      VarName := Copy(Line, 1, SpacePos - 1);
      ValStr := Trim(Copy(Line, SpacePos + 1, MaxInt));
      Val(ValStr, V, Code);
      if Code = 0 then
        JVars.AddPair(VarName, JNum(V))
      else
        JVars.AddPair(VarName, ValStr);
    end;

    J.AddPair('variables', JVars);
    J.AddPair('script', Script.Text);
    Result := J.ToJSON;
  finally
    Script.Free;
    J.Free;
  end;
end;

end.
