unit unit_ElnFileEnumerator;

// Host-side IElnFileEnumerator implementation. Returns the bare
// "[ID]name.ext" filenames attached to an item, sourced from the
// DB via Aurelius. Lets Viewer.Markdown's resolver rewrite ![](foo.png) ->
// ![](%5BID%5Dfoo.png) without depending on the temp-folder happening to
// contain the sibling images (it never does — the host downloads only the
// .md being viewed).
//
// EnsureItemFilesInDir additionally downloads any siblings missing from the
// .md's temp folder so the file:/// references the browser then resolves
// actually exist on disk.

interface

uses
  System.Classes, System.SysUtils,
  unit_ELNPluginCore;

type
  TElnFileEnumerator = class(TInterfacedObject, IElnFileEnumerator)
  public
    function GetItemFiles(ItemId: Integer): TArray<string>;
    function EnsureItemFilesInDir(ItemId: Integer;
      const TargetDir: string): TArray<string>;
  end;

procedure InstallElnFileEnumerator;
procedure UninstallElnFileEnumerator;

implementation

uses
  System.IOUtils,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_DataModel;

{ TElnFileEnumerator }

function TElnFileEnumerator.GetItemFiles(ItemId: Integer): TArray<string>;
var
  Mgr: TObjectManager;
  Item: TItem;
  F: unit_Item.TFile;
  List: TArray<string>;
  Idx: Integer;
begin
  Result := nil;
  if ItemId <= 0 then Exit;
  if not Assigned(Model) or not Assigned(Model.Manager) then Exit;

  Mgr := Model.Manager;
  Item := Mgr.Find<TItem>(ItemId);
  if not Assigned(Item) or Item.IsDeleted then Exit;

  SetLength(List, Item.Files.Count);
  Idx := 0;
  for F in Item.Files do
  begin
    List[Idx] := F.FullName;
    Inc(Idx);
  end;
  SetLength(List, Idx);
  Result := List;
end;

function TElnFileEnumerator.EnsureItemFilesInDir(ItemId: Integer;
  const TargetDir: string): TArray<string>;
var
  Mgr: TObjectManager;
  Item: TItem;
  F: unit_Item.TFile;
  List: TArray<string>;
  Idx: Integer;
  LocalPath, StoragePath: string;
begin
  Result := nil;
  if ItemId <= 0 then Exit;
  if (TargetDir = '') then Exit;
  if not Assigned(Model) or not Assigned(Model.Manager) then Exit;
  if not TDirectory.Exists(TargetDir) then
    ForceDirectories(TargetDir);

  Mgr := Model.Manager;
  Item := Mgr.Find<TItem>(ItemId);
  if not Assigned(Item) or Item.IsDeleted then Exit;

  begin
    SetLength(List, Item.Files.Count);
    Idx := 0;
    for F in Item.Files do
    begin
      List[Idx] := F.FullName;
      Inc(Idx);

      // Materialize siblings in the viewer's working directory only.
      LocalPath := TPath.Combine(TargetDir, F.FullName);
      if System.IOUtils.TFile.Exists(LocalPath) then Continue;

      StoragePath := StringReplace(Model.GetFileName(F.Id), '\', '/', [rfReplaceAll]);
      if StoragePath = '' then Continue;
      try
        Model.Storage.CopyOut(StoragePath, LocalPath);
      except
        // Best-effort: a failed sibling download just means that one image
        // renders broken, not that the whole page fails.
      end;
    end;
    SetLength(List, Idx);
    Result := List;
  end;
end;

procedure InstallElnFileEnumerator;
begin
  ElnFileEnumerator := TElnFileEnumerator.Create;
end;

procedure UninstallElnFileEnumerator;
begin
  ElnFileEnumerator := nil;
end;

end.
