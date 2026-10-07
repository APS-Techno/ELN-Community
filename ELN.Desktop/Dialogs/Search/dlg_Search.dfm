object dlgSearch: TdlgSearch
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Search'
  ClientHeight = 460
  ClientWidth = 700
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 700
    Height = 40
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblCount: TLabel
      Left = 536
      Top = 12
      Width = 150
      Height = 20
      Anchors = [akTop, akRight]
      Caption = ''
    end
    object edSearch: TEdit
      Left = 8
      Top = 8
      Width = 440
      Height = 24
      TabOrder = 0
      TextHint = 'Type to search (min 2 chars)...'
      OnKeyPress = edSearchKeyPress
    end
    object btnSearch: TButton
      Left = 456
      Top = 8
      Width = 70
      Height = 24
      Caption = 'Search'
      Default = True
      TabOrder = 1
      OnClick = btnSearchClick
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 420
    Width = 700
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnGoTo: TButton
      Left = 520
      Top = 8
      Width = 80
      Height = 26
      Anchors = [akTop, akRight]
      Caption = 'Go to Item'
      TabOrder = 0
      OnClick = btnGoToClick
    end
    object btnClose: TButton
      Left = 608
      Top = 8
      Width = 80
      Height = 26
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 1
    end
  end
  object ListView: TListView
    AlignWithMargins = True
    Left = 8
    Top = 42
    Width = 684
    Height = 376
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'ID'
        Width = 60
      end
      item
        Caption = 'Type'
        Width = 70
      end
      item
        Caption = 'Name'
        Width = 200
      end
      item
        Caption = 'Location'
        Width = 250
      end
      item
        Caption = 'Matched In'
        Width = 100
      end>
    GridLines = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnDblClick = ListViewDblClick
  end
end
