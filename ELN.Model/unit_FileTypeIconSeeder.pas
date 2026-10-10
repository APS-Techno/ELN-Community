unit unit_FileTypeIconSeeder;


interface

uses
  unit_FileTypeModel;

type
  TFileTypeIconSeeder = class
  public
    class procedure SeedIcons(Model: TFileTypeModel); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  VCL.Graphics,
  unit_FileType,
  unit_FileAssociationDetails;


class procedure TFileTypeIconSeeder.SeedIcons(Model: TFileTypeModel);
var
  Icons: TFileAssociationDetails;
  Stream: TMemoryStream;
  FileType: TFileType;
  FileTypes: TFileTypes;
  Picture: TPicture;
begin
  Icons := TFileAssociationDetails.Create;
  Picture := TPicture.Create;
  Stream := TMemoryStream.Create;
  try
    FileTypes := Model.GetFileTypes;
    for FileType in FileTypes do
    begin
      Picture.Icon := Icons.GetFileIcon(FileType.Ext);
      Picture.SaveToStream(Stream);
      Stream.Seek(0, soFromBeginning);
      FileType.Icon.LoadFromStream(Stream);
      Stream.Clear;
    end;
    Model.Manager.Flush;
  finally
    FreeAndNil(Icons);
    FreeAndNil(Stream);
    FreeAndNil(Picture);
  end;
end;

end.
