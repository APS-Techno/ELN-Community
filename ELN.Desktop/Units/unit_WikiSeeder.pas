unit unit_WikiSeeder;


interface

uses
  unit_Item;

procedure WriteReadmeContent(Item: TItem; UserId: Integer;
  const Content: string = '';
  const Title: string = 'README');

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  unit_FileType,
  unit_DataModel;

const
  DefaultReadmeContent =
    '# Project Wiki'#10#10 +
    'This is the project wiki. Pages live under the five canonical sections:'#10#10 +
    '- **Goals/** - strategic objectives, milestones.'#10 +
    '- **Ideas/** - hypotheses, candidate experiments, scratch thinking.'#10 +
    '- **Literature/** - paper summaries and external references.'#10 +
    '- **Analysis/** - synthesized findings drawn from data projects.'#10 +
    '- **References/** - datasheets, protocols, external docs.'#10#10 +
    'Link to any ELN item with `[[item:N]]` and any specimen with ' +
    '`[[specimen:CODE]]`.'#10#10 +
    'Pages are plain Markdown; use the notebook editor to edit them.'#10;

procedure WriteReadmeContent(Item: TItem; UserId: Integer;
  const Content: string = '';
  const Title: string = 'README');
var
  MdType: TFileType;
  NewFile: unit_Item.TFile;
  ExistingFile: unit_Item.TFile;
  Body: string;
  Bytes: TBytes;
  Hasher: THashMD5;
begin
  if not Assigned(Item) then
    Exit;

  for ExistingFile in Item.Files do
    if Assigned(ExistingFile.FileType) and
       SameText(ExistingFile.FileType.Ext, '.md') then
      Exit;

  if Content = '' then
    Body := DefaultReadmeContent
  else
    Body := Content;

  MdType := Model.FileTypes.GetFileTypeByExt('.md');
  if not Assigned(MdType) then
    Exit;  

  NewFile := Model.Items.AddFile(MdType, Title, UserId, Item);
  if not Assigned(NewFile) then
    Exit;

  Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(Body);
  try
    Model.Storage.WriteBytes(
      StringReplace(Model.GetFileName(NewFile.Id), '\', '/', [rfReplaceAll]),
      Bytes);
    Hasher := THashMD5.Create;
    Hasher.Update(Bytes);
    NewFile.Hash := Hasher.HashAsString;
    if not Model.Items.UpdateFile(NewFile, UserId) then
      raise EInvalidOperation.Create('Could not store the Wiki attachment hash');
  except
    on E: Exception do
    begin
      if not Model.Items.RemoveFile(NewFile, Item, UserId) then
        raise EInvalidOperation.Create(E.Message +
          '; could not remove the failed Wiki attachment record');
      raise;
    end;
  end;
end;

end.
