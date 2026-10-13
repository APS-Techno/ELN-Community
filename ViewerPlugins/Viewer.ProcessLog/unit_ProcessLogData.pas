unit unit_ProcessLogData;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  unit_ELNPluginTypes;

type
  TProcessOutcome = (poUnknown, poComplete, poFailed, poAborted, poIncomplete);

  TProcessLogEntry = record
    Time: string;
    Source: string;
    Message: string;
  end;

  TProcessLogData = class
  private
    FHeader: string;
    FRecipeName: string;
    FOutcome: TProcessOutcome;
    FOutcomeLine: string;
    FDurationSec: Double;
    FHasDuration: Boolean;
    FStartTime: string;
    FEndTime: string;
    FEntries: TArray<TProcessLogEntry>;
    FAlarms: TArray<TProcessLogEntry>;
    procedure ParseHeader(const Line: string);
    procedure ParseEntry(const Entry: TProcessLogEntry);
  public
    procedure Clear;
    function LoadFromLines(Lines: TStrings): Boolean;
    function LoadFromFile(const AFileName: string): Boolean;
    function BuildKeyValues: TArray<TPluginKeyValue>;
    function BuildDetailedJson: TJSONObject;

    property Header: string read FHeader;
    property RecipeName: string read FRecipeName;
    property Outcome: TProcessOutcome read FOutcome;
    property OutcomeLine: string read FOutcomeLine;
    property HasDuration: Boolean read FHasDuration;
    property DurationSec: Double read FDurationSec;
    property Entries: TArray<TProcessLogEntry> read FEntries;
    property Alarms: TArray<TProcessLogEntry> read FAlarms;
  end;

function ProcessOutcomeName(Outcome: TProcessOutcome): string;
function TryParseRecipeElapsed(const Text: string; out Seconds: Double): Boolean;
function TryParseProcessLogLine(const Line: string; out Entry: TProcessLogEntry): Boolean;

implementation

uses
  System.IOUtils, System.DateUtils, System.StrUtils, System.RegularExpressions;

const
  OUTCOME_NAMES: array[TProcessOutcome] of string =
    ('unknown', 'complete', 'failed', 'aborted', 'incomplete');

function ProcessOutcomeName(Outcome: TProcessOutcome): string;
begin
  Result := OUTCOME_NAMES[Outcome];
end;

function TryParseRecipeElapsed(const Text: string; out Seconds: Double): Boolean;
var
  M: TMatch;
  H, Mi: Integer;
  S: Double;
begin
  Seconds := 0;
  M := TRegEx.Match(Text, '^\s*(?:(\d+)h\s+)?(?:(\d+)m\s+)?(\d+(?:\.\d+)?)s\s*$');
  Result := M.Success;
  if not Result then Exit;
  H := StrToIntDef(M.Groups[1].Value, 0);
  Mi := StrToIntDef(M.Groups[2].Value, 0);
  Result := TryStrToFloat(M.Groups[3].Value, S, TFormatSettings.Invariant);
  if Result then
    Seconds := H * 3600 + Mi * 60 + S;
end;

function TryParseProcessLogLine(const Line: string; out Entry: TProcessLogEntry): Boolean;
var
  M: TMatch;
begin
  M := TRegEx.Match(Line, '^(\d{1,2}:\d{2}:\d{2}(?:\.\d+)?)\s+\[([^\]]*)\]\s?(.*)$');
  Result := M.Success;
  if Result then
  begin
    Entry.Time := M.Groups[1].Value;
    Entry.Source := M.Groups[2].Value;
    Entry.Message := Trim(M.Groups[3].Value);
  end;
end;

procedure TProcessLogData.Clear;
begin
  FHeader := '';
  FRecipeName := '';
  FOutcome := poUnknown;
  FOutcomeLine := '';
  FDurationSec := 0;
  FHasDuration := False;
  FStartTime := '';
  FEndTime := '';
  FEntries := nil;
  FAlarms := nil;
end;

function TProcessLogData.LoadFromFile(const AFileName: string): Boolean;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName);
    except
      Clear;
      Exit(False);
    end;
    Result := LoadFromLines(Lines);
  finally
    Lines.Free;
  end;
end;

procedure TProcessLogData.ParseHeader(const Line: string);
var
  M: TMatch;
  StartDT, EndDT: TDateTime;
  Fmt: TFormatSettings;
begin
  FHeader := Line;
  M := TRegEx.Match(Line,
    '^---\s+\S+:\s+(.*?)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+to\s+' +
    '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\s+---\s*$');
  if not M.Success then Exit;
  if FRecipeName = '' then
    FRecipeName := M.Groups[1].Value;
  FStartTime := M.Groups[2].Value;
  FEndTime := M.Groups[3].Value;
  Fmt := TFormatSettings.Invariant;
  Fmt.DateSeparator := '-';
  Fmt.ShortDateFormat := 'yyyy-mm-dd';
  Fmt.TimeSeparator := ':';
  Fmt.DecimalSeparator := '.';
  if TryStrToDateTime(FStartTime, StartDT, Fmt) and
    TryStrToDateTime(FEndTime, EndDT, Fmt) and (EndDT >= StartDT) then
  begin
    FDurationSec := MilliSecondsBetween(EndDT, StartDT) / 1000;
    FHasDuration := True;
  end;
end;

procedure TProcessLogData.ParseEntry(const Entry: TProcessLogEntry);
const
  LABELS: array[poComplete..poIncomplete] of string =
    ('complete', 'failed', 'aborted', 'INCOMPLETE');
var
  M: TMatch;
  O: TProcessOutcome;
  Elapsed: Double;
begin
  if SameText(Entry.Source, 'Interlock') or
    StartsText('INCOMPLETE step', Entry.Message) then
    FAlarms := FAlarms + [Entry];

  if not SameText(Entry.Source, 'Recipe') then Exit;

  M := TRegEx.Match(Entry.Message, '^Recipe started:\s*(.+)$');
  if M.Success then
  begin
    FRecipeName := Trim(M.Groups[1].Value);
    Exit;
  end;

  for O := Low(LABELS) to High(LABELS) do
  begin
    M := TRegEx.Match(Entry.Message,
      '^Recipe ' + LABELS[O] + ':\s*(.*?)\s*\(([^)]*)\)', [roIgnoreCase]);
    if not M.Success then Continue;
    FOutcome := O;
    FOutcomeLine := Entry.Message;
    if M.Groups[1].Value <> '' then
      FRecipeName := M.Groups[1].Value;
    if TryParseRecipeElapsed(M.Groups[2].Value, Elapsed) then
    begin
      FDurationSec := Elapsed;
      FHasDuration := True;
    end;
    Exit;
  end;
end;

function TProcessLogData.LoadFromLines(Lines: TStrings): Boolean;
var
  I: Integer;
  Line: string;
  Entry: TProcessLogEntry;
begin
  Clear;
  for I := 0 to Lines.Count - 1 do
  begin
    Line := Lines[I];
    if (FHeader = '') and Line.StartsWith('---') then
      ParseHeader(Trim(Line))
    else if TryParseProcessLogLine(Line, Entry) then
    begin
      FEntries := FEntries + [Entry];
      ParseEntry(Entry);
    end;
  end;
  Result := (FHeader <> '') or (Length(FEntries) > 0);
end;

function TProcessLogData.BuildKeyValues: TArray<TPluginKeyValue>;
var
  KV: TPluginKeyValue;
begin
  Result := nil;
  if (FHeader = '') and (Length(FEntries) = 0) then Exit;

  if FHasDuration then
  begin
    KV.Name := 'Process.Duration';
    KV.Value := FDurationSec;
    KV.Units := 's';
    KV.Description := 'Recipe run time (' + FRecipeName + ')';
    KV.RecType := prResult;
    KV.IsKey := True;
    Result := Result + [KV];
  end;

  KV.Name := 'Process.AlarmCount';
  KV.Value := Length(FAlarms);
  KV.Units := '';
  KV.Description := 'Interlock blocks and incomplete steps (' + FRecipeName + ')';
  KV.RecType := prResult;
  KV.IsKey := True;
  Result := Result + [KV];

  if FOutcome <> poUnknown then
  begin
    KV.Name := 'Process.Outcome';
    KV.Value := Ord(FOutcome);
    KV.Units := '';
    KV.Description := 'Recipe ' + OUTCOME_NAMES[FOutcome] +
      ' (1 complete, 2 failed, 3 aborted, 4 incomplete): ' + FRecipeName;
    KV.RecType := prResult;
    KV.IsKey := True;
    Result := Result + [KV];
  end;
end;

function TProcessLogData.BuildDetailedJson: TJSONObject;
var
  JAlarms: TJSONArray;
  JA: TJSONObject;
  A: TProcessLogEntry;
begin
  Result := TJSONObject.Create;
  Result.AddPair('header', FHeader);
  Result.AddPair('recipe', FRecipeName);
  Result.AddPair('outcome', OUTCOME_NAMES[FOutcome]);
  if FOutcomeLine <> '' then
    Result.AddPair('outcomeLine', FOutcomeLine);
  if FStartTime <> '' then
    Result.AddPair('windowStart', FStartTime);
  if FEndTime <> '' then
    Result.AddPair('windowEnd', FEndTime);
  if FHasDuration then
    Result.AddPair('durationSec', JNum(FDurationSec));
  Result.AddPair('lines', TJSONNumber.Create(Length(FEntries)));
  JAlarms := TJSONArray.Create;
  for A in FAlarms do
  begin
    JA := TJSONObject.Create;
    JA.AddPair('time', A.Time);
    JA.AddPair('source', A.Source);
    JA.AddPair('message', A.Message);
    JAlarms.AddElement(JA);
  end;
  Result.AddPair('alarms', JAlarms);
end;

end.
