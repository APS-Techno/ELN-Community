object frameFileSystemBrowser: TframeFileSystemBrowser
  Left = 0
  Top = 0
  Width = 900
  Height = 430
  TabOrder = 0
  object pnlNavigation: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 894
    Height = 36
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object btnBack: TRzButton
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 58
      Height = 30
      Align = alLeft
      Caption = 'Back'
      TabOrder = 0
      OnClick = btnBackClick
    end
    object btnForward: TRzButton
      AlignWithMargins = True
      Left = 67
      Top = 3
      Width = 65
      Height = 30
      Align = alLeft
      Caption = 'Forward'
      TabOrder = 1
      OnClick = btnForwardClick
    end
    object btnUp: TRzButton
      AlignWithMargins = True
      Left = 138
      Top = 3
      Width = 42
      Height = 30
      Align = alLeft
      Caption = 'Up'
      TabOrder = 2
      OnClick = btnUpClick
    end
    object btnRefresh: TRzButton
      AlignWithMargins = True
      Left = 815
      Top = 3
      Width = 76
      Height = 30
      Align = alRight
      Caption = 'Refresh'
      TabOrder = 4
      OnClick = btnRefreshClick
    end
    object edPath: TRzEdit
      AlignWithMargins = True
      Left = 186
      Top = 3
      Width = 623
      Height = 30
      Align = alClient
      Text = ''
      TabOrder = 3
      OnKeyDown = edPathKeyDown
    end
  end
  object lblStatus: TRzLabel
    AlignWithMargins = True
    Left = 3
    Top = 412
    Width = 894
    Height = 15
    Align = alBottom
    AutoSize = False
    Caption = 'Choose a folder'
    ShowHint = True
    EllipsisPosition = epPathEllipsis
  end
  object splFolders: TRzSplitter
    AlignWithMargins = True
    Left = 3
    Top = 45
    Width = 894
    Height = 361
    Align = alClient
    BorderOuter = fsFlatRounded
    MarginMin = 120
    MarginMax = 120
    Position = 205
    RealTimeDrag = True
    SplitterWidth = 5
    UpperLeft.BorderOuter = fsFlatRounded
    LowerRight.BorderOuter = fsFlatRounded
    TabOrder = 1
    UpperLeftControls = (
      tvFolders)
    LowerRightControls = (
      lvFiles)
    object tvFolders: TRzTreeView
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 199
      Height = 355
      Align = alClient
      Indent = 19
      ReadOnly = True
      HideSelection = False
      TabOrder = 0
      OnChange = tvFoldersChange
      OnDeletion = tvFoldersDeletion
      OnExpanding = tvFoldersExpanding
    end
    object lvFiles: TRzListView
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 678
      Height = 355
      Align = alClient
      Columns = <
        item
          Caption = 'Name'
          Width = 285
        end
        item
          Caption = 'Type'
          Width = 100
        end
        item
          Caption = 'Size'
          Width = 100
        end
        item
          Caption = 'Modified'
          Width = 155
        end>
      FillLastColumn = False
      HideSelection = False
      MultiSelect = True
      ReadOnly = True
      RowSelect = True
      SmallImages = BrowserIcons
      TabOrder = 0
      ViewStyle = vsReport
      OnColumnClick = lvFilesColumnClick
      OnDblClick = lvFilesDblClick
      OnKeyDown = lvFilesKeyDown
      OnSelectItem = lvFilesSelectItem
    end
  end
  object BrowserImages: TImageCollection
    Images = <
      item
        Name = 'Folder'
        SourceImages = <
          item
            Image.Data = {
              89504E470D0A1A0A0000000D4948445200000018000000180806000000E0773DF8
              0000005C49444154789C63601805A38052C008220E4D51FF4F8C62BB9C9B60F5A4
              002652141F22D221387D80CF8587900C27C527445B40AE0F480A223B32E2808554
              0D76445A02F32D493E20078C5A40108C0611750BBB411907A38081100000D0F71D
              15CB2204900000000049454E44AE426082}
          end>
      end
      item
        Name = 'Document'
        SourceImages = <
          item
            Image.Data = {
              89504E470D0A1A0A0000000D4948445200000018000000180806000000E0773DF80000007849444154789CED95510A80300C43ABECD039426FAD2008A26D9CB6FD18EC7D0E96AC4DCB444667B91FA8EAF65504C043E7649504943CCAAD80BDCA13B6EE842BC045D4AA24A54520262906CCA449107D99BA90018C50CB5AE431BE41CB08126429BB0CD0B1D51E338383994108774CFF7C9D62503EA6E5EC27222ECEB1F6ACC00000000049454E44AE426082}
          end>
      end>
    OnGetBitmap = BrowserImagesGetBitmap
    Left = 440
    Top = 280
  end
  object BrowserIcons: TVirtualImageList
    Images = <
      item
        CollectionIndex = 0
        CollectionName = 'Folder'
        Name = 'Folder'
      end
      item
        CollectionIndex = 1
        CollectionName = 'Document'
        Name = 'Document'
      end>
    ImageCollection = BrowserImages
    Width = 20
    Height = 20
    Left = 520
    Top = 280
  end
end
