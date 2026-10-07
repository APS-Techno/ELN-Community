object frameProjectTree: TframeProjectTree
  Left = 0
  Top = 0
  Width = 494
  Height = 705
  TabOrder = 0
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 488
    Height = 591
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Transparent = True
    object Tree: TVirtualStringTree
      AlignWithMargins = True
      Left = 5
      Top = 87
      Width = 478
      Height = 499
      Align = alClient
      DefaultNodeHeight = 33
      DragMode = dmAutomatic
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      Header.AutoSizeIndex = 0
      Header.Height = 21
      Header.Options = [hoColumnResize, hoDrag, hoShowSortGlyphs, hoVisible]
      Images = dmTreeImages.ProjectTreeImages
      ParentFont = False
      TabOrder = 0
      TreeOptions.SelectionOptions = [toFullRowSelect, toSelectNextNodeOnRemoval]
      OnAfterCellPaint = TreeAfterCellPaint
      OnBeforeCellPaint = TreeBeforeCellPaint
      OnClick = TreeClick
      OnCollapsed = TreeCollapsed
      OnDblClick = TreeDblClick
      OnDragAllowed = TreeDragAllowed
      OnDragOver = TreeDragOver
      OnDragDrop = TreeDragDrop
      OnExpanded = TreeExpanded
      OnFocusChanging = TreeFocusChanging
      OnFreeNode = TreeFreeNode
      OnGetCellText = TreeGetCellText
      OnPaintText = TreePaintText
      OnDrawText = TreeDrawText
      OnGetImageIndexEx = TreeGetImageIndexEx
      OnGetNodeDataSize = TreeGetNodeDataSize
      OnGetPopupMenu = TreeGetPopupMenu
      Touch.InteractiveGestures = [igPan, igPressAndTap]
      Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
      Columns = <
        item
          Options = [coAllowClick, coDraggable, coEnabled, coParentBidiMode, coParentColor, coResizable, coShowDropMark, coVisible, coAutoSpring, coSmartResize, coAllowFocus, coEditable, coStyleColor]
          Position = 0
          Text = 'Title'
          Width = 200
        end
        item
          Options = [coAllowClick, coDraggable, coEnabled, coParentBidiMode, coParentColor, coResizable, coShowDropMark, coVisible, coAutoSpring, coAllowFocus, coEditable, coStyleColor]
          Position = 1
          Text = 'Descritpion'
          Width = 200
        end
        item
          Position = 2
          Text = 'Date'
          Width = 80
        end>
    end
    object RzPanel1: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 478
      Height = 37
      Align = alTop
      BorderOuter = fsNone
      TabOrder = 1
      Transparent = True
      object RzToolbar1: TRzToolbar
        AlignWithMargins = True
        Left = 2
        Top = 2
        Width = 474
        Height = 33
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Align = alClient
        AutoStyle = False
        Images = dmTreeImages.vilProjectToolBar
        RowHeight = 30
        AutoSize = True
        BorderInner = fsNone
        BorderOuter = fsNone
        BorderSides = [sdTop]
        BorderWidth = 0
        FullRepaint = True
        TabOrder = 0
        Transparent = True
        ToolbarControls = (
          BtnNewProject
          BtnNewFolder
          BtnNewTopicWiki
          RzSpacer1
          btnEditItem
          btnLeft
          RzSpacer3
          btnDeleteItem
          RzSpacer4
          btnRefresh
          RzSpacer5
          btnShowArchived
          RzSpacer6
          btnHypotheses)
        object BtnNewFolder: TRzToolButton
          Left = 33
          Top = 5
          Hint = 'New Folder'
          ImageIndex = 1
          Caption = 'New Folder'
          ParentShowHint = False
          ShowHint = True
          OnClick = BtnNewFolderClick
        end
        object BtnNewProject: TRzToolButton
          Left = 6
          Top = 5
          Hint = 'New Project'
          ImageIndex = 9
          Caption = 'New Project'
          ParentShowHint = False
          ShowHint = True
          OnClick = BtnNewProjectClick
        end
        object BtnNewTopicWiki: TRzToolButton
          Left = 60
          Top = 5
          Hint = 'New Topic Wiki'
          ImageIndex = 9
          Caption = 'New Topic Wiki'
          ParentShowHint = False
          ShowHint = True
          OnClick = BtnNewTopicWikiClick
        end
        object RzSpacer1: TRzSpacer
          Left = 87
          Top = 5
        end
        object btnEditItem: TRzToolButton
          Left = 97
          Top = 5
          Hint = 'Edit'
          ImageIndex = 2
          Caption = 'Edit'
          ParentShowHint = False
          ShowHint = True
          OnClick = btnEditItemClick
        end
        object btnLeft: TRzToolButton
          Left = 124
          Top = 5
          Hint = 'Move Folder Up'
          ImageIndex = 3
          Caption = 'Move Folder Up'
          ParentShowHint = False
          ShowHint = True
          OnClick = btnLeftClick
        end
        object RzSpacer3: TRzSpacer
          Left = 151
          Top = 5
        end
        object btnDeleteItem: TRzToolButton
          Left = 161
          Top = 5
          Hint = 'Delete'
          ImageIndex = 4
          Caption = 'Delete'
          ParentShowHint = False
          ShowHint = True
          OnClick = btnDeleteItemClick
        end
        object RzSpacer4: TRzSpacer
          Left = 188
          Top = 5
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
        end
        object btnRefresh: TRzToolButton
          Left = 198
          Top = 5
          Hint = 'Refresh'
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
          ImageIndex = 5
          Caption = 'Refresh'
          ParentShowHint = False
          ShowHint = True
          OnClick = btnRefreshClick
        end
        object RzSpacer5: TRzSpacer
          Left = 225
          Top = 5
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
        end
        object btnShowArchived: TRzToolButton
          Left = 235
          Top = 5
          Hint = 'Show Archived'
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
          AllowAllUp = True
          GroupIndex = 1
          ImageIndex = 6
          Caption = 'Archived'
          ParentShowHint = False
          ShowHint = True
          OnClick = btnShowArchivedClick
        end
        object RzSpacer6: TRzSpacer
          Left = 262
          Top = 5
        end
        object btnHypotheses: TRzToolButton
          Left = 272
          Top = 5
          Hint = 'Hypotheses...'
          ImageIndex = 10
          Caption = 'Hypotheses'
          ParentShowHint = False
          ShowHint = True
        end
      end
    end
    object pnlSearch: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 45
      Width = 478
      Height = 36
      Margins.Top = 0
      Align = alTop
      BorderOuter = fsNone
      TabOrder = 2
      Transparent = True
      object edSearch: TRzEdit
        AlignWithMargins = True
        Left = 5
        Top = 5
        Width = 426
        Height = 26
        Margins.Left = 5
        Margins.Top = 5
        Margins.Right = 5
        Margins.Bottom = 5
        Text = ''
        Align = alClient
        TabOrder = 0
        OnChange = edSearchChange
        ExplicitHeight = 23
      end
      object btnClearSearch: TRzBitBtn
        AlignWithMargins = True
        Left = 439
        Top = 3
        Width = 36
        Height = 30
        Hint = 'Clear search'
        FrameColor = clBtnFace
        Align = alRight
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
        OnClick = btnClearSearchClick
        ImageIndex = 53
        Images = dmTreeImages.vilMenuImages
      end
    end
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 600
    Width = 488
    Height = 102
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Transparent = True
    object lblTitle: TRzLabel
      Left = 18
      Top = 8
      Width = 4
      Height = 17
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblCreated: TRzLabel
      Left = 18
      Top = 79
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lbModified: TRzLabel
      Left = 274
      Top = 76
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblDataFolder: TRzLabel
      Left = 18
      Top = 54
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblComment: TRzLabel
      Left = 18
      Top = 31
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object pmProject: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 748
    Top = 252
    object miProjectNewFolder: TMenuItem
      Caption = 'New Folder'
      ImageIndex = 7
      ImageName = 'Add Folder'
      OnClick = miProjectNewFolderClick
    end
    object miProjectSep1: TMenuItem
      Caption = '-'
    end
    object miProjectEdit: TMenuItem
      Caption = 'Edit...'
      ImageIndex = 8
      ImageName = 'Edit'
      OnClick = miProjectEditClick
    end
    object miProjectSort: TMenuItem
      Caption = 'Sort'
      object miProjectSortMoveUp: TMenuItem
        Caption = 'Move Up'
        OnClick = miSortMoveUpClick
      end
      object miProjectSortMoveDown: TMenuItem
        Caption = 'Move Down'
        OnClick = miSortMoveDownClick
      end
      object miProjectSortSep: TMenuItem
        Caption = '-'
      end
      object miProjectSortByName: TMenuItem
        Caption = 'By Name'
        OnClick = miSortByNameClick
      end
      object miProjectSortByDate: TMenuItem
        Caption = 'By Date Created'
        OnClick = miSortByDateClick
      end
    end
    object miProjectArchive: TMenuItem
      Caption = 'Archive'
      ImageIndex = 15
      ImageName = 'Archive'
      OnClick = miProjectArchiveClick
    end
    object miProjectDelete: TMenuItem
      Caption = 'Delete'
      ImageIndex = 9
      ImageName = 'Delete Document'
      OnClick = miProjectDeleteClick
    end
    object miProjectSep2: TMenuItem
      Caption = '-'
    end
    object miProjectRefresh: TMenuItem
      Caption = 'Refresh'
      ImageIndex = 12
      ImageName = 'Refresh'
      OnClick = miRefreshClick
    end
    object miProjectSep3: TMenuItem
      Caption = '-'
    end
    object miProjectShare: TMenuItem
      Caption = 'Share...'
      ImageIndex = 16
      ImageName = 'Share'
      OnClick = miProjectShareClick
    end
    object miProjectHypotheses: TMenuItem
      Caption = 'Hypotheses...'
      Hint = 'Open the project'#39's hypotheses: propose, attach runs, decide'
      ImageIndex = 26
      ImageName = 'Analyze'
      OnClick = miProjectHypothesesClick
    end
    object miProjectSep4: TMenuItem
      Caption = '-'
    end
    object miProjectCopyMCPLink: TMenuItem
      Caption = 'Copy MCP Link'
      ImageIndex = 5
      ImageName = 'Copy'
      OnClick = miProjectCopyMCPLinkClick
    end
  end
  object pmFolder: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 508
    Top = 268
    object miFolderNewFolder: TMenuItem
      Caption = 'New Folder'
      ImageIndex = 7
      ImageName = 'Add Folder'
      OnClick = miFolderNewFolderClick
    end
    object miFolderSep1: TMenuItem
      Caption = '-'
    end
    object miFolderEdit: TMenuItem
      Caption = 'Edit...'
      ImageIndex = 8
      ImageName = 'Edit'
      OnClick = miFolderEditClick
    end
    object miFolderSort: TMenuItem
      Caption = 'Sort'
      object miFolderSortMoveUp: TMenuItem
        Caption = 'Move Up'
        OnClick = miSortMoveUpClick
      end
      object miFolderSortMoveDown: TMenuItem
        Caption = 'Move Down'
        OnClick = miSortMoveDownClick
      end
      object miFolderSortSep: TMenuItem
        Caption = '-'
      end
      object miFolderSortByName: TMenuItem
        Caption = 'By Name'
        OnClick = miSortByNameClick
      end
      object miFolderSortByDate: TMenuItem
        Caption = 'By Date Created'
        OnClick = miSortByDateClick
      end
    end
    object miFolderMoveUp: TMenuItem
      Caption = 'Move to Parent Level'
      ImageIndex = 10
      ImageName = 'Arrow Up'
      OnClick = miFolderMoveUpClick
    end
    object miFolderDelete: TMenuItem
      Caption = 'Delete'
      ImageIndex = 9
      ImageName = 'Delete Document'
      OnClick = miFolderDeleteClick
    end
    object miFolderSep2: TMenuItem
      Caption = '-'
    end
    object miFolderRefresh: TMenuItem
      Caption = 'Refresh'
      ImageIndex = 12
      ImageName = 'Refresh'
      OnClick = miRefreshClick
    end
    object miFolderSep3: TMenuItem
      Caption = '-'
    end
    object miFolderCopyMCPLink: TMenuItem
      Caption = 'Copy MCP Link'
      ImageIndex = 5
      ImageName = 'Copy'
      OnClick = miFolderCopyMCPLinkClick
    end
  end
  object pmRoot: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 508
    Top = 332
    object miRootNewGroup: TMenuItem
      Caption = 'New Group...'
      ImageIndex = 19
      ImageName = 'Add List'
      OnClick = miRootNewGroupClick
    end
    object miSortUsers: TMenuItem
      Caption = 'Sort Users By'
      object miSortUsersManual: TMenuItem
        Caption = 'Manual (drag && drop)'
        RadioItem = True
        OnClick = miSortUsersModeClick
      end
      object miSortUsersById: TMenuItem
        Tag = 1
        Caption = 'ID'
        RadioItem = True
        OnClick = miSortUsersModeClick
      end
      object miSortUsersByName: TMenuItem
        Tag = 2
        Caption = 'Name'
        RadioItem = True
        OnClick = miSortUsersModeClick
      end
    end
  end
  object pmGroup: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 508
    Top = 396
    object miGroupNewProject: TMenuItem
      Caption = 'New Project...'
      ImageIndex = 20
      ImageName = 'New'
      OnClick = miGroupNewProjectClick
    end
    object miGroupSep1: TMenuItem
      Caption = '-'
    end
    object miGroupRename: TMenuItem
      Caption = 'Rename...'
      ImageIndex = 8
      ImageName = 'Edit'
      OnClick = miGroupRenameClick
    end
    object miGroupDelete: TMenuItem
      Caption = 'Delete Group'
      ImageIndex = 9
      ImageName = 'Delete Document'
      OnClick = miGroupDeleteClick
    end
  end
end
