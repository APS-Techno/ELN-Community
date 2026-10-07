object dlgRecycleBin: TdlgRecycleBin
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Recycle Bin'
  ClientHeight = 393
  ClientWidth = 604
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
    Width = 604
    Height = 24
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 8
      Top = 4
      Width = 500
      Height = 16
      Caption = 'Deleted items. Select an item to restore or permanently delete:'
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 353
    Width = 604
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnRestore: TButton
      Left = 8
      Top = 6
      Width = 80
      Height = 25
      Caption = 'Restore'
      Enabled = False
      TabOrder = 0
      OnClick = btnRestoreClick
    end
    object btnPurge: TButton
      Left = 96
      Top = 6
      Width = 80
      Height = 25
      Caption = 'Delete'
      Enabled = False
      TabOrder = 1
      OnClick = btnPurgeClick
    end
    object btnEmpty: TButton
      Left = 184
      Top = 6
      Width = 90
      Height = 25
      Caption = 'Empty Bin'
      TabOrder = 2
      OnClick = btnEmptyClick
    end
    object btnClose: TButton
      Left = 521
      Top = 6
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 3
    end
  end
  object lvItems: TListView
    AlignWithMargins = True
    Left = 8
    Top = 26
    Width = 588
    Height = 323
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'Title'
        Width = 180
      end
      item
        Caption = 'Level'
        Width = 80
      end
      item
        Caption = 'Deleted Date'
        Width = 130
      end
      item
        Caption = 'Project / Folder'
        Width = 180
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnSelectItem = lvItemsSelectItem
  end
end
