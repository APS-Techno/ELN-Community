unit unit_SearchTestSupport;

interface

uses
  System.SysUtils;

function NativePath(const Path: string): string;

function RepoFilePath(const Relative: string): string;

function SearchFixturePath(const Name: string): string;

function PlatformManifestPath: string;

procedure SetEnvironmentValue(const Name, Value: string);

{$IFDEF MSWINDOWS}
function NativeLibraryLoaded(const Path: string): Boolean;
{$ENDIF}

function RaisedError(const Action: TProc): string;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Stdlib,
{$ENDIF}
  System.IOUtils, unit_SearchArtifacts;

const
  SourceRootVariable = 'ELN_SOURCE_ROOT';

function NativePath(const Path: string): string;
begin
  Result := Path.Replace('\', '/').Replace('/', PathDelim);
end;

function RepoFilePath(const Relative: string): string;
var
  Dir, Candidate, Native: string;
begin
  Native := NativePath(Relative);
  Dir := GetEnvironmentVariable(SourceRootVariable);
  if Dir <> '' then
  begin
    Result := TPath.Combine(Dir, Native);
    if not TFile.Exists(Result) then
      raise Exception.CreateFmt('%s not found under %s (%s)', [Native, Dir, SourceRootVariable]);
    Exit;
  end;
  Dir := ExtractFileDir(ParamStr(0));
  while Dir <> '' do
  begin
    Candidate := TPath.Combine(Dir, Native);
    if TFile.Exists(Candidate) then
      Exit(Candidate);
    if ExtractFileDir(Dir) = Dir then
      Break;
    Dir := ExtractFileDir(Dir);
  end;
  raise Exception.CreateFmt('%s not found above %s; set %s to the source root', [Native, ParamStr(0),
    SourceRootVariable]);
end;

function SearchFixturePath(const Name: string): string;
begin
  Result := RepoFilePath('ELN.Community.Tests/Fixtures/Search/' + Name);
end;

function PlatformManifestPath: string;
begin
  Result := RepoFilePath('ELN.Search/' + SearchArtifactManifestName);
end;

procedure SetEnvironmentValue(const Name, Value: string);
{$IFDEF POSIX}
var
  NameText, ValueText: UTF8String;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  if Value = '' then
    SetEnvironmentVariable(PChar(Name), nil)
  else
    SetEnvironmentVariable(PChar(Name), PChar(Value));
{$ENDIF}
{$IFDEF POSIX}
  NameText := UTF8String(Name);
  ValueText := UTF8String(Value);
  if Value = '' then
    unsetenv(MarshaledAString(NameText))
  else
    setenv(MarshaledAString(NameText), MarshaledAString(ValueText), 1);
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
function NativeLibraryLoaded(const Path: string): Boolean;
begin
  Result := GetModuleHandle(PChar(Path)) <> 0;
end;
{$ENDIF}

function RaisedError(const Action: TProc): string;
begin
  Result := '';
  try
    Action();
  except
    on E: Exception do
      Result := E.ClassName + ': ' + E.Message;
  end;
end;

end.
