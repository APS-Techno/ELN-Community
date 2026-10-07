object dlgExperimentTemplate: TdlgExperimentTemplate
  Left = 0
  Top = 0
  Caption = 'Experiment Templates'
  ClientHeight = 600
  ClientWidth = 960
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object spltMain: TSplitter
    Left = 260
    Top = 0
    Height = 548
    MinSize = 15
  end
  object spltRight: TSplitter
    Left = 543
    Top = 0
    Height = 548
    MinSize = 15
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 548
    Width = 960
    Height = 52
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object btnCreate: TRzButton
      Left = 713
      Top = 14
      Width = 134
      Default = True
      ModalResult = 1
      Caption = 'Create from Template'
      TabOrder = 0
      OnClick = btnCreateClick
    end
    object btnClose: TRzButton
      Left = 866
      Top = 14
      Width = 70
      Cancel = True
      ModalResult = 2
      Caption = 'Close'
      TabOrder = 1
    end
  end
  object pnlLeft: TRzPanel
    Left = 0
    Top = 0
    Width = 260
    Height = 548
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object lblTemplateList: TRzLabel
      Left = 2
      Top = 2
      Width = 256
      Height = 13
      Align = alTop
      Caption = '  Templates'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
      Transparent = True
      ExplicitWidth = 66
    end
    object pnlListButtons: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 478
      Width = 250
      Height = 65
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 0
      object btnAdd: TRzButton
        Left = 5
        Top = 5
        Width = 55
        Caption = 'Add'
        TabOrder = 0
        OnClick = btnAddClick
      end
      object btnDelete: TRzButton
        Left = 64
        Top = 5
        Width = 55
        Caption = 'Delete'
        TabOrder = 1
        OnClick = btnDeleteClick
      end
      object btnDuplicate: TRzButton
        Left = 123
        Top = 5
        Width = 65
        Caption = 'Duplicate'
        TabOrder = 2
        OnClick = btnDuplicateClick
      end
      object btnExport: TRzButton
        Left = 5
        Top = 35
        Width = 55
        Caption = 'Export'
        TabOrder = 3
        OnClick = btnExportClick
      end
      object btnImport: TRzButton
        Left = 64
        Top = 35
        Width = 55
        Caption = 'Import'
        TabOrder = 4
        OnClick = btnImportClick
      end
      object btnBulkImport: TRzButton
        Left = 123
        Top = 35
        Width = 82
        Caption = 'Import All...'
        TabOrder = 5
        OnClick = btnBulkImportClick
      end
    end
    object vstTemplateList: TVirtualStringTree
      AlignWithMargins = True
      Left = 5
      Top = 18
      Width = 250
      Height = 454
      Align = alClient
      DefaultNodeHeight = 17
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = []
      Header.AutoSizeIndex = 0
      Header.Height = 17
      ParentFont = False
      TabOrder = 1
      TreeOptions.PaintOptions = [toShowButtons, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages]
      TreeOptions.SelectionOptions = [toFullRowSelect]
      OnFocusChanged = vstTemplateListFocusChanged
      OnFocusChanging = vstTemplateListFocusChanging
      OnFreeNode = vstTemplateListFreeNode
      OnGetCellText = vstTemplateListGetCellText
      OnPaintText = vstTemplateListPaintText
      OnGetNodeDataSize = vstTemplateListGetNodeDataSize
      Touch.InteractiveGestures = [igPan, igPressAndTap]
      Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
      Columns = <
        item
          Options = [coAllowClick, coEnabled, coParentBidiMode, coParentColor, coResizable, coVisible, coAutoSpring, coSmartResize, coAllowFocus, coStyleColor]
          Position = 0
          Text = 'Template'
          Width = 250
        end>
    end
  end
  object pnlRight: TRzPanel
    Left = 263
    Top = 0
    Width = 280
    Height = 548
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object pnlDetails: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 270
      Height = 150
      Align = alTop
      BorderOuter = fsFlatRounded
      TabOrder = 0
      object lblName: TRzLabel
        Left = 6
        Top = 4
        Width = 31
        Height = 13
        Caption = 'Name:'
        Transparent = True
      end
      object lblCategory: TRzLabel
        Left = 6
        Top = 46
        Width = 49
        Height = 13
        Caption = 'Category:'
        Transparent = True
      end
      object lblDescription: TRzLabel
        Left = 6
        Top = 88
        Width = 57
        Height = 13
        Caption = 'Description:'
        Transparent = True
      end
      object edtName: TRzEdit
        Left = 4
        Top = 20
        Width = 258
        Height = 21
        Text = ''
        TabOrder = 0
        OnChange = edtNameChange
      end
      object cmbCategory: TComboBox
        Left = 4
        Top = 62
        Width = 160
        Height = 21
        TabOrder = 1
        OnChange = cmbCategoryChange
      end
      object memDescription: TMemo
        Left = 4
        Top = 104
        Width = 258
        Height = 42
        ScrollBars = ssVertical
        TabOrder = 2
        OnChange = memDescriptionChange
      end
    end
    object pnlProps: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 161
      Width = 270
      Height = 350
      Align = alClient
      BorderOuter = fsFlatRounded
      TabOrder = 1
      DesignSize = (
        270
        350)
      object lblPropTitle: TRzLabel
        Left = 6
        Top = 4
        Width = 24
        Height = 13
        Caption = 'Title:'
        Transparent = True
      end
      object lblPropLevel: TRzLabel
        Left = 6
        Top = 44
        Width = 29
        Height = 13
        Caption = 'Level:'
        Transparent = True
      end
      object lblPropType: TRzLabel
        Left = 6
        Top = 116
        Width = 28
        Height = 13
        Caption = 'Type:'
        Transparent = True
      end
      object lblPropActionType: TRzLabel
        Left = 6
        Top = 256
        Width = 61
        Height = 13
        Caption = 'Action Type:'
        Transparent = True
      end
      object edtNodeTitle: TRzEdit
        Left = 4
        Top = 18
        Width = 258
        Height = 21
        Text = ''
        TabOrder = 0
        OnChange = edtNodeTitleChange
      end
      object lstNodeLevel: TListBox
        Left = 4
        Top = 58
        Width = 258
        Height = 52
        ItemHeight = 13
        TabOrder = 1
        OnClick = lstNodeLevelClick
      end
      object lstNodeType: TListBox
        Left = 4
        Top = 130
        Width = 258
        Height = 120
        ItemHeight = 13
        TabOrder = 2
        OnClick = lstNodeTypeClick
      end
      object lstNodeActionType: TListBox
        Left = 4
        Top = 270
        Width = 258
        Height = 74
        Anchors = [akLeft, akTop, akRight, akBottom]
        ItemHeight = 13
        TabOrder = 3
        OnClick = lstNodeActionTypeClick
      end
    end
    object pnlSaveBar: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 517
      Width = 270
      Height = 26
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 2
      object btnSave: TRzButton
        Left = 0
        Top = 0
        Width = 70
        Caption = 'Save'
        TabOrder = 0
        OnClick = btnSaveClick
      end
    end
  end
  object pnlCenter: TRzPanel
    Left = 546
    Top = 0
    Width = 414
    Height = 548
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 3
    object pnlTreeButtons: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 511
      Width = 404
      Height = 32
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 0
      object btnAddChild: TRzButton
        Left = 2
        Top = 0
        Width = 62
        Caption = 'Add Child'
        TabOrder = 0
        OnClick = btnAddChildClick
      end
      object btnAddSibling: TRzButton
        Left = 70
        Top = 0
        Width = 79
        Caption = 'Add Sibling'
        TabOrder = 1
        OnClick = btnAddSiblingClick
      end
      object btnMoveUp: TRzButton
        Left = 155
        Top = 0
        Width = 30
        Caption = 'Up'
        TabOrder = 2
        OnClick = btnMoveUpClick
      end
      object btnMoveDown: TRzButton
        Left = 191
        Top = 0
        Width = 49
        Caption = 'Down'
        TabOrder = 3
        OnClick = btnMoveDownClick
      end
      object btnLevelUp: TRzButton
        Left = 246
        Top = 0
        Width = 24
        Caption = '<'
        TabOrder = 4
        OnClick = btnLevelUpClick
      end
      object btnDeleteNode: TRzButton
        Left = 275
        Top = 0
        Width = 60
        Caption = 'Delete'
        TabOrder = 5
        OnClick = btnDeleteNodeClick
      end
    end
    object vstStructure: TVirtualStringTree
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 404
      Height = 500
      Align = alClient
      DefaultNodeHeight = 17
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = []
      Header.AutoSizeIndex = 0
      Header.Height = 17
      ParentFont = False
      TabOrder = 1
      TreeOptions.PaintOptions = [toShowButtons, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages]
      TreeOptions.SelectionOptions = [toFullRowSelect]
      OnFocusChanged = vstStructureFocusChanged
      OnFreeNode = vstStructureFreeNode
      OnGetCellText = vstStructureGetCellText
      OnPaintText = vstStructurePaintText
      OnGetNodeDataSize = vstStructureGetNodeDataSize
      Touch.InteractiveGestures = [igPan, igPressAndTap]
      Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
      Columns = <
        item
          Options = [coAllowClick, coEnabled, coParentBidiMode, coParentColor, coResizable, coVisible, coAutoSpring, coSmartResize, coAllowFocus, coStyleColor]
          Position = 0
          Text = 'Structure'
          Width = 400
        end>
    end
  end
end
