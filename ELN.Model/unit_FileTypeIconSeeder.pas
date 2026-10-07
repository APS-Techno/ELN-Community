unit unit_FileTypeIconSeeder;

{
  Windows-only helper that scrapes shell icons via SHGetFileInfo and writes
  them into TFileType.Icon blobs. Lives in ELN.Model.Win because of its
  VCL.Graphics / VCL.Controls dependencies. The web API (Linux) does not
  need icons, so it does not reference this unit.

  Extracted from TFileTypeModel.GetIcons during the Option C surgery that
  broke ELN.Model's VCL dependency.
}

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

{ TFileTypeIconSeeder }

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
    // Identical semantics to the original GetIcons which called FManager.Flush.
    // Model.Manager exposes the same TObjectManager instance.
    Model.Manager.Flush;
  finally
    FreeAndNil(Icons);
    FreeAndNil(Stream);
    FreeAndNil(Picture);
  end;
end;

end.
