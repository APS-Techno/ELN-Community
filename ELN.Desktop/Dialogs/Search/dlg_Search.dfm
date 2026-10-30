object dlgSearch: TdlgSearch
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Search'
  ClientHeight = 460
  ClientWidth = 700
  Color = clBtnFace
  Constraints.MinHeight = 240
  Constraints.MinWidth = 560
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poMainFormCenter
  PopupMode = pmExplicit
  OnClose = FormClose
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnResize = FormResize
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 700
    Height = 68
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblCount: TLabel
      Left = 492
      Top = 43
      Width = 200
      Height = 15
      Alignment = taRightJustify
      Anchors = [akTop, akRight]
      AutoSize = False
    end
    object edSearch: TComboBox
      Left = 8
      Top = 8
      Width = 602
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      AutoComplete = True
      TabOrder = 0
      TextHint = 'Search (at least 2 characters)'
      OnKeyPress = edSearchKeyPress
    end
    object btnSearch: TButton
      Left = 618
      Top = 7
      Width = 74
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Search'
      TabOrder = 1
      OnClick = btnSearchClick
    end
    object chkMeaning: TCheckBox
      Left = 8
      Top = 41
      Width = 140
      Height = 19
      Caption = 'Search by meaning'
      TabOrder = 2
      OnClick = chkMeaningClick
    end
    object chkRerank: TCheckBox
      Left = 156
      Top = 41
      Width = 140
      Height = 19
      Caption = 'Rerank results'
      TabOrder = 3
      OnClick = chkRerankClick
    end
  end
  object pnlFilters: TPanel
    Left = 0
    Top = 68
    Width = 700
    Height = 30
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    object cbProject: TComboBox
      AlignWithMargins = True
      Left = 8
      Top = 3
      Width = 170
      Height = 23
      Margins.Left = 8
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      Style = csDropDownList
      TabOrder = 0
    end
    object cbItemType: TComboBox
      AlignWithMargins = True
      Left = 186
      Top = 3
      Width = 120
      Height = 23
      Margins.Left = 8
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      Style = csDropDownList
      ItemIndex = 0
      TabOrder = 1
      Text = 'Any type'
      Items.Strings = (
        'Any type'
        'Synthesis'
        'Treatment'
        'Measurement'
        'Testing'
        'Characterization'
        'Computing'
        'Specimen'
        'Model'
        'Other'
        'Wiki')
    end
    object lblCreated: TLabel
      AlignWithMargins = True
      Left = 314
      Top = 3
      Width = 48
      Height = 24
      Margins.Left = 8
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      AutoSize = False
      Caption = 'Created'
      Layout = tlCenter
    end
    object dtpFrom: TDateTimePicker
      AlignWithMargins = True
      Left = 362
      Top = 3
      Width = 104
      Height = 24
      Margins.Left = 0
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      Date = 46000.000000000000000000
      Time = 0.500000000000000000
      ShowCheckbox = True
      TabOrder = 2
    end
    object lblTo: TLabel
      AlignWithMargins = True
      Left = 466
      Top = 3
      Width = 22
      Height = 24
      Margins.Left = 0
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      Alignment = taCenter
      AutoSize = False
      Caption = 'to'
      Layout = tlCenter
    end
    object dtpTo: TDateTimePicker
      AlignWithMargins = True
      Left = 488
      Top = 3
      Width = 104
      Height = 24
      Margins.Left = 0
      Margins.Top = 3
      Margins.Right = 0
      Margins.Bottom = 3
      Align = alLeft
      Date = 46000.000000000000000000
      Time = 0.500000000000000000
      ShowCheckbox = True
      TabOrder = 3
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 392
    Width = 700
    Height = 68
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object lblStatus: TLabel
      AlignWithMargins = True
      Left = 462
      Top = 3
      Width = 230
      Height = 54
      Margins.Left = 8
      Margins.Right = 8
      Margins.Bottom = 8
      Align = alRight
      Alignment = taRightJustify
      AutoSize = False
      EllipsisPosition = epEndEllipsis
      Layout = tlTop
      WordWrap = True
    end
    object lblDetail: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 3
      Width = 446
      Height = 54
      Margins.Left = 8
      Margins.Right = 0
      Margins.Bottom = 8
      Align = alClient
      AutoSize = False
      Layout = tlTop
      WordWrap = True
    end
  end
  object ListView: TListView
    AlignWithMargins = True
    Left = 8
    Top = 100
    Width = 684
    Height = 362
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'ID'
        Width = 55
      end
      item
        Caption = 'Type'
        Width = 85
      end
      item
        Caption = 'Name'
        Width = 200
      end
      item
        Caption = 'Location'
        Width = 220
      end
      item
        AutoSize = True
        Caption = 'Matched In'
      end>
    GridLines = True
    ReadOnly = True
    RowSelect = True
    ShowHint = False
    TabOrder = 3
    ViewStyle = vsReport
    OnDblClick = ListViewDblClick
    OnKeyDown = ListViewKeyDown
    OnSelectItem = ListViewSelectItem
  end
  object tmrStatus: TTimer
    Enabled = False
    Interval = 500
    OnTimer = tmrStatusTimer
    Left = 600
    Top = 200
  end
  object tmrNav: TTimer
    Enabled = False
    Interval = 250
    OnTimer = tmrNavTimer
    Left = 640
    Top = 200
  end
end
