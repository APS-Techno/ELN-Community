unit dm_TreeImages;

interface

uses
  Winapi.Windows, Winapi.CommCtrl,
  System.SysUtils, System.Classes, Vcl.Forms,
  Vcl.Controls, Vcl.BaseImageCollection, Vcl.ImageCollection,
  System.ImageList, Vcl.ImgList, Vcl.VirtualImageList,
  Vcl.Graphics, Vcl.Imaging.pngimage;

type
  TIconTheme = (itLight, itDark);

  TdmTreeImages = class(TDataModule)
    ilItemsToolbar: TVirtualImageList;
    ilItems: TVirtualImageList;
    ItemsImageCollection: TImageCollection;
    ItemTypesImageCollection: TImageCollection;
    vilProjectToolBar: TVirtualImageList;
    ProjectImageCollection: TImageCollection;
    ProjectTypesImageCollection: TImageCollection;
    ProjectTreeImages: TVirtualImageList;
    MenuImageCollection: TImageCollection;
    vilMenuImages: TVirtualImageList;
    FileTypeImageCollection: TImageCollection;
    vilFileTypeImages: TVirtualImageList;
  private
    FCurrentTheme: TIconTheme;
    FThemeLoaded: Boolean;
    FResModule: HMODULE;
    procedure LoadCollection(ACollection: TImageCollection;
      const AResPrefix: string;
      const ANames: array of string;
      const ACategoryPrefix: string);
    procedure LoadResFile;
    procedure FreeResFile;
    function IsVILRenderBroken(AVIL: TVirtualImageList): Boolean;
    procedure RebuildVIL(AVIL: TVirtualImageList; ACollection: TImageCollection);
    procedure PatchBrokenVILs;
  public
    destructor Destroy; override;
    procedure LoadIcons(ATheme: TIconTheme);
    procedure ApplyThemeIcons;
    procedure ScaleForDPI(APPI: Integer);
    procedure LoadGlyph(ABitmap: TBitmap; const AResName: string; ASize: Integer);
    class function DetectIconTheme: TIconTheme; static;
    function FileIconName(const AFileName: string): string;
    property CurrentTheme: TIconTheme read FCurrentTheme;
  end;

var
  dmTreeImages: TdmTreeImages;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

uses
  System.StrUtils, unit_TreeAppearance;

const
  CItemToolbarOrder: array[0..12] of string = (
    'Add File', 'Add Folder', 'Add Image', 'Add properties',
    'Add List', 'Edit', 'Delete Document', 'Duplicate',
    'Export', 'Refresh', 'Expand All', 'Collapse All', 'New'
  );

  CItemTreeOrder: array[0..11] of string = (
    'Synthesis', 'Treatment', 'Characterization', 'Measurement',
    'Testing', 'Computing', 'Specimen', 'Model',
    'Note', 'Protocol', 'Folder', 'Wiki'
  );

  CProjectToolbarOrder: array[0..10] of string = (
    'Add File', 'Add Folder', 'Edit', 'Arrow Up',
    'Delete Document', 'Refresh', 'Show Archived',
    'Refresh', 'Show Archived', 'New', 'Analyze'
  );

  CProjectTreeOrder: array[0..1] of string = (
    'Project', 'Folder'
  );

  CMenuOrder: array[0..69] of string = (
    'Export', 'Import', 'Logout', 'Exit', 'Dashboard', 'Copy',
    'Add File', 'Add Folder', 'Edit', 'Delete Document',
    'Arrow Up', 'Down Right', 'Refresh', 'Duplicate',
    'Show Archived', 'Archive', 'Share', 'Add Image',
    'Add properties', 'Add List', 'New', 'New Procedure',
    'New Action', 'Note', 'Protocol', 'Value', 'Analyze',
    'Open File', 'Users', 'Templates', 'Equipment',
    'Value Types', 'File Types', 'Equipment Types', 'Action Types',
    'Import Data', 'Reconfigure', 'Analysis', 'Protocol Review',
    'Unit Converter', 'Settings', 'Audit Log', 'Recycle Bin',
    'Tag Editor', 'Theme', 'Quick Start', 'Manual', 'Keyboard',
    'Bug Report', 'Registration', 'About', 'Export Config',
    'Search', 'Clear', 'Eye', 'Move',
    'Regen Previews', 'Favorite', 'New Item', 'DB Maintenance',
    'Extract Values', 'Audit Rules', 'Data Completeness',
    'Link Types', 'Go To', 'Show IDs', 'Web Devices',
    'Save Draft', 'Reload Draft', 'Semantic Search'
  );

  CFileTypeOrder: array[0..31] of string = (
    'Generic', 'PDF', 'XLSX', 'CSV', 'DAT', 'ASCII', 'LOG',
    'TIFF', 'OPJU', 'XRCX', 'XRDML', 'RP4', 'DSC', 'FIBPS',
    'ZRW', 'MIT', 'LMPIN', 'DUMP',
    'DOCX', 'PPTX', 'PNG', 'BMP', 'JPG', 'TXT', 'DM3', 'DSR', 'HTML',
    'XRFX', 'VK4', 'MD', 'DEPO', 'RCPX'
  );

  CExtToIcon: array[0..38] of record Ext, Icon: string end = (
    (Ext: '.pdf';   Icon: 'PDF'),
    (Ext: '.xlsx';  Icon: 'XLSX'),
    (Ext: '.csv';   Icon: 'CSV'),
    (Ext: '.dat';   Icon: 'DAT'),
    (Ext: '.ascii'; Icon: 'ASCII'),
    (Ext: '.log';   Icon: 'LOG'),
    (Ext: '.process.log'; Icon: 'LOG'),
    (Ext: '.tiff';  Icon: 'TIFF'),
    (Ext: '.tif';   Icon: 'TIFF'),
    (Ext: '.opju';  Icon: 'OPJU'),
    (Ext: '.xrcx';  Icon: 'XRCX'),
    (Ext: '.xrdml'; Icon: 'XRDML'),
    (Ext: '.rp4';   Icon: 'RP4'),
    (Ext: '.dsc';   Icon: 'DSC'),
    (Ext: '.rcpx';  Icon: 'RCPX'),
    (Ext: '.fibps'; Icon: 'FIBPS'),
    (Ext: '.zrw';   Icon: 'ZRW'),
    (Ext: '.zrv';   Icon: 'ZRW'),
    (Ext: '.mit';   Icon: 'MIT'),
    (Ext: '.lmpin'; Icon: 'LMPIN'),
    (Ext: '.dump';  Icon: 'DUMP'),
    (Ext: '.data';  Icon: 'DUMP'),
    (Ext: '.lammps';Icon: 'DUMP'),
    (Ext: '.docx';  Icon: 'DOCX'),
    (Ext: '.pptx';  Icon: 'PPTX'),
    (Ext: '.png';   Icon: 'PNG'),
    (Ext: '.bmp';   Icon: 'BMP'),
    (Ext: '.jpg';   Icon: 'JPG'),
    (Ext: '.jpeg';  Icon: 'JPG'),
    (Ext: '.txt';   Icon: 'TXT'),
    (Ext: '.dm3';   Icon: 'DM3'),
    (Ext: '.dsr';   Icon: 'DSR'),
    (Ext: '.html';  Icon: 'HTML'),
    (Ext: '.htm';   Icon: 'HTML'),
    (Ext: '.xrfx';  Icon: 'XRFX'),
    (Ext: '.vk4';   Icon: 'VK4'),
    (Ext: '.md';    Icon: 'MD'),
    (Ext: '.tsv';   Icon: 'DEPO'),
    (Ext: '.json';  Icon: 'DEPO')
  );


const
  CIconResFile = 'Icons\ELNIcons.dll';

function SanitizeName(const AName: string): string;
begin
  Result := UpperCase(StringReplace(AName, ' ', '_', [rfReplaceAll]));
end;

function TdmTreeImages.FileIconName(const AFileName: string): string;
var
  Name: string;
  I, Best: Integer;
begin
  Result := 'Generic';
  Name := ExtractFileName(AFileName);
  Best := 0;
  for I := Low(CExtToIcon) to High(CExtToIcon) do
    if (Length(CExtToIcon[I].Ext) > Best) and EndsText(CExtToIcon[I].Ext, Name) then
    begin
      Best := Length(CExtToIcon[I].Ext);
      Result := CExtToIcon[I].Icon;
    end;
end;


destructor TdmTreeImages.Destroy;
begin
  FreeResFile;
  inherited;
end;


procedure TdmTreeImages.LoadResFile;
var
  ResPath: string;
begin
  if FResModule <> 0 then
    Exit;
  ResPath := ExtractFilePath(Application.ExeName) + CIconResFile;
  FResModule := LoadLibraryEx(PChar(ResPath), 0, LOAD_LIBRARY_AS_DATAFILE);
  if FResModule = 0 then
    raise EOSError.CreateFmt('Cannot load icon resources: %s', [ResPath]);
end;


procedure TdmTreeImages.FreeResFile;
begin
  if FResModule <> 0 then
  begin
    FreeLibrary(FResModule);
    FResModule := 0;
  end;
end;


class function TdmTreeImages.DetectIconTheme: TIconTheme;
var
  C: COLORREF;
  R, G, B: Byte;
begin
  C := GetSysColor(COLOR_BTNFACE);
  R := GetRValue(C);
  G := GetGValue(C);
  B := GetBValue(C);
  if (0.299 * R + 0.587 * G + 0.114 * B) < 128 then
    Result := itDark
  else
    Result := itLight;
end;


procedure TdmTreeImages.LoadCollection(ACollection: TImageCollection;
  const AResPrefix: string;
  const ANames: array of string;
  const ACategoryPrefix: string);
var
  I: Integer;
  RS: TResourceStream;
  Item: TImageCollectionItem;
  ResName: string;
begin
  for I := 0 to High(ANames) do
  begin
    ResName := AResPrefix + SanitizeName(ANames[I]);
    Item := ACollection.Images.Add;
    Item.Name := ACategoryPrefix + ANames[I];
    try
      RS := TResourceStream.Create(FResModule, ResName, RT_RCDATA);
      try
        Item.SourceImages.Add;
        Item.SourceImages[0].Image.LoadFromStream(RS);
      finally
        RS.Free;
      end;
    except
      on E: EResNotFound do
        ; 
    end;
  end;
end;


procedure TdmTreeImages.LoadIcons(ATheme: TIconTheme);
var
  ThemePrefix: string;
begin
  LoadResFile;

  if ATheme = itDark then
    ThemePrefix := 'DARK_'
  else
    ThemePrefix := 'LIGHT_';

  ItemsImageCollection.Images.Clear;
  LoadCollection(ItemsImageCollection,
    ThemePrefix + 'ITEM_TB_', CItemToolbarOrder, 'ToolBar\');

  ItemTypesImageCollection.Images.Clear;
  LoadCollection(ItemTypesImageCollection,
    ThemePrefix + 'ITEM_TREE_', CItemTreeOrder, '');

  ProjectImageCollection.Images.Clear;
  LoadCollection(ProjectImageCollection,
    ThemePrefix + 'PROJECT_TB_', CProjectToolbarOrder, 'Project\');

  ProjectTypesImageCollection.Images.Clear;
  LoadCollection(ProjectTypesImageCollection,
    ThemePrefix + 'PROJECT_TREE_', CProjectTreeOrder, 'Items\');

  MenuImageCollection.Images.Clear;
  LoadCollection(MenuImageCollection,
    ThemePrefix + 'MENU_', CMenuOrder, 'Menu\');

  FileTypeImageCollection.Images.Clear;
  LoadCollection(FileTypeImageCollection,
    ThemePrefix + 'FILETYPE_', CFileTypeOrder, 'FileType\');

  FCurrentTheme := ATheme;
  FThemeLoaded := True;

  PatchBrokenVILs;
end;


procedure TdmTreeImages.ApplyThemeIcons;
var
  NewTheme: TIconTheme;
begin
  NewTheme := DetectIconTheme;
  if (not FThemeLoaded) or (NewTheme <> FCurrentTheme) then
    LoadIcons(NewTheme);
end;


procedure TdmTreeImages.LoadGlyph(ABitmap: TBitmap; const AResName: string;
  ASize: Integer);
var
  ThemePrefix, ResName: string;
  RS: TResourceStream;
  Png: TPngImage;
begin
  LoadResFile;
  if FCurrentTheme = itDark then
    ThemePrefix := 'DARK_MENU_'
  else
    ThemePrefix := 'LIGHT_MENU_';
  ResName := ThemePrefix + SanitizeName(AResName);
  RS := TResourceStream.Create(FResModule, ResName, RT_RCDATA);
  try
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(RS);
      ABitmap.SetSize(ASize, ASize);
      ABitmap.PixelFormat := pf32bit;
      ABitmap.Transparent := True;
      ABitmap.Canvas.Brush.Color := clBtnFace;
      ABitmap.Canvas.FillRect(Rect(0, 0, ASize, ASize));
      ABitmap.Canvas.StretchDraw(Rect(0, 0, ASize, ASize), Png);
    finally
      Png.Free;
    end;
  finally
    RS.Free;
  end;
end;


function TdmTreeImages.IsVILRenderBroken(AVIL: TVirtualImageList): Boolean;
var
  Bmp: TBitmap;
  X, Y: Integer;
  Row: PByteArray;
begin
  Result := True;
  if (AVIL.Width = 0) or (AVIL.Height = 0) or (AVIL.Count = 0) then
    Exit;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AVIL.Width, AVIL.Height);
    Bmp.Canvas.Brush.Color := clFuchsia;
    Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
    AVIL.Draw(Bmp.Canvas, 0, 0, 0);

    for Y := 0 to Bmp.Height - 1 do
    begin
      Row := Bmp.ScanLine[Y];
      for X := 0 to Bmp.Width - 1 do
      begin
        // BGRA layout: B=Row[X*4], G=Row[X*4+1], R=Row[X*4+2]
        if not ((Row[X*4]=255) and (Row[X*4+1]=0) and (Row[X*4+2]=255)) and
           not ((Row[X*4]=255) and (Row[X*4+1]=255) and (Row[X*4+2]=255)) then
        begin
          Result := False;
          Exit;
        end;
      end;
    end;
  finally
    Bmp.Free;
  end;
end;


procedure TdmTreeImages.RebuildVIL(AVIL: TVirtualImageList;
  ACollection: TImageCollection);
var
  NewHandle: HIMAGELIST;
  I, J, X, Y: Integer;
  Bmp: TBitmap;
  CollName: string;
  SrcImg: TGraphic;
  W, H: Integer;
  Row: PByteArray;
begin
  W := AVIL.Width;
  H := AVIL.Height;
  if (W = 0) or (H = 0) or (AVIL.Count = 0) then Exit;

  NewHandle := ImageList_Create(W, H, ILC_COLOR32, AVIL.Count, 0);
  if NewHandle = 0 then Exit;
  ImageList_SetBkColor(NewHandle, CLR_NONE);

  for I := 0 to AVIL.Count - 1 do
  begin
    CollName := AVIL.Images[I].CollectionName;
    SrcImg := nil;
    for J := 0 to ACollection.Images.Count - 1 do
    begin
      if ACollection.Images[J].Name = CollName then
      begin
        if ACollection.Images[J].SourceImages.Count > 0 then
          SrcImg := ACollection.Images[J].SourceImages[0].Image;
        Break;
      end;
    end;

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(W, H);
      Bmp.Canvas.Brush.Color := clBtnFace;
      Bmp.Canvas.FillRect(Rect(0, 0, W, H));
      if (SrcImg <> nil) and (SrcImg.Width > 0) then
        Bmp.Canvas.StretchDraw(Rect(0, 0, W, H), SrcImg);
      for Y := 0 to H - 1 do
      begin
        Row := Bmp.ScanLine[Y];
        for X := 0 to W - 1 do
          Row[X * 4 + 3] := 255;
      end;
      ImageList_Add(NewHandle, Bmp.Handle, 0);
    finally
      Bmp.Free;
    end;
  end;

  AVIL.Handle := NewHandle;
end;


procedure TdmTreeImages.PatchBrokenVILs;
begin
  // Detect if TVirtualImageList's internal WIC rendering produced blank
  // HIMAGELIST entries (known issue on some Windows 11 25H2 builds).
  // If broken, rebuild from source images using GDI StretchDraw.
  if not IsVILRenderBroken(vilMenuImages) then
    Exit;

  RebuildVIL(vilMenuImages,      MenuImageCollection);
  RebuildVIL(ilItemsToolbar,     ItemsImageCollection);
  RebuildVIL(ilItems,            ItemTypesImageCollection);
  RebuildVIL(vilProjectToolBar,  ProjectImageCollection);
  RebuildVIL(ProjectTreeImages,  ProjectTypesImageCollection);
  RebuildVIL(vilFileTypeImages,  FileTypeImageCollection);
end;


procedure TdmTreeImages.ScaleForDPI(APPI: Integer);

  function S(V: Integer): Integer;
  begin
    Result := MulDiv(V, APPI, 192);
  end;

var
  TreeIcon: Integer;
begin
  // Icons are authored at 192 DPI (200%). Sizes are absolute per target DPI so
  // this is safe to call again whenever the main window moves to a monitor
  // with a different DPI; SetSize is a no-op when the size is unchanged.
  ilItemsToolbar.SetSize(S(48), S(48));
  vilProjectToolBar.SetSize(S(48), S(48));
  // Tree icons follow the tree scale (unit_TreeAppearance); even sizes
  // render crisper. Toolbar and menu icons keep their size.
  TreeIcon := (MulDiv(32 * Appearance.Scale, APPI, 192 * 100) + 1) and not 1;
  ilItems.SetSize(TreeIcon, TreeIcon);
  ProjectTreeImages.SetSize(TreeIcon, TreeIcon);
  vilMenuImages.SetSize(S(40), S(40));
  vilFileTypeImages.SetSize(S(32), S(32));

  // Resizing re-renders every image through WIC, which is broken on some
  // Windows 11 builds — re-apply the GDI fallback if that just happened.
  if FThemeLoaded then
    PatchBrokenVILs;
end;

end.
