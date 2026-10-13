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

procedure ParseDSCVar(const VarName: string; VarValue: Double;
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
begin
  AName := VarName;
  AUnits := '';
  ADesc := '';
  Lo := LowerCase(VarName);

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
  else if ExtractSuffix('dcpulseduty', Suffix) then
  begin
    AName := 'DC Duty';
    AUnits := '%';
    ADesc := FormatSuffix(Suffix);
  end
  else if ExtractSuffix('dcpulsetime', Suffix) then
  begin
    AName := 'DC Duty';
    AUnits := '%';
    ADesc := FormatSuffix(Suffix);
  end;
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
begin
  Result := nil;
  if Editor.Lines.Count = 0 then
    Exit;

  List := TList<TPluginKeyValue>.Create;
  try
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

      ParseDSCVar(VarName, V, KV.Name, KV.Units, KV.Description);
      KV.Value := V;
      KV.RecType := prCondition;
      KV.IsKey := False;
      List.Add(KV);
    end;

    Result := List.ToArray;
  finally
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
