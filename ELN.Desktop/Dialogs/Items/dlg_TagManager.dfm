object dlgTagManager: TdlgTagManager
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Tag Editor'
  ClientHeight = 352
  ClientWidth = 364
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 364
    Height = 28
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 8
      Top = 6
      Width = 348
      Height = 16
      Caption = 'Manage tags: add, edit, or delete'
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 312
    Width = 364
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnAddTag: TButton
      Left = 8
      Top = 6
      Width = 65
      Height = 25
      Caption = 'Add'
      TabOrder = 0
      OnClick = btnAddTagClick
    end
    object btnEditTag: TButton
      Left = 78
      Top = 6
      Width = 65
      Height = 25
      Caption = 'Edit'
      TabOrder = 1
      OnClick = btnEditTagClick
    end
    object btnDeleteTag: TButton
      Left = 148
      Top = 6
      Width = 65
      Height = 25
      Caption = 'Delete'
      TabOrder = 2
      OnClick = btnDeleteTagClick
    end
    object btnClose: TButton
      Left = 281
      Top = 6
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 3
    end
  end
  object lvTags: TListView
    AlignWithMargins = True
    Left = 8
    Top = 30
    Width = 348
    Height = 280
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'Tag'
        Width = 220
      end
      item
        Caption = 'Color'
        Width = 100
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnCustomDrawSubItem = lvTagsCustomDrawSubItem
    OnDblClick = lvTagsDblClick
    OnItemChecked = lvTagsItemChecked
  end
end
