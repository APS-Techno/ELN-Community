unit unit_OnnxRuntimeApi;

interface

uses
  System.SysUtils;

const
  OrtApiVersion = 31;

  OrtElementFloat = 1;
  OrtElementInt64 = 7;

type
  EOnnxRuntimeError = class(Exception);

  TOrtTensorInfo = record
    ElementType: Integer;
    Dimensions: TArray<Int64>;
  end;

  TOrtInt64Input = record
    Name: string;
    Data: TArray<Int64>;
    Shape: TArray<Int64>;
  end;

  TOrtFloatOutput = record
    Data: TArray<Single>;
    Shape: TArray<Int64>;
  end;

  TOrtRuntime = class
  private
    FLibrary: NativeUInt;
    FLibraryPath: string;
    FApi: Pointer;
    FVersion: string;
    FEnv: Pointer;
    function Fn(Index: Integer): Pointer;
  public
    constructor Create(const LibraryPath: string);
    destructor Destroy; override;
    procedure Check(Status: Pointer; const Context: string);
    property Api: Pointer read FApi;
    property Env: Pointer read FEnv;
    property Version: string read FVersion;
    property LibraryPath: string read FLibraryPath;
  end;

  TOrtSession = class
  private
    FRuntime: TOrtRuntime;
    FSession: Pointer;
    FMemoryInfo: Pointer;
    FInputNames: TArray<string>;
    FOutputNames: TArray<string>;
    FInputInfo: TArray<TOrtTensorInfo>;
    FOutputInfo: TArray<TOrtTensorInfo>;
    function ReadName(Index: NativeUInt; Output: Boolean): string;
    function ReadTypeInfo(Index: NativeUInt; Output: Boolean): TOrtTensorInfo;
  public
    constructor Create(Runtime: TOrtRuntime; const ModelPath: string; IntraOpThreads: Integer);
    destructor Destroy; override;
    function Run(const Inputs: TArray<TOrtInt64Input>; const OutputName: string): TOrtFloatOutput;
    property InputNames: TArray<string> read FInputNames;
    property OutputNames: TArray<string> read FOutputNames;
    property InputInfo: TArray<TOrtTensorInfo> read FInputInfo;
    property OutputInfo: TArray<TOrtTensorInfo> read FOutputInfo;
  end;

implementation

uses
  unit_NativeLibrary;

{ Indexes into struct OrtApi of onnxruntime_c_api.h, ORT 1.31.1 (ORT_API_VERSION 31).
  The table only grows at its end, so these indexes hold for every runtime that
  returns a table for OrtApiVersion. }
const
  IdxGetErrorMessage = 2;
  IdxCreateEnv = 3;
  IdxCreateSession = 7;
  IdxRun = 9;
  IdxCreateSessionOptions = 10;
  IdxSetSessionGraphOptimizationLevel = 23;
  IdxSetIntraOpNumThreads = 24;
  IdxSessionGetInputCount = 30;
  IdxSessionGetOutputCount = 31;
  IdxSessionGetInputTypeInfo = 33;
  IdxSessionGetOutputTypeInfo = 34;
  IdxSessionGetInputName = 36;
  IdxSessionGetOutputName = 37;
  IdxCreateTensorWithDataAsOrtValue = 49;
  IdxGetTensorMutableData = 51;
  IdxCastTypeInfoToTensorInfo = 55;
  IdxGetTensorElementType = 60;
  IdxGetDimensionsCount = 61;
  IdxGetDimensions = 62;
  IdxGetTensorTypeAndShape = 65;
  IdxCreateCpuMemoryInfo = 69;
  IdxAllocatorFree = 76;
  IdxGetAllocatorWithDefaultOptions = 78;
  IdxReleaseEnv = 92;
  IdxReleaseStatus = 93;
  IdxReleaseMemoryInfo = 94;
  IdxReleaseSession = 95;
  IdxReleaseValue = 96;
  IdxReleaseTypeInfo = 98;
  IdxReleaseTensorTypeAndShapeInfo = 99;
  IdxReleaseSessionOptions = 100;

  OrtLoggingLevelWarning = 2;
  OrtEnableAll = 99;
  OrtArenaAllocator = 1;
  OrtMemTypeDefault = 0;

type
  TOrtApiTable = array[0..1023] of Pointer;
  POrtApiTable = ^TOrtApiTable;

  TOrtGetApi = function(Version: Cardinal): Pointer; stdcall;
  TOrtGetVersionString = function: PAnsiChar; stdcall;
  TOrtApiBase = record
    GetApi: TOrtGetApi;
    GetVersionString: TOrtGetVersionString;
  end;
  POrtApiBase = ^TOrtApiBase;
  TOrtGetApiBase = function: POrtApiBase; stdcall;

  TGetErrorMessage = function(Status: Pointer): PAnsiChar; stdcall;
  TReleasePointer = procedure(Handle: Pointer); stdcall;
  TCreateEnv = function(LogLevel: Integer; LogId: PAnsiChar; out Env: Pointer): Pointer; stdcall;
  TCreateSession = function(Env: Pointer; ModelPath: Pointer; Options: Pointer;
    out Session: Pointer): Pointer; stdcall;
  TRun = function(Session: Pointer; RunOptions: Pointer; InputNames: PPAnsiChar;
    Inputs: PPointer; InputCount: NativeUInt; OutputNames: PPAnsiChar;
    OutputCount: NativeUInt; Outputs: PPointer): Pointer; stdcall;
  TCreateSessionOptions = function(out Options: Pointer): Pointer; stdcall;
  TSetGraphOptimizationLevel = function(Options: Pointer; Level: Integer): Pointer; stdcall;
  TSetIntraOpNumThreads = function(Options: Pointer; Threads: Integer): Pointer; stdcall;
  TSessionGetCount = function(Session: Pointer; out Count: NativeUInt): Pointer; stdcall;
  TSessionGetTypeInfo = function(Session: Pointer; Index: NativeUInt;
    out TypeInfo: Pointer): Pointer; stdcall;
  TSessionGetName = function(Session: Pointer; Index: NativeUInt; Allocator: Pointer;
    out Name: PAnsiChar): Pointer; stdcall;
  TCreateTensorWithData = function(MemoryInfo: Pointer; Data: Pointer; DataBytes: NativeUInt;
    Shape: PInt64; ShapeCount: NativeUInt; ElementType: Integer; out Value: Pointer): Pointer; stdcall;
  TGetTensorMutableData = function(Value: Pointer; out Data: Pointer): Pointer; stdcall;
  TCastTypeInfoToTensorInfo = function(TypeInfo: Pointer; out TensorInfo: Pointer): Pointer; stdcall;
  TGetTensorElementType = function(Info: Pointer; out ElementType: Integer): Pointer; stdcall;
  TGetDimensionsCount = function(Info: Pointer; out Count: NativeUInt): Pointer; stdcall;
  TGetDimensions = function(Info: Pointer; Dims: PInt64; Count: NativeUInt): Pointer; stdcall;
  TGetTensorTypeAndShape = function(Value: Pointer; out Info: Pointer): Pointer; stdcall;
  TCreateCpuMemoryInfo = function(AllocatorType: Integer; MemType: Integer;
    out MemoryInfo: Pointer): Pointer; stdcall;
  TAllocatorFree = function(Allocator: Pointer; P: Pointer): Pointer; stdcall;
  TGetAllocatorWithDefaultOptions = function(out Allocator: Pointer): Pointer; stdcall;

function ReadShape(Runtime: TOrtRuntime; Info: Pointer; const Context: string): TArray<Int64>;
var
  Count: NativeUInt;
begin
  Runtime.Check(TGetDimensionsCount(POrtApiTable(Runtime.Api)^[IdxGetDimensionsCount])(Info, Count), Context);
  SetLength(Result, Count);
  if Count > 0 then
    Runtime.Check(TGetDimensions(POrtApiTable(Runtime.Api)^[IdxGetDimensions])(Info, @Result[0], Count), Context);
end;

function ElementCount(const Shape: TArray<Int64>): Int64;
var
  D: Int64;
begin
  Result := 1;
  for D in Shape do
  begin
    if D < 0 then
      raise EOnnxRuntimeError.Create('Tensor shape has an unresolved dimension');
    Result := Result * D;
  end;
end;

{ TOrtRuntime }

constructor TOrtRuntime.Create(const LibraryPath: string);
var
  GetApiBase: TOrtGetApiBase;
  Base: POrtApiBase;
begin
  inherited Create;
  FLibraryPath := LibraryPath;
  if not FileExists(LibraryPath) then
    raise EOnnxRuntimeError.CreateFmt('ONNX Runtime is not installed: %s is missing', [LibraryPath]);
  { A bare-name load could resolve to the older onnxruntime.dll that Windows ships in System32. }
  FLibrary := LoadNativeLibrary(LibraryPath);
  if FLibrary = 0 then
    raise EOnnxRuntimeError.CreateFmt('ONNX Runtime is not installed correctly: %s cannot be loaded (%s)',
      [LibraryPath, NativeLoadError]);
  @GetApiBase := NativeSymbol(FLibrary, 'OrtGetApiBase');
  if not Assigned(GetApiBase) then
    raise EOnnxRuntimeError.CreateFmt('%s does not export OrtGetApiBase', [LibraryPath]);
  Base := GetApiBase();
  FVersion := string(AnsiString(Base^.GetVersionString()));
  FApi := Base^.GetApi(OrtApiVersion);
  if FApi = nil then
    raise EOnnxRuntimeError.CreateFmt('ONNX Runtime %s does not provide C API version %d',
      [FVersion, OrtApiVersion]);
  Check(TCreateEnv(Fn(IdxCreateEnv))(OrtLoggingLevelWarning, 'eln-search', FEnv), 'CreateEnv');
end;

destructor TOrtRuntime.Destroy;
begin
  if FEnv <> nil then
    TReleasePointer(Fn(IdxReleaseEnv))(FEnv);
  if FLibrary <> 0 then
    FreeNativeLibrary(FLibrary);
  inherited;
end;

function TOrtRuntime.Fn(Index: Integer): Pointer;
begin
  Result := POrtApiTable(FApi)^[Index];
end;

procedure TOrtRuntime.Check(Status: Pointer; const Context: string);
var
  Msg: string;
begin
  if Status = nil then
    Exit;
  Msg := string(UTF8String(TGetErrorMessage(Fn(IdxGetErrorMessage))(Status)));
  TReleasePointer(Fn(IdxReleaseStatus))(Status);
  raise EOnnxRuntimeError.CreateFmt('%s failed: %s', [Context, Msg]);
end;

{ TOrtSession }

constructor TOrtSession.Create(Runtime: TOrtRuntime; const ModelPath: string; IntraOpThreads: Integer);
var
  Options: Pointer;
  Count: NativeUInt;
  I: NativeUInt;
{$IFNDEF MSWINDOWS}
  ModelPathText: UTF8String;
{$ENDIF}
begin
  inherited Create;
  FRuntime := Runtime;
  if not FileExists(ModelPath) then
    raise EOnnxRuntimeError.CreateFmt('ONNX model not found: %s', [ModelPath]);
  Runtime.Check(TCreateSessionOptions(Runtime.Fn(IdxCreateSessionOptions))(Options), 'CreateSessionOptions');
  try
    Runtime.Check(TSetGraphOptimizationLevel(Runtime.Fn(IdxSetSessionGraphOptimizationLevel))(Options,
      OrtEnableAll), 'SetSessionGraphOptimizationLevel');
    if IntraOpThreads > 0 then
      Runtime.Check(TSetIntraOpNumThreads(Runtime.Fn(IdxSetIntraOpNumThreads))(Options, IntraOpThreads),
        'SetIntraOpNumThreads');
{$IFDEF MSWINDOWS}
    Runtime.Check(TCreateSession(Runtime.Fn(IdxCreateSession))(Runtime.Env, PWideChar(ModelPath),
      Options, FSession), 'CreateSession');
{$ELSE}
    ModelPathText := UTF8String(ModelPath);
    Runtime.Check(TCreateSession(Runtime.Fn(IdxCreateSession))(Runtime.Env, PAnsiChar(ModelPathText),
      Options, FSession), 'CreateSession');
{$ENDIF}
  finally
    TReleasePointer(Runtime.Fn(IdxReleaseSessionOptions))(Options);
  end;
  Runtime.Check(TCreateCpuMemoryInfo(Runtime.Fn(IdxCreateCpuMemoryInfo))(OrtArenaAllocator,
    OrtMemTypeDefault, FMemoryInfo), 'CreateCpuMemoryInfo');

  Runtime.Check(TSessionGetCount(Runtime.Fn(IdxSessionGetInputCount))(FSession, Count), 'SessionGetInputCount');
  SetLength(FInputNames, Count);
  SetLength(FInputInfo, Count);
  if Count > 0 then
    for I := 0 to Count - 1 do
    begin
      FInputNames[I] := ReadName(I, False);
      FInputInfo[I] := ReadTypeInfo(I, False);
    end;
  Runtime.Check(TSessionGetCount(Runtime.Fn(IdxSessionGetOutputCount))(FSession, Count), 'SessionGetOutputCount');
  SetLength(FOutputNames, Count);
  SetLength(FOutputInfo, Count);
  if Count > 0 then
    for I := 0 to Count - 1 do
    begin
      FOutputNames[I] := ReadName(I, True);
      FOutputInfo[I] := ReadTypeInfo(I, True);
    end;
end;

destructor TOrtSession.Destroy;
begin
  if FMemoryInfo <> nil then
    TReleasePointer(FRuntime.Fn(IdxReleaseMemoryInfo))(FMemoryInfo);
  if FSession <> nil then
    TReleasePointer(FRuntime.Fn(IdxReleaseSession))(FSession);
  inherited;
end;

function TOrtSession.ReadName(Index: NativeUInt; Output: Boolean): string;
var
  Allocator: Pointer;
  Name: PAnsiChar;
  Idx: Integer;
begin
  FRuntime.Check(TGetAllocatorWithDefaultOptions(FRuntime.Fn(IdxGetAllocatorWithDefaultOptions))(Allocator),
    'GetAllocatorWithDefaultOptions');
  if Output then
    Idx := IdxSessionGetOutputName
  else
    Idx := IdxSessionGetInputName;
  FRuntime.Check(TSessionGetName(FRuntime.Fn(Idx))(FSession, Index, Allocator, Name), 'SessionGetName');
  try
    Result := string(UTF8String(Name));
  finally
    FRuntime.Check(TAllocatorFree(FRuntime.Fn(IdxAllocatorFree))(Allocator, Name), 'AllocatorFree');
  end;
end;

function TOrtSession.ReadTypeInfo(Index: NativeUInt; Output: Boolean): TOrtTensorInfo;
var
  TypeInfo, TensorInfo: Pointer;
  Idx: Integer;
begin
  if Output then
    Idx := IdxSessionGetOutputTypeInfo
  else
    Idx := IdxSessionGetInputTypeInfo;
  FRuntime.Check(TSessionGetTypeInfo(FRuntime.Fn(Idx))(FSession, Index, TypeInfo), 'SessionGetTypeInfo');
  try
    FRuntime.Check(TCastTypeInfoToTensorInfo(FRuntime.Fn(IdxCastTypeInfoToTensorInfo))(TypeInfo, TensorInfo),
      'CastTypeInfoToTensorInfo');
    if TensorInfo = nil then
    begin
      Result.ElementType := 0;
      Result.Dimensions := nil;
      Exit;
    end;
    FRuntime.Check(TGetTensorElementType(FRuntime.Fn(IdxGetTensorElementType))(TensorInfo, Result.ElementType),
      'GetTensorElementType');
    Result.Dimensions := ReadShape(FRuntime, TensorInfo, 'GetDimensions');
  finally
    TReleasePointer(FRuntime.Fn(IdxReleaseTypeInfo))(TypeInfo);
  end;
end;

function TOrtSession.Run(const Inputs: TArray<TOrtInt64Input>; const OutputName: string): TOrtFloatOutput;
var
  Names: TArray<UTF8String>;
  NamePtrs: TArray<PAnsiChar>;
  Values: TArray<Pointer>;
  OutName: UTF8String;
  OutNamePtr: PAnsiChar;
  OutValue: Pointer;
  ShapeInfo: Pointer;
  ElementType: Integer;
  DataPtr: Pointer;
  Count: Int64;
  I: Integer;
begin
  SetLength(Names, Length(Inputs));
  SetLength(NamePtrs, Length(Inputs));
  SetLength(Values, Length(Inputs));
  OutValue := nil;
  try
    for I := 0 to High(Inputs) do
    begin
      if ElementCount(Inputs[I].Shape) <> Length(Inputs[I].Data) then
        raise EOnnxRuntimeError.CreateFmt('Input %s: data length does not match its shape', [Inputs[I].Name]);
      if Length(Inputs[I].Data) = 0 then
        raise EOnnxRuntimeError.CreateFmt('Input %s is empty', [Inputs[I].Name]);
      Names[I] := UTF8String(Inputs[I].Name);
      NamePtrs[I] := PAnsiChar(Names[I]);
      FRuntime.Check(TCreateTensorWithData(FRuntime.Fn(IdxCreateTensorWithDataAsOrtValue))(FMemoryInfo,
        @Inputs[I].Data[0], NativeUInt(Length(Inputs[I].Data)) * SizeOf(Int64), @Inputs[I].Shape[0],
        Length(Inputs[I].Shape), OrtElementInt64, Values[I]), 'CreateTensorWithDataAsOrtValue');
    end;
    OutName := UTF8String(OutputName);
    OutNamePtr := PAnsiChar(OutName);
    FRuntime.Check(TRun(FRuntime.Fn(IdxRun))(FSession, nil, @NamePtrs[0], @Values[0], Length(Values),
      @OutNamePtr, 1, @OutValue), 'Run');

    FRuntime.Check(TGetTensorTypeAndShape(FRuntime.Fn(IdxGetTensorTypeAndShape))(OutValue, ShapeInfo),
      'GetTensorTypeAndShape');
    try
      FRuntime.Check(TGetTensorElementType(FRuntime.Fn(IdxGetTensorElementType))(ShapeInfo, ElementType),
        'GetTensorElementType');
      Result.Shape := ReadShape(FRuntime, ShapeInfo, 'GetDimensions');
    finally
      TReleasePointer(FRuntime.Fn(IdxReleaseTensorTypeAndShapeInfo))(ShapeInfo);
    end;
    if ElementType <> OrtElementFloat then
      raise EOnnxRuntimeError.CreateFmt('Output %s is not a float tensor', [OutputName]);
    Count := ElementCount(Result.Shape);
    FRuntime.Check(TGetTensorMutableData(FRuntime.Fn(IdxGetTensorMutableData))(OutValue, DataPtr),
      'GetTensorMutableData');
    SetLength(Result.Data, Count);
    if Count > 0 then
      Move(DataPtr^, Result.Data[0], Count * SizeOf(Single));
  finally
    if OutValue <> nil then
      TReleasePointer(FRuntime.Fn(IdxReleaseValue))(OutValue);
    for I := 0 to High(Values) do
      if Values[I] <> nil then
        TReleasePointer(FRuntime.Fn(IdxReleaseValue))(Values[I]);
  end;
end;

end.
