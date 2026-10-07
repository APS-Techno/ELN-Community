unit editor_FileTypes;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, EditorBase, Data.DB, Vcl.StdCtrls,
  Vcl.Buttons, RzDBNav, Vcl.Grids, Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask,
  Vcl.DBCtrls;

type
  TedFileTypes = class(TfrmEditorBase)
    DBIcon: TDBImage;
    edExtension: TDBEdit;
    edDescription: TDBEdit;
    Label1: TLabel;
    Label2: TLabel;
  private
    FIconImage: TImage;
    FUpdatingIcon: Boolean;
    procedure DataSetAfterInsert(DataSet: TDataSet);
    procedure DataSetBeforeDelete(DataSet: TDataSet);
    procedure DataSetBeforePost(DataSet: TDataSet);
    procedure DataSourceDataChange(Sender: TObject; Field: TField);
    procedure DBIconDblClick(Sender: TObject);
    procedure LoadShellIcon(const Ext: string);
    procedure SaveIconToBlob(Bmp: TBitmap);
  public
    procedure Show(DataSet: TDataSet); reintroduce;
  end;

var
  edFileTypes: TedFileTypes;

implementation

uses
  unit_DataModel, Winapi.ShellAPI,
  unit_FileType,
  unit_TimeHelper;

{$R *.dfm}

procedure TedFileTypes.Show(DataSet: TDataSet);
begin
  FIconImage := TImage.Create(Self);
  FIconImage.Parent := DBIcon.Parent;
  FIconImage.SetBounds(DBIcon.Left, DBIcon.Top, DBIcon.Width, DBIcon.Height);
  FIconImage.Stretch := True;
  FIconImage.OnDblClick := DBIconDblClick;
  FIconImage.Cursor := crHandPoint;
  FIconImage.BringToFront;
  DBIcon.Visible := False;

  DataSet.AfterInsert := DataSetAfterInsert;
  DataSet.BeforeDelete := DataSetBeforeDelete;
  DataSet.BeforePost := DataSetBeforePost;
  DataSource.OnDataChange := DataSourceDataChange;
  inherited;
  DataSet.AfterInsert := nil;
  DataSet.BeforeDelete := nil;
  DataSet.BeforePost := nil;
  DataSource.OnDataChange := nil;
end;

procedure TedFileTypes.LoadShellIcon(const Ext: string);
var
  FullExt: string;
  FileInfo: TSHFileInfo;
  Bmp: TBitmap;
begin
  FIconImage.Picture.Graphic := nil;
  FullExt := Trim(Ext);
  if FullExt = '' then Exit;
  if FullExt[1] <> '.' then
    FullExt := '.' + FullExt;
  if SHGetFileInfo(PChar('*' + FullExt), FILE_ATTRIBUTE_NORMAL,
      FileInfo, SizeOf(FileInfo),
      SHGFI_ICON or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) = 0 then
    Exit;
  Bmp := TBitmap.Create;
  try
    Bmp.Width := 32;
    Bmp.Height := 32;
    Bmp.Canvas.Brush.Color := clBtnFace;
    Bmp.Canvas.FillRect(Bmp.Canvas.ClipRect);
    DrawIconEx(Bmp.Canvas.Handle, 0, 0, FileInfo.hIcon, 32, 32, 0, 0, DI_NORMAL);
    DestroyIcon(FileInfo.hIcon);
    FIconImage.Picture.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TedFileTypes.SaveIconToBlob(Bmp: TBitmap);
var
  DS: TDataSet;
  Stream: TMemoryStream;
  DidEdit: Boolean;
begin
  DS := DataSource.DataSet;
  DidEdit := DS.State = dsBrowse;
  if DidEdit then DS.Edit;
  Stream := TMemoryStream.Create;
  try
    Bmp.SaveToStream(Stream);
    Stream.Position := 0;
    TBlobField(DS.FieldByName('Icon')).LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
  if DidEdit then
    DS.Post;
end;

procedure TedFileTypes.DataSourceDataChange(Sender: TObject; Field: TField);
var
  DS: TDataSet;
  Ext, FullExt: string;
  FileInfo: TSHFileInfo;
  Bmp: TBitmap;
begin
  if FUpdatingIcon then Exit;
  DS := DataSource.DataSet;
  if (DS = nil) or DS.IsEmpty then Exit;

  Ext := DS.FieldByName('Ext').AsString;
  LoadShellIcon(Ext);

  // Auto-populate blob when NULL
  if DS.FieldByName('Icon').IsNull then
  begin
    FullExt := Trim(Ext);
    if FullExt = '' then Exit;
    if FullExt[1] <> '.' then FullExt := '.' + FullExt;
    if SHGetFileInfo(PChar('*' + FullExt), FILE_ATTRIBUTE_NORMAL,
        FileInfo, SizeOf(FileInfo),
        SHGFI_ICON or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) = 0 then Exit;
    Bmp := TBitmap.Create;
    try
      Bmp.Width := 32;
      Bmp.Height := 32;
      Bmp.Canvas.Brush.Color := clBtnFace;
      Bmp.Canvas.FillRect(Bmp.Canvas.ClipRect);
      DrawIconEx(Bmp.Canvas.Handle, 0, 0, FileInfo.hIcon, 32, 32, 0, 0, DI_NORMAL);
      DestroyIcon(FileInfo.hIcon);
      FUpdatingIcon := True;
      try
        SaveIconToBlob(Bmp);
      finally
        FUpdatingIcon := False;
      end;
    finally
      Bmp.Free;
    end;
  end;
end;

procedure TedFileTypes.DBIconDblClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  FileInfo: TSHFileInfo;
  Bmp: TBitmap;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Select Icon File';
    Dlg.Filter := 'Icon files (*.ico)|*.ico|Executables / Libraries (*.exe;*.dll)|*.exe;*.dll|All files (*.*)|*.*';
    Dlg.Options := [ofFileMustExist];
    if not Dlg.Execute then Exit;

    if SHGetFileInfo(PChar(Dlg.FileName), 0, FileInfo, SizeOf(FileInfo),
        SHGFI_ICON or SHGFI_LARGEICON) = 0 then Exit;

    Bmp := TBitmap.Create;
    try
      Bmp.Width := 32;
      Bmp.Height := 32;
      Bmp.Canvas.Brush.Color := clBtnFace;
      Bmp.Canvas.FillRect(Bmp.Canvas.ClipRect);
      DrawIconEx(Bmp.Canvas.Handle, 0, 0, FileInfo.hIcon, 32, 32, 0, 0, DI_NORMAL);
      DestroyIcon(FileInfo.hIcon);
      FUpdatingIcon := True;
      try
        SaveIconToBlob(Bmp);
      finally
        FUpdatingIcon := False;
      end;
      FIconImage.Picture.Bitmap.Assign(Bmp);
    finally
      Bmp.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TedFileTypes.DataSetAfterInsert(DataSet: TDataSet);
begin
  DataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
end;

// Extension lookups across the app (plugin binding, tree icons,
// GetFileTypeByExt) all take the FIRST SameText match, so two rows sharing an
// extension make the resolved file type arbitrary. Reject the duplicate here
// and normalise the leading dot, which every one of those lookups assumes.
procedure TedFileTypes.DataSetBeforePost(DataSet: TDataSet);
var
  Ext: string;
  Dup: TFileType;
begin
  Ext := Trim(DataSet.FieldByName('Ext').AsString);
  if Ext = '' then
  begin
    ShowMessage('Extension is required.');
    Abort;
  end;

  if Ext[1] <> '.' then
  begin
    Ext := '.' + Ext;
    DataSet.FieldByName('Ext').AsString := Ext;
  end;

  Dup := Model.FileTypes.FindDuplicateExt(Ext,
    DataSet.FieldByName('Id').AsInteger);
  if Assigned(Dup) then
  begin
    ShowMessage(Format(
      'Extension %s is already registered as "%s" (id %d).'#13#10 +
      'Each extension may appear only once.', [Ext, Dup.Description, Dup.Id]));
    Abort;
  end;
end;

procedure TedFileTypes.DataSetBeforeDelete(DataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.FileTypes.CanDelete(DataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

end.
