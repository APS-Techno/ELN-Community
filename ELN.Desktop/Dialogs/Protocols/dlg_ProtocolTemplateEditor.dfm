object dlgTemplateEditor: TdlgTemplateEditor
  Left = 0
  Top = 0
  Caption = 'Template Editor'
  ClientHeight = 607
  ClientWidth = 837
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
    Left = 552
    Top = 84
    Height = 473
    MinSize = 15
    ExplicitLeft = 540
    ExplicitTop = 60
    ExplicitHeight = 368
  end
  object spltTree: TSplitter
    Left = 549
    Top = 84
    Height = 473
    MinSize = 15
    ExplicitLeft = 200
    ExplicitTop = 60
    ExplicitHeight = 368
  end
  object pnlTop: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 831
    Height = 78
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 0
    DesignSize = (
      831
      78)
    object lblName: TRzLabel
      Left = 16
      Top = 6
      Width = 31
      Height = 13
      Caption = 'Name:'
    end
    object lblDescription: TRzLabel
      Left = 230
      Top = 6
      Width = 57
      Height = 13
      Caption = 'Description:'
    end
    object lblCategory: TRzLabel
      Left = 225
      Top = 54
      Width = 49
      Height = 13
      Caption = 'Category:'
    end
    object edtName: TRzEdit
      Left = 16
      Top = 22
      Width = 200
      Height = 21
      Text = ''
      TabOrder = 0
    end
    object edtDescription: TRzEdit
      Left = 230
      Top = 22
      Width = 300
      Height = 21
      Text = ''
      TabOrder = 1
    end
    object chkActive: TCheckBox
      Left = 550
      Top = 24
      Width = 60
      Height = 14
      Caption = 'Active'
      Checked = True
      State = cbChecked
      TabOrder = 2
    end
    object btnPreview: TRzButton
      Left = 762
      Top = 17
      Width = 60
      Anchors = [akTop, akRight]
      Caption = 'Preview'
      TabOrder = 3
      OnClick = btnPreviewClick
    end
    object edtCategory: TRzEdit
      Left = 280
      Top = 49
      Width = 150
      Height = 21
      Text = ''
      TabOrder = 4
    end
    object btnTags: TRzButton
      Left = 436
      Top = 46
      Width = 160
      Caption = 'Tags... (none)'
      TabOrder = 6
      OnClick = btnTagsClick
    end
    object btnLoadExample: TRzButton
      Left = 16
      Top = 49
      Width = 97
      Height = 24
      Caption = 'Load Example...'
      TabOrder = 5
      OnClick = btnLoadExampleClick
    end
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 560
    Width = 831
    Height = 44
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    DesignSize = (
      831
      44)
    object btnOK: TRzButton
      Left = 666
      Top = 10
      Default = True
      ModalResult = 1
      Anchors = [akRight, akBottom]
      Caption = 'OK'
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TRzButton
      Left = 747
      Top = 10
      Cancel = True
      ModalResult = 2
      Anchors = [akRight, akBottom]
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object pnlTreeCol: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 87
    Width = 200
    Height = 467
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object lblTree: TRzLabel
      Left = 4
      Top = 2
      Width = 49
      Height = 13
      Caption = 'Structure:'
    end
    object tvSchema: TTreeView
      Left = 2
      Top = 2
      Width = 196
      Height = 380
      Align = alClient
      HideSelection = False
      Indent = 10
      ReadOnly = True
      TabOrder = 0
      OnChange = tvSchemaChange
      OnDeletion = tvSchemaDeletion
    end
    object pnlTreeToolbar: TRzPanel
      Left = 2
      Top = 382
      Width = 196
      Height = 83
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 1
      object btnAddSection: TRzButton
        Left = 2
        Top = 6
        Width = 58
        Caption = '+Section'
        TabOrder = 0
        OnClick = btnAddSectionClick
      end
      object btnAddRow: TRzButton
        Left = 62
        Top = 6
        Width = 42
        Caption = '+Row'
        TabOrder = 1
        OnClick = btnAddRowClick
      end
      object btnAddField: TRzButton
        Left = 106
        Top = 6
        Width = 42
        Caption = '+Field'
        TabOrder = 2
        OnClick = btnAddFieldClick
      end
      object btnDeleteSchema: TRzButton
        Left = 150
        Top = 6
        Width = 43
        Caption = 'Delete'
        TabOrder = 3
        OnClick = btnDeleteSchemaClick
      end
      object btnSchemaUp: TRzButton
        Left = 2
        Top = 35
        Width = 32
        Caption = 'Up'
        TabOrder = 4
        OnClick = btnSchemaUpClick
      end
      object btnSchemaDown: TRzButton
        Left = 36
        Top = 35
        Width = 45
        Caption = 'Down'
        TabOrder = 5
        OnClick = btnSchemaDownClick
      end
      object btnJsonToggle: TRzButton
        Left = 158
        Top = 35
        Width = 36
        Caption = 'JSON'
        TabOrder = 6
        OnClick = btnJsonToggleClick
      end
    end
    object synEditor: TSynEdit
      Left = 2
      Top = 2
      Width = 196
      Height = 380
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -14
      Font.Name = 'Consolas'
      Font.Style = []
      Font.Quality = fqClearTypeNatural
      TabOrder = 2
      Visible = False
      UseCodeFolding = False
      BookMarkOptions.LeftMargin = 1
      BookMarkOptions.Xoffset = 6
      ExtraLineSpacing = 1
      Gutter.Font.Charset = DEFAULT_CHARSET
      Gutter.Font.Color = clWindowText
      Gutter.Font.Height = -10
      Gutter.Font.Name = 'Consolas'
      Gutter.Font.Style = []
      Gutter.Font.Quality = fqClearTypeNatural
      Gutter.Bands = <
        item
          Kind = gbkMarks
          Width = 13
        end
        item
          Kind = gbkLineNumbers
        end
        item
          Kind = gbkFold
        end
        item
          Kind = gbkTrackChanges
        end
        item
          Kind = gbkMargin
          Width = 3
        end>
      Highlighter = synJsonHighlighter
      SelectedColor.Alpha = 0.400000005960464500
    end
  end
  object pnlPropsCol: TRzPanel
    AlignWithMargins = True
    Left = 209
    Top = 87
    Width = 337
    Height = 467
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 3
    object lblPropCaption: TRzLabel
      Left = 4
      Top = 2
      Width = 62
      Height = 13
      Caption = 'Properties:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblSchemaError: TRzLabel
      AlignWithMargins = True
      Left = 5
      Top = 450
      Width = 327
      Height = 12
      Align = alBottom
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGreen
      Font.Height = -10
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      Visible = False
      ExplicitLeft = 2
      ExplicitTop = 453
      ExplicitWidth = 3
    end
    object pnlCardHost: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 42
      Width = 327
      Height = 402
      Margins.Top = 40
      Align = alClient
      BorderOuter = fsNone
      TabOrder = 0
      ExplicitTop = 48
    end
  end
  object pnlPreview: TRzPanel
    AlignWithMargins = True
    Left = 558
    Top = 87
    Width = 276
    Height = 467
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 4
    object lblPreview: TRzLabel
      Left = 4
      Top = 2
      Width = 42
      Height = 13
      Caption = 'Preview:'
    end
  end
  object dlgOpenSchema: TOpenDialog
    Filter = 'JSON Files (*.json)|*.json|All Files (*.*)|*.*'
    Options = [ofHideReadOnly, ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Load Example Schema'
    Left = 1168
    Top = 852
  end
  object synJsonHighlighter: TSynJSONSyn
    Left = 996
    Top = 852
  end
end
