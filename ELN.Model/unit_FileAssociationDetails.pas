unit unit_FileAssociationDetails;

{ Extensions, descriptions and icons must use the same list order. }

interface

uses Classes, VCL.Controls, SysUtils, ShellAPI, VCL.Graphics, Windows;

type
  TFileAssociationDetails = class(TObject)
  private
    FImages : TImageList;
    FExtensions : TStringList;
    FDescriptions : TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddFile(FileName : string);
    procedure AddExtension(Extension : string);
    procedure Clear;
    procedure GetFileIconsAndDescriptions;
    function GetFileIcon(const Ext: string):TIcon;
    property Images : TImageList read FImages;
    property Extensions : TStringList read FExtensions;
    property Descriptions : TStringList read FDescriptions;
  end;

implementation




constructor TFileAssociationDetails.Create;
begin
  inherited;
  FExtensions := TStringList.Create;
  FExtensions.Sorted := True;
  FDescriptions := TStringList.Create;
  FImages := TImageList.Create(nil);
end;

destructor TFileAssociationDetails.Destroy;
begin
  try
    FExtensions.Free;
    FDescriptions.Free;
    FImages.Free;
  finally
    inherited;
  end;
end;

procedure TFileAssociationDetails.AddFile(FileName: string);
begin
  AddExtension(ExtractFileExt(FileName));
end;

procedure TFileAssociationDetails.AddExtension(Extension : string);
begin
  Extension := UpperCase(Extension);
  if (Trim(Extension) <> '') and
     (FExtensions.IndexOf(Extension) = -1) then
    FExtensions.Add(Extension);
end;

procedure TFileAssociationDetails.Clear;
begin
  FExtensions.Clear;
end;

function TFileAssociationDetails.GetFileIcon(const Ext: string):TIcon;
var
  Extension : string;
  FileInfo : SHFILEINFO;
begin
  FImages.Clear;
  FDescriptions.Clear;

  Result := TIcon.Create;
  try
      Extension := '*' + Ext;

      SHGetFileInfo(PChar(Extension),
                    FILE_ATTRIBUTE_NORMAL,
                    FileInfo,
                    SizeOf(FileInfo),
                    SHGFI_TYPENAME or SHGFI_USEFILEATTRIBUTES
                    );
      FDescriptions.Add(FileInfo.szTypeName);

      SHGetFileInfo(PChar(Extension),
                    FILE_ATTRIBUTE_NORMAL,
                    FileInfo,
                    SizeOf(FileInfo),
                    SHGFI_ICON or SHGFI_SMALLICON or
                    SHGFI_SYSICONINDEX or SHGFI_USEFILEATTRIBUTES
                    );
      Result.Handle := FileInfo.hIcon;
  finally
  end;
end;

procedure TFileAssociationDetails.GetFileIconsAndDescriptions;
var
  Icon: TIcon;
  iCount : integer;
  Extension : string;
  FileInfo : SHFILEINFO;
begin
  FImages.Clear;
  FDescriptions.Clear;

  Icon := TIcon.Create;
  try
    for iCount := 0 to FExtensions.Count - 1 do
    begin
      Extension := '*' + FExtensions.Strings[iCount];

      SHGetFileInfo(PChar(Extension),
                    FILE_ATTRIBUTE_NORMAL,
                    FileInfo,
                    SizeOf(FileInfo),
                    SHGFI_TYPENAME or SHGFI_USEFILEATTRIBUTES
                    );
      FDescriptions.Add(FileInfo.szTypeName);

      SHGetFileInfo(PChar(Extension),
                    FILE_ATTRIBUTE_NORMAL,
                    FileInfo,
                    SizeOf(FileInfo),
                    SHGFI_ICON or SHGFI_SMALLICON or
                    SHGFI_SYSICONINDEX or SHGFI_USEFILEATTRIBUTES
                    );
      Icon.Handle := FileInfo.hIcon;
      FImages.AddIcon(Icon);
    end;
  finally
    Icon.Free;
  end;
end;

end.
