unit unit_PdfiumApi;

interface

uses
  System.SysUtils, System.SyncObjs;

const
  FPDF_ERR_SUCCESS = 0;
  FPDF_ERR_PASSWORD = 4;

type
  EPdfiumError = class(Exception);

  TPdfiumLibraryConfig = record
    Version: Integer;
    UserFontPaths: Pointer;
    Isolate: Pointer;
    V8EmbedderSlot: Cardinal;
    Platform_: Pointer;
  end;

  TFPDF_InitLibraryWithConfig = procedure(Config: Pointer); stdcall;
  TFPDF_DestroyLibrary = procedure; stdcall;
  TFPDF_LoadMemDocument64 = function(Data: Pointer; Size: NativeUInt; Password: PAnsiChar): Pointer; stdcall;
  TFPDF_GetLastError = function: Cardinal; stdcall;
  TFPDF_GetPageCount = function(Document: Pointer): Integer; stdcall;
  TFPDF_LoadPage = function(Document: Pointer; PageIndex: Integer): Pointer; stdcall;
  TFPDF_ClosePage = procedure(Page: Pointer); stdcall;
  TFPDF_CloseDocument = procedure(Document: Pointer); stdcall;
  TFPDFText_LoadPage = function(Page: Pointer): Pointer; stdcall;
  TFPDFText_ClosePage = procedure(TextPage: Pointer); stdcall;
  TFPDFText_CountChars = function(TextPage: Pointer): Integer; stdcall;
  TFPDFText_GetText = function(TextPage: Pointer; StartIndex, Count: Integer; Result: PWideChar): Integer; stdcall;

  TPdfiumApi = class
  private
    FModule: NativeUInt;
  public
    InitLibraryWithConfig: TFPDF_InitLibraryWithConfig;
    DestroyLibrary: TFPDF_DestroyLibrary;
    LoadMemDocument64: TFPDF_LoadMemDocument64;
    GetLastError: TFPDF_GetLastError;
    GetPageCount: TFPDF_GetPageCount;
    LoadPage: TFPDF_LoadPage;
    ClosePage: TFPDF_ClosePage;
    CloseDocument: TFPDF_CloseDocument;
    TextLoadPage: TFPDFText_LoadPage;
    TextClosePage: TFPDFText_ClosePage;
    TextCountChars: TFPDFText_CountChars;
    TextGetText: TFPDFText_GetText;
    constructor Create(const LibraryPath: string);
    destructor Destroy; override;
  end;

function PdfiumLock: TCriticalSection;

function PdfiumApiFor(const LibraryPath: string): TPdfiumApi;

// Call only when no extraction is in flight in the process.
procedure ReleasePdfiumApi;

implementation

uses
  unit_NativeLibrary;

var
  GLock: TCriticalSection;
  GApi: TPdfiumApi;

function PdfiumLock: TCriticalSection;
begin
  Result := GLock;
end;

constructor TPdfiumApi.Create(const LibraryPath: string);
var
  Config: TPdfiumLibraryConfig;

  function Bind(const Name: string): Pointer;
  begin
    Result := NativeSymbol(FModule, Name);
    if Result = nil then
      raise EPdfiumError.CreateFmt('PDFium export %s is missing', [Name]);
  end;

begin
  inherited Create;
  FModule := LoadNativeLibrary(LibraryPath);
  if FModule = 0 then
    raise EPdfiumError.CreateFmt('PDFium cannot be loaded from %s: %s', [LibraryPath, NativeLoadError]);
  try
    InitLibraryWithConfig := Bind('FPDF_InitLibraryWithConfig');
    DestroyLibrary := Bind('FPDF_DestroyLibrary');
    LoadMemDocument64 := Bind('FPDF_LoadMemDocument64');
    GetLastError := Bind('FPDF_GetLastError');
    GetPageCount := Bind('FPDF_GetPageCount');
    LoadPage := Bind('FPDF_LoadPage');
    ClosePage := Bind('FPDF_ClosePage');
    CloseDocument := Bind('FPDF_CloseDocument');
    TextLoadPage := Bind('FPDFText_LoadPage');
    TextClosePage := Bind('FPDFText_ClosePage');
    TextCountChars := Bind('FPDFText_CountChars');
    TextGetText := Bind('FPDFText_GetText');
  except
    FreeNativeLibrary(FModule);
    FModule := 0;
    raise;
  end;
  FillChar(Config, SizeOf(Config), 0);
  Config.Version := 2;
  InitLibraryWithConfig(@Config);
end;

destructor TPdfiumApi.Destroy;
begin
  if FModule <> 0 then
  begin
    DestroyLibrary;
    FreeNativeLibrary(FModule);
  end;
  inherited;
end;

function PdfiumApiFor(const LibraryPath: string): TPdfiumApi;
begin
  GLock.Enter;
  try
    if GApi = nil then
      GApi := TPdfiumApi.Create(LibraryPath);
    Result := GApi;
  finally
    GLock.Leave;
  end;
end;

procedure ReleasePdfiumApi;
begin
  GLock.Enter;
  try
    FreeAndNil(GApi);
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;

end.
