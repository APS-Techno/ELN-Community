object frameItemTree: TframeItemTree
  Left = 0
  Top = 0
  Width = 640
  Height = 480
  TabOrder = 0
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 375
    Width = 634
    Height = 102
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Transparent = True
    DesignSize = (
      634
      102)
    object lblName: TRzLabel
      AlignWithMargins = True
      Left = 12
      Top = 5
      Width = 617
      Height = 21
      Margins.Left = 10
      Align = alTop
      Caption = 'Name'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Transparent = True
      ExplicitWidth = 46
    end
    object lblDetails: TRzLabel
      AlignWithMargins = True
      Left = 12
      Top = 32
      Width = 617
      Height = 17
      Margins.Left = 10
      Align = alTop
      Caption = 'Description'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
      ExplicitWidth = 66
    end
    object pnlLinks: TRzPanel
      AlignWithMargins = True
      Left = 12
      Top = 55
      Width = 617
      Height = 44
      Margins.Left = 10
      Align = alTop
      BorderOuter = fsFlatRounded
      TabOrder = 0
      Transparent = True
      Visible = False
      object pnlLinksHeader: TRzPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 611
        Height = 20
        Align = alTop
        BorderOuter = fsNone
        TabOrder = 0
        Transparent = True
        object lblLinksCaption: TRzLabel
          Left = 2
          Top = 2
          Width = 34
          Height = 15
          Caption = 'Links'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Segoe UI'
          Font.Style = [fsBold]
          ParentFont = False
          Transparent = True
        end
        object btnManageLinks: TButton
          AlignWithMargins = True
          Left = 529
          Top = 0
          Width = 82
          Height = 20
          Align = alRight
          Margins.Left = 3
          Margins.Top = 0
          Margins.Right = 0
          Margins.Bottom = 0
          Caption = 'Manage...'
          TabOrder = 0
          OnClick = btnManageLinksClick
        end
      end
      object vstLinks: TVirtualStringTree
        AlignWithMargins = True
        Left = 3
        Top = 26
        Width = 611
        Height = 15
        Align = alClient
        BorderStyle = bsNone
        DefaultNodeHeight = 19
        Header.AutoSizeIndex = -1
        Header.Options = [hoColumnResize]
        HintMode = hmHint
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
        TreeOptions.PaintOptions = [toHideFocusRect, toThemeAware, toUseBlendedImages, toUseBlendedSelection]
        TreeOptions.SelectionOptions = [toFullRowSelect]
        OnGetText = vstLinksGetText
        OnGetHint = vstLinksGetHint
        OnGetNodeDataSize = vstLinksGetNodeDataSize
        OnNodeClick = vstLinksNodeClick
        Columns = <
          item
            Position = 0
            Width = 160
          end
          item
            Position = 1
            Width = 440
          end>
      end
    end
    object shpTypeBar: TShape
      Left = 0
      Top = 0
      Width = 5
      Height = 102
      Anchors = [akLeft, akTop, akBottom]
      Pen.Style = psClear
    end
  end
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 68
    Width = 634
    Height = 301
    Margins.Top = 5
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Transparent = True
    object RzPanel1: TRzPanel
      Left = 2
      Top = 2
      Width = 630
      Height = 297
      Margins.Top = 6
      Align = alClient
      AutoSize = True
      BorderOuter = fsFlatRounded
      TabOrder = 0
      Transparent = True
      object pnlSearch: TRzPanel
        AlignWithMargins = True
        Left = 5
        Top = 45
        Width = 620
        Height = 36
        Margins.Top = 0
        Align = alTop
        BorderOuter = fsNone
        TabOrder = 1
        Transparent = True
        object btnClearSearch: TRzBitBtn
          AlignWithMargins = True
          Left = 581
          Top = 3
          Width = 36
          Height = 30
          Hint = 'Clear search'
          Align = alRight
          ParentShowHint = False
          ShowHint = True
          TabOrder = 0
          OnClick = btnClearSearchClick
          ImageIndex = 53
          Images = dmTreeImages.vilMenuImages
        end
        object edSearch: TRzEdit
          AlignWithMargins = True
          Left = 5
          Top = 5
          Width = 568
          Height = 26
          Margins.Left = 5
          Margins.Top = 5
          Margins.Right = 5
          Margins.Bottom = 5
          Text = ''
          Align = alClient
          TabOrder = 1
          OnChange = edSearchChange
          ExplicitHeight = 23
        end
      end
      object Tree: TVirtualStringTree
        AlignWithMargins = True
        Left = 5
        Top = 87
        Width = 620
        Height = 205
        Align = alClient
        DefaultNodeHeight = 33
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        Header.AutoSizeIndex = 0
        Header.Options = [hoColumnResize, hoDrag, hoShowSortGlyphs, hoVisible]
        Images = dmTreeImages.ilItems
        ParentFont = False
        ParentShowHint = False
        ShowHint = True
        TabOrder = 0
        TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toThemeAware, toUseBlendedImages, toFullVertGridLines]
        TreeOptions.SelectionOptions = [toFullRowSelect, toSelectNextNodeOnRemoval]
        OnAfterCellPaint = TreeAfterCellPaint
        OnBeforeCellPaint = TreeBeforeCellPaint
        OnClick = TreeClick
        OnDblClick = TreeDblClick
        OnDragAllowed = TreeDragAllowed
        OnGetCellText = TreeGetCellText
        OnGetImageIndexEx = TreeGetImageIndexEx
        OnGetNodeDataSize = TreeGetNodeDataSize
        OnGetPopupMenu = TreeGetPopupMenu
        OnKeyDown = TreeKeyDown
        OnPaintText = TreePaintText
        Touch.InteractiveGestures = [igPan, igPressAndTap]
        Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
        Columns = <
          item
            Options = [coAllowClick, coDraggable, coEnabled, coParentBidiMode, coParentColor, coResizable, coShowDropMark, coVisible, coAutoSpring, coSmartResize, coAllowFocus, coEditable, coStyleColor]
            Position = 0
            Text = 'Title'
            Width = 338
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
          end
          item
            Alignment = taRightJustify
            Options = [coAllowClick, coDraggable, coEnabled, coParentBidiMode, coParentColor, coResizable, coShowDropMark, coAllowFocus, coStyleColor]
            Position = 3
            Text = 'ID'
            Width = 60
          end>
      end
      object RzPanel2: TRzPanel
        AlignWithMargins = True
        Left = 5
        Top = 5
        Width = 620
        Height = 37
        Align = alTop
        BorderOuter = fsNone
        TabOrder = 2
        Transparent = True
        object RzToolbar1: TRzToolbar
          AlignWithMargins = True
          Left = 2
          Top = 2
          Width = 616
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
          Align = alClient
          AutoStyle = False
          Images = dmTreeImages.ilItemsToolbar
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
            BtnNew
            BtnNewFolder
            BtnAddFile
            BtnAddNote
            btnAddProtocol
            BtnAddValue
            RzSpacer2
            BtnEdit
            BtnDuplicate
            RzSpacer3
            BtnDelete
            RzSpacer4
            BtnExport
            RzSpacer5
            btnRefresh
            RzSpacer6
            btnExpandCollapse)
          object BtnNewFolder: TRzToolButton
            Left = 47
            Top = 5
            Hint = 'New Folder'
            ImageIndex = 1
            Caption = 'New Folder'
            ParentShowHint = False
            ShowHint = True
            Visible = False
            OnClick = BtnNewFolderClick
          end
          object BtnNew: TRzToolButton
            Left = 6
            Top = 5
            Width = 39
            Hint = 'New'
            DropDownMenu = pmNew
            ImageIndex = 12
            ToolStyle = tsDropDown
            Caption = 'New'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnNewClick
          end
          object BtnAddFile: TRzToolButton
            Left = 74
            Top = 5
            Hint = 'Add File'
            ImageIndex = 2
            Caption = 'Add File'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnAddFileClick
          end
          object BtnAddNote: TRzToolButton
            Left = 101
            Top = 5
            Hint = 'Add Note'
            ImageIndex = 3
            Caption = 'Add Note'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnAddNoteClick
          end
          object RzSpacer2: TRzSpacer
            Left = 182
            Top = 5
          end
          object BtnEdit: TRzToolButton
            Left = 192
            Top = 5
            Hint = 'Edit'
            ImageIndex = 5
            Caption = 'Edit'
            ParentShowHint = False
            ShowHint = True
          end
          object BtnDuplicate: TRzToolButton
            Left = 219
            Top = 5
            Hint = 'Duplicate'
            ImageIndex = 7
            Caption = 'Duplicate'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnDuplicateClick
          end
          object RzSpacer3: TRzSpacer
            Left = 246
            Top = 5
          end
          object BtnDelete: TRzToolButton
            Left = 256
            Top = 5
            Hint = 'Delete'
            ImageIndex = 6
            Caption = 'Delete'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnDeleteClick
          end
          object btnAddProtocol: TRzToolButton
            Left = 128
            Top = 5
            Hint = 'Add Protocol'
            ImageIndex = 4
            Caption = 'Add Protocol'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnAddProtocolClick
          end
          object BtnAddValue: TRzToolButton
            Left = 155
            Top = 5
            Hint = 'Add Value'
            ImageIndex = 4
            Caption = 'Value'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnAddValueClick
          end
          object RzSpacer4: TRzSpacer
            Left = 283
            Top = 5
          end
          object BtnExport: TRzToolButton
            Left = 293
            Top = 5
            Hint = 'Export Package'
            ImageIndex = 8
            Caption = 'Export'
            ParentShowHint = False
            ShowHint = True
            OnClick = BtnExportClick
          end
          object RzSpacer5: TRzSpacer
            Left = 320
            Top = 5
            Margins.Left = 2
            Margins.Top = 2
            Margins.Right = 2
            Margins.Bottom = 2
          end
          object btnRefresh: TRzToolButton
            Left = 330
            Top = 5
            Hint = 'Refresh'
            Margins.Left = 2
            Margins.Top = 2
            Margins.Right = 2
            Margins.Bottom = 2
            ImageIndex = 9
            Caption = 'Refresh'
            ParentShowHint = False
            ShowHint = True
            OnClick = btnRefreshClick
          end
          object RzSpacer6: TRzSpacer
            Left = 357
            Top = 5
          end
          object btnExpandCollapse: TRzToolButton
            Left = 367
            Top = 5
            Hint = 'Expand All'
            ImageIndex = 10
            Caption = 'Expand All'
            ParentShowHint = False
            ShowHint = True
            OnClick = btnExpandCollapseClick
          end
        end
      end
    end
  end
  object pnlTitle: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 6
    Width = 634
    Height = 54
    Margins.Top = 6
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 2
    Transparent = True
    object lblPath: TRzLabel
      Left = 13
      Top = 14
      Width = 35
      Height = 21
      Caption = 'Path'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object pmNew: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 134
    Top = 380
    object miNewProc: TMenuItem
      Caption = 'New Procedure'
      ImageIndex = 21
      OnClick = miNewProcClick
    end
    object miNewItem: TMenuItem
      Caption = 'New Item'
      ImageIndex = 58
      OnClick = miNewItemClick
    end
    object miNewAction: TMenuItem
      Caption = 'New Action'
      ImageIndex = 22
      OnClick = miNewActionClick
    end
  end
  object pmItem: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 230
    Top = 380
    object miItemNew: TMenuItem
      Caption = 'New...'
      ImageIndex = 20
      OnClick = miItemNewClick
    end
    object miItemNewFolder: TMenuItem
      Caption = 'New Folder'
      ImageIndex = 7
      OnClick = miItemNewFolderClick
    end
    object miItemAdd: TMenuItem
      Caption = 'Add'
      ImageIndex = 6
      object miItemAddFile: TMenuItem
        Caption = 'File...'
        ImageIndex = 6
        OnClick = miItemAddFileClick
      end
      object miItemAddNote: TMenuItem
        Caption = 'Note...'
        ImageIndex = 23
        OnClick = miItemAddNoteClick
      end
      object miItemAddProtocol: TMenuItem
        Caption = 'Protocol...'
        ImageIndex = 24
        OnClick = miItemAddProtocolClick
      end
      object miItemAddValue: TMenuItem
        Caption = 'Value...'
        ImageIndex = 25
        OnClick = miItemAddValueClick
      end
      object miItemAnalyze: TMenuItem
        Caption = 'Analyze...'
        ImageIndex = 26
        OnClick = miItemAnalyzeClick
      end
    end
    object miItemSep1: TMenuItem
      Caption = '-'
    end
    object miItemEdit: TMenuItem
      Caption = 'Edit...'
      ImageIndex = 8
      OnClick = miItemEditClick
    end
    object miItemDuplicate: TMenuItem
      Caption = 'Duplicate'
      ImageIndex = 13
      OnClick = miItemDuplicateClick
    end
    object miItemMoveTo: TMenuItem
      Caption = 'Move to...'
      ImageIndex = 55
      OnClick = miItemMoveToClick
    end
    object miItemSort: TMenuItem
      Caption = 'Sort'
      object miItemSortMoveUp: TMenuItem
        Caption = 'Move Up'
        ShortCut = 16422
        OnClick = miItemSortMoveUpClick
      end
      object miItemSortMoveDown: TMenuItem
        Caption = 'Move Down'
        ShortCut = 16424
        OnClick = miItemSortMoveDownClick
      end
      object miItemSortSep: TMenuItem
        Caption = '-'
      end
      object miItemSortByName: TMenuItem
        Caption = 'By Name'
        OnClick = miItemSortByNameClick
      end
      object miItemSortByDate: TMenuItem
        Caption = 'By Date Created'
        OnClick = miItemSortByDateClick
      end
    end
    object miItemSep2: TMenuItem
      Caption = '-'
    end
    object miItemSep3: TMenuItem
      Caption = '-'
    end
    object miItemHypothesis: TMenuItem
      Caption = 'Hypothesis'
      object miItemAttachHypothesis: TMenuItem
        Caption = 'Attach to hypothesis...'
        OnClick = miItemAttachHypothesisClick
      end
      object miItemNewHypothesis: TMenuItem
        Caption = 'New hypothesis from this item...'
        OnClick = miItemNewHypothesisClick
      end
    end
    object miItemSep4: TMenuItem
      Caption = '-'
    end
    object miItemDelete: TMenuItem
      Caption = 'Delete'
      ImageIndex = 9
      OnClick = miItemDeleteClick
    end
    object miItemSep5: TMenuItem
      Caption = '-'
    end
    object miItemRegenPreviews: TMenuItem
      Caption = 'Regenerate Previews'
      ImageIndex = 56
      OnClick = miItemRegenPreviewsClick
    end
    object miItemCheckValueSources: TMenuItem
      Caption = 'Check Value Sources...'
      OnClick = miItemCheckValueSourcesClick
    end
    object miItemRefresh: TMenuItem
      Caption = 'Refresh'
      ImageIndex = 12
      OnClick = miItemRefreshClick
    end
    object miItemCopyMCPLink: TMenuItem
      Caption = 'Copy MCP Link'
      ImageIndex = 5
      OnClick = miItemCopyMCPLinkClick
    end
  end
  object pmProtocol: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 326
    Top = 380
    object miProtocolEdit: TMenuItem
      Caption = 'Edit...'
      ImageIndex = 8
      OnClick = miProtocolEditClick
    end
    object miProtocolSep1: TMenuItem
      Caption = '-'
    end
    object miProtocolDelete: TMenuItem
      Caption = 'Delete'
      ImageIndex = 9
      OnClick = miProtocolDeleteClick
    end
    object miProtocolSep2: TMenuItem
      Caption = '-'
    end
    object miProtocolRefresh: TMenuItem
      Caption = 'Refresh'
      ImageIndex = 12
      OnClick = miProtocolRefreshClick
    end
    object miProtocolSep3: TMenuItem
      Caption = '-'
    end
    object miProtocolCopyMCPLink: TMenuItem
      Caption = 'Copy MCP Link'
      ImageIndex = 5
      OnClick = miProtocolCopyMCPLinkClick
    end
  end
  object pmFile: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 422
    Top = 380
    object miFileOpen: TMenuItem
      Caption = 'Open'
      ImageIndex = 27
      OnClick = miFileOpenClick
    end
    object miFileExport: TMenuItem
      Caption = 'Export...'
      ImageIndex = 0
      OnClick = miFileExportClick
    end
    object miFileReupload: TMenuItem
      Caption = 'Reupload...'
      ImageIndex = 1
      OnClick = miFileReuploadClick
    end
    object miFileMoveTo: TMenuItem
      Caption = 'Move to...'
      ImageIndex = 55
      OnClick = miFileMoveToClick
    end
    object miFileEdit: TMenuItem
      Caption = 'Edit'
      ImageIndex = 8
      OnClick = miFileEditClick
    end
    object miFileExtractValues: TMenuItem
      Caption = 'Extract Values...'
      ImageIndex = 60
      OnClick = miFileExtractValuesClick
    end
    object miFileSep1: TMenuItem
      Caption = '-'
    end
    object miFileDelete: TMenuItem
      Caption = 'Delete'
      ImageIndex = 9
      OnClick = miFileDeleteClick
    end
    object miFileSep2: TMenuItem
      Caption = '-'
    end
    object miFileCopyPath: TMenuItem
      Caption = 'Copy Path'
      ImageIndex = 5
      OnClick = miFileCopyPathClick
    end
    object miFileSep3: TMenuItem
      Caption = '-'
    end
    object miFileRegenPreview: TMenuItem
      Caption = 'Regenerate Preview'
      ImageIndex = 56
      OnClick = miFileRegenPreviewClick
    end
    object miFileRefresh: TMenuItem
      Caption = 'Refresh'
      ImageIndex = 12
      OnClick = miFileRefreshClick
    end
    object miFileSep4: TMenuItem
      Caption = '-'
    end
    object miFileCopyMCPLink: TMenuItem
      Caption = 'Copy MCP Link'
      ImageIndex = 5
      OnClick = miFileCopyMCPLinkClick
    end
  end
  object tmrStartup: TTimer
    Enabled = False
    Interval = 1000
    OnTimer = tmrStartupTimer
    Left = 560
    Top = 400
  end
end
