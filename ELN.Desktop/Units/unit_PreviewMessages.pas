unit unit_PreviewMessages;

interface

uses
  WinApi.Windows,
  Winapi.Messages,
  System.AnsiStrings;

const
  WM_ELN_BASE = WM_APP + $0500;

  WM_ELN_IMAGECLICK = WM_ELN_BASE + 0;
  WM_ELN_IMAGEDBLCLICK = WM_ELN_BASE + 1;
  WM_ELN_FILESELECTED = WM_ELN_BASE + 2;
  // Right click on a gallery thumbnail; WParam = file id. The handler reads
  // the cursor position itself, so no coordinates travel in LParam.
  WM_ELN_IMAGECONTEXT = WM_ELN_BASE + 3;
  // The stored content of a file changed on the server (e.g. Reupload) while
  // its id stayed the same; WParam = file id. The main form drops every local
  // cached copy so the next ImageClick downloads the new content instead of
  // re-displaying the old one.
  WM_ELN_FILECHANGED = WM_ELN_BASE + 4;


procedure ImageClick(ID: integer);
procedure ImageDBLClick(ID: integer);
procedure FileSelected(ID: integer);
procedure ImageContextMenu(ID: integer);
procedure FileContentChanged(ID: integer);

implementation


uses
  Forms, SysUtils;

procedure ImageClick;
begin
  if Application.MainFormHandle = 0 then Exit;
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGECLICK,
    ID,
    0
  );
end;

procedure ImageDBLClick;
begin
  if Application.MainFormHandle = 0 then Exit;
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGEDBLCLICK,
    ID,
    0
  );
end;

procedure ImageContextMenu(ID: integer);
begin
  if Application.MainFormHandle = 0 then Exit;
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGECONTEXT,
    ID,
    0
  );
end;

procedure FileContentChanged(ID: integer);
begin
  if Application.MainFormHandle = 0 then Exit;
  // Synchronous on purpose: callers post ImageClick right after this and the
  // cache must already be gone when that message is handled.
  SendMessage(
    Application.MainFormHandle,
    WM_ELN_FILECHANGED,
    ID,
    0
  );
end;

procedure FileSelected;
begin
  if Application.MainFormHandle = 0 then Exit;
  if ID < 0 then ID := 0;
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_FILESELECTED,
    ID,
    0
  );
end;

end.
