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
  // all file events carry low/high 32-bit ID halves in WParam/LParam.
  WM_ELN_IMAGECONTEXT = WM_ELN_BASE + 3;
  WM_ELN_FILECHANGED = WM_ELN_BASE + 4;


procedure EncodeFileIdMessage(ID: Int64; out LowHalf: WPARAM; out HighHalf: LPARAM);
function DecodeFileIdMessage(LowHalf: WPARAM; HighHalf: LPARAM): Int64;
procedure ImageClick(ID: Int64);
procedure ImageDBLClick(ID: Int64);
procedure FileSelected(ID: Int64);
procedure ImageContextMenu(ID: Int64);
procedure FileContentChanged(ID: Int64);

implementation


uses
  Forms, SysUtils;

procedure EncodeFileIdMessage(ID: Int64; out LowHalf: WPARAM; out HighHalf: LPARAM);
begin
  LowHalf := WPARAM(UInt64(ID) and $FFFFFFFF);
  HighHalf := LPARAM(Integer(Cardinal(UInt64(ID) shr 32)));
end;

function DecodeFileIdMessage(LowHalf: WPARAM; HighHalf: LPARAM): Int64;
begin
  Result := Int64(UInt64(Cardinal(LowHalf)) or
    (UInt64(Cardinal(HighHalf)) shl 32));
end;

procedure ImageClick;
var
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  if Application.MainFormHandle = 0 then Exit;
  EncodeFileIdMessage(ID, LowHalf, HighHalf);
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGECLICK,
    LowHalf,
    HighHalf
  );
end;

procedure ImageDBLClick;
var
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  if Application.MainFormHandle = 0 then Exit;
  EncodeFileIdMessage(ID, LowHalf, HighHalf);
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGEDBLCLICK,
    LowHalf,
    HighHalf
  );
end;

procedure ImageContextMenu(ID: Int64);
var
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  if Application.MainFormHandle = 0 then Exit;
  EncodeFileIdMessage(ID, LowHalf, HighHalf);
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_IMAGECONTEXT,
    LowHalf,
    HighHalf
  );
end;

procedure FileContentChanged(ID: Int64);
var
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  if Application.MainFormHandle = 0 then Exit;
  EncodeFileIdMessage(ID, LowHalf, HighHalf);
  // Synchronous on purpose: callers post ImageClick right after this and the
  // cache must already be gone when that message is handled.
  SendMessage(
    Application.MainFormHandle,
    WM_ELN_FILECHANGED,
    LowHalf,
    HighHalf
  );
end;

procedure FileSelected;
var
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  if Application.MainFormHandle = 0 then Exit;
  if ID < 0 then ID := 0;
  EncodeFileIdMessage(ID, LowHalf, HighHalf);
  PostMessage(
    Application.MainFormHandle,
    WM_ELN_FILESELECTED,
    LowHalf,
    HighHalf
  );
end;

end.
