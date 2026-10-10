{ EncodePassString is reversible obfuscation, not protection for secrets. }
unit unit_Helpers;

interface

uses
  CLasses,
  Windows,
  Vcl.Imaging.PngImage,
  VCL.Controls;

type
  TFileNames = array of string;

function CreateFolders(const Root: string; const Path: string): Boolean;
function SimpleShellExecute(
  hWnd: HWND;
  const FileName: string;
  const Parameters: string = '';
  const Operation: string = 'open';
  ShowCmd: Integer = SW_SHOWNORMAL;
  const Directory: string = ''
  ): Cardinal;

function md5(const Journal, Title: string): string;
function GetSpecialPath(CSIDL: word): string;
function CompareInt(i1, i2: Integer): Integer;
function EncodePassString(const Input: string): string;
function DecodePassString(const Input: string): string;
function RenameFolder(OldPath, NewPath: string): Boolean;


function c_GetTempPath: String;
function SimpleQuoteString(const Value: string): string;
function ClearDir(const DirectoryName: string): Boolean;

procedure SaveScreenshot(const FileName: string; Control: TWinControl);
function ComputeFileHash(const FilePath: string): string;

implementation

uses
  ShellApi,
  ActiveX,
  UrlMon,
  Graphics,
  StrUtils,
  SysUtils,
  IOUtils,
  Vcl.Forms,
  Vcl.ExtCtrls,
  ShlObj,
  IdHashMessageDigest,
  Math,
  Vcl.HtmlHelpViewer,
  Vcl.Dialogs,
  Winapi.Wincodec;

procedure CalcNewSize(Bitmap: TBitmap; var MaxWidth, MaxHeight: integer);
var
  NewWidth, NewHeight: Integer;
  AspectRatio: Extended;
begin
  AspectRatio := Bitmap.Width / Bitmap.Height;
  if Bitmap.Width > MaxWidth then
  begin
    NewWidth := MaxWidth;
    NewHeight := Trunc(NewWidth / AspectRatio);
  end
  else if Bitmap.Height > MaxHeight then
  begin
    NewHeight := MaxHeight;
    NewWidth := Trunc(NewHeight * AspectRatio);
  end
  else
  begin
    NewWidth  := Bitmap.Width;
    NewHeight := Bitmap.Height;
  end;
  if NewWidth  > 0 then MaxWidth := NewWidth;
  if NewHeight > 0 then MaxHeight := NewHeight;
end;

procedure ResizeBitmap(Bitmap: TBitmap; NewWidth, NewHeight: integer);
var
  Factory: IWICImagingFactory;
  Scaler: IWICBitmapScaler;
  Source : TWICImage;
begin
  CalcNewSize(Bitmap, NewWidth, NewHeight);
  Source := TWICImage.Create;
  try
    Factory := TWICImage.ImagingFactory;
    Source.Assign(Bitmap);
    Factory.CreateBitmapScaler(Scaler);
    Scaler.Initialize(Source.Handle, NewWidth, NewHeight,
                        WICBitmapInterpolationModeHighQualityCubic);
    Source.Handle := IWICBitmap(Scaler);
    Bitmap.Assign(Source);
    Scaler := nil;
    Factory := nil;
  finally
    Source.Free;
  end;
end;

function PrintWindow(Wnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external user32 name 'PrintWindow';

procedure SaveScreenshot(const FileName: string; Control: TWinControl);
const
  PW_RENDERFULLCONTENT = $00000002;
var
  TargetBitmap: TBitmap;
  Png: TPngImage;
begin
  TargetBitmap := TBitmap.Create;
  Png := TPngImage.Create;
  try
    TargetBitmap.SetSize(Control.Width, Control.Height);
    PrintWindow(Control.Handle, TargetBitmap.Canvas.Handle, PW_RENDERFULLCONTENT);
    ResizeBitmap(TargetBitmap, 400, 300);
    Png.Assign(TargetBitmap);
    Png.SaveToFile(FileName);
  finally
    TargetBitmap.Free;
    Png.Free;
  end;
end;

function ClearDir(const DirectoryName: string): Boolean;
var
  SearchRec: TSearchRec;
  ACurrentDir: string;
begin
  Result := True;
  ACurrentDir := IncludeTrailingPathDelimiter(DirectoryName);

  try
    if FindFirst(ACurrentDir + '*.*', faAnyFile, SearchRec) = 0 then
      try
        repeat
          if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') then
            SysUtils.DeleteFile(ACurrentDir + SearchRec.Name);
        until FindNext(SearchRec) <> 0;
      finally
        SysUtils.FindClose(SearchRec);
      end;
  except
    Result := False;
  end;
end;



function EncodePassString(const Input: string): string;
var
  i: Integer;
begin
  Result := Input;
  for i := 1 to Length(Input) do
    Result[i] := Chr(Ord(Input[i]) + 5);
end;

function DecodePassString(const Input: string): string;
var
  i: Integer;
begin
  Result := Input;
  for i := 1 to Length(Input) do
    Result[i] := Chr(Ord(Input[i]) - 5);
end;

function CompareInt(i1, i2: Integer): Integer;
begin
  Result := Sign(i1 - i2);
end;

function GetSpecialPath(CSIDL: word): string;
var
  S: string;
begin
  SetLength(S, MAX_PATH);
  if not SHGetSpecialFolderPath(0, PChar(S), CSIDL, True) then
    S := '';
  Result := IncludeTrailingPathDelimiter(PChar(S));
end;

function md5(const Journal, Title: string): string;
var
  IdHashMessageDigest5: TIdHashMessageDigest5;
begin
  try
    IdHashMessageDigest5:=TIdHashMessageDigest5.create;
    Result:=IdHashMessageDigest5.HashStringAsHex(Journal + Title);
  finally
    FreeAndNil(IdHashMessageDigest5);
  end;
end;

function ComputeFileHash(const FilePath: string): string;
var
  Stream: TFileStream;
  MD5: TIdHashMessageDigest5;
begin
  Result := '';
  try
    Stream := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
    try
      MD5 := TIdHashMessageDigest5.Create;
      try
        Result := MD5.HashStreamAsHex(Stream);
      finally
        MD5.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    Result := '';
  end;
end;

function SimpleQuoteString(const Value: string): string;
const
  QUOTECHAR = '"';
begin
  if (Value = '') then Result := Value
    else
     if (Value[1] = QUOTECHAR) then
         Result := Value
  else
    Result := QUOTECHAR + Value + QUOTECHAR;
end;


function SimpleShellExecute(
  hWnd: HWND;
  const FileName: string;
  const Parameters: string = '';
  const Operation: string = 'open';
  ShowCmd: Integer = SW_SHOWNORMAL;
  const Directory: string = ''
  ): Cardinal;
var
  AFileName: string;
  AParameters: string;
  ADirectory: string;
begin
  AFileName := SimpleQuoteString(FileName);
  AParameters := SimpleQuoteString(Parameters);
  ADirectory := Directory;

  Result := ShellAPI.ShellExecute(
    hWnd,
    PChar(Operation),
    PChar(AFileName),
    PChar(AParameters),
    PChar(Directory),
    ShowCmd
  );
end;


function CreateFolders(const Root: string; const Path: string): Boolean;
var
  FullPath: string;
begin
  if Path = '\' then
    FullPath := Root + Path
  else
    FullPath := TPath.Combine(Root, Path);

  Result := SysUtils.ForceDirectories(FullPath);
end;


function RenameFolder(OldPath, NewPath: string): Boolean;
begin
  Result := RenameFile(OldPath, NewPath);
end;

function c_GetTempPath: String;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  SetString(Result, Buffer, GetTempPath(Length(Buffer), Buffer));
end;

initialization

finalization

end.

