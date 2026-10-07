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
      TabOrder = 0
      ViewStyle = vsReport
      OnColumnClick = lvFilesColumnClick
      OnDblClick = lvFilesDblClick
      OnKeyDown = lvFilesKeyDown
      OnSelectItem = lvFilesSelectItem
    end
  end
end
