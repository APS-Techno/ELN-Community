unit unit_WikiSeeder;

{
  Seeds a freshly-created wiki item with a stub .md attachment.
  Defaults produce a README.md with the canonical project-wiki blurb;
  callers can override the Title (becomes the logical file name) and
  Content (becomes the body) to seed arbitrary Wiki pages.

  Called after Model.Templates.ApplyTemplate returns the new wiki TItem stub.
  Adds a TFile row through the model and stores UTF-8 Markdown through the
  injected notebook storage. Existing Markdown attachments are unchanged.
  Storage failure rolls back the new row and preserves the existing page.

}

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
begin
  if not Assigned(Item) then
    Exit;

  // Idempotency: already has a .md attachment? done.
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
    Exit;  // .md file type not registered - bail silently

  NewFile := Model.Items.AddFile(MdType, Title, UserId, Item);
  if not Assigned(NewFile) then
    Exit;

  try
    Model.Storage.WriteBytes(
      StringReplace(Model.GetFileName(NewFile.Id), '\', '/', [rfReplaceAll]),
      TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(Body));
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
