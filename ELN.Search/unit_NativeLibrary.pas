unit unit_NativeLibrary;

interface

function LoadNativeLibrary(const Path: string): NativeUInt;

function NativeSymbol(Handle: NativeUInt; const Name: string): Pointer;

procedure FreeNativeLibrary(Handle: NativeUInt);

function NativeLoadError: string;

// WinHTTP rounds its timeouts up to steps of about 4 s, so a deadline needs a Cancel from a
// second thread. Curl keeps CURLOPT_TIMEOUT_MS exactly, and its Cancel frees the handle while
// curl_easy_perform still uses it.
function HttpDeadlineNeedsCancel: Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Dlfcn,
{$ENDIF}
  System.SysUtils;

const
  ErrorTextSize = 1024;

threadvar
  LastErrorText: array[0..ErrorTextSize - 1] of WideChar;

procedure KeepError(const Text: string);
var
  Count: Integer;
begin
  Count := Length(Text);
  if Count > ErrorTextSize - 1 then
    Count := ErrorTextSize - 1;
  if Count > 0 then
    Move(PChar(Text)^, LastErrorText[0], Count * SizeOf(WideChar));
  LastErrorText[Count] := #0;
end;

procedure KeepSystemError;
begin
{$IFDEF MSWINDOWS}
  KeepError(SysErrorMessage(GetLastError));
{$ENDIF}
{$IFDEF POSIX}
  KeepError(string(UTF8String(dlerror)));
{$ENDIF}
end;

function LoadNativeLibrary(const Path: string): NativeUInt;
{$IFDEF POSIX}
var
  PathText: UTF8String;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  Result := LoadLibraryEx(PChar(Path), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
{$ENDIF}
{$IFDEF POSIX}
  PathText := UTF8String(Path);
  Result := dlopen(MarshaledAString(PathText), RTLD_NOW or RTLD_LOCAL);
{$ENDIF}
  if Result = 0 then
    KeepSystemError;
end;

function NativeSymbol(Handle: NativeUInt; const Name: string): Pointer;
var
  NameText: UTF8String;
begin
  NameText := UTF8String(Name);
{$IFDEF MSWINDOWS}
  Result := GetProcAddress(HMODULE(Handle), PAnsiChar(NameText));
{$ENDIF}
{$IFDEF POSIX}
  dlerror;
  Result := dlsym(Handle, MarshaledAString(NameText));
{$ENDIF}
  if Result = nil then
    KeepSystemError;
end;

procedure FreeNativeLibrary(Handle: NativeUInt);
begin
  if Handle = 0 then
    Exit;
{$IFDEF MSWINDOWS}
  FreeLibrary(HMODULE(Handle));
{$ENDIF}
{$IFDEF POSIX}
  dlclose(Handle);
{$ENDIF}
end;

function NativeLoadError: string;
begin
  Result := PChar(@LastErrorText[0]);
end;

function HttpDeadlineNeedsCancel: Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := True;
{$ENDIF}
{$IFDEF POSIX}
  Result := False;
{$ENDIF}
end;

end.
