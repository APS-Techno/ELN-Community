unit unit_Common;

interface

uses

  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  WinApi.CommCtrl, ToolWin, Buttons, ExtCtrls, StdCtrls, ImgList, ActnList,
  StdActns, VirtualTrees, unit_ProjectAccessPolicy;

  type

    TLocation = record
       ProjectID, FolderID: integer;
       Path: string;
       Access: TProjectAccess;
    end;

  procedure ConvertToHighColor(ImageList: TImageList);

implementation

procedure ConvertToHighColor(ImageList: TImageList);
var
  IL: TImageList;
begin
  // Have to create a temporary copy of the given list, because the list is cleared on handle creation.
  IL := TImageList.Create(nil);
  IL.Assign(ImageList);

  with ImageList do
    Handle := ImageList_Create(Width, Height, ILC_COLOR16 or ILC_MASK, Count, AllocBy);
  ImageList.Assign(IL);
  IL.Free;
end;

end.
