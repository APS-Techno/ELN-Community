unit frm_CommunitySplash;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Imaging.pngimage;

type
  TfrmCommunitySplash = class(TForm)
    imgBackground: TImage;
    lblVersion: TLabel;
    lblStatus: TLabel;
  public
    class function Display: TfrmCommunitySplash; static;
    procedure SetStatus(const Text: string);
  end;

implementation

uses
  Winapi.Windows;

{$R *.dfm}

function ExecutableVersion: string;
var
  Size, Handle: DWORD;
  Buffer: TBytes;
  FixedInfo: PVSFixedFileInfo;
  InfoLen: UINT;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(Application.ExeName), Handle);
  if Size = 0 then Exit;
  SetLength(Buffer, Size);
  if not GetFileVersionInfo(PChar(Application.ExeName), Handle, Size, @Buffer[0]) then Exit;
  if VerQueryValue(@Buffer[0], '\', Pointer(FixedInfo), InfoLen) then
    Result := Format('%d.%d.%d.%d', [
      HiWord(FixedInfo.dwFileVersionMS), LoWord(FixedInfo.dwFileVersionMS),
      HiWord(FixedInfo.dwFileVersionLS), LoWord(FixedInfo.dwFileVersionLS)]);
end;

class function TfrmCommunitySplash.Display: TfrmCommunitySplash;
var
  Version: string;
begin
  Result := TfrmCommunitySplash.Create(nil);
  try
    Version := ExecutableVersion;
    if Version = '' then Version := 'unavailable';
    Result.lblVersion.Caption := 'Version ' + Version;
    Result.lblStatus.Caption := 'Starting';
    Result.Show;
    Result.Update;
  except
    Result.Free;
    raise;
  end;
end;

procedure TfrmCommunitySplash.SetStatus(const Text: string);
begin
  lblStatus.Caption := Text;
  Update;
end;

end.
