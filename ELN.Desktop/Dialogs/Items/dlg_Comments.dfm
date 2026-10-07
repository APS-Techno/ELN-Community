object dlgComments: TdlgComments
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Comments'
  ClientHeight = 423
  ClientWidth = 484
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
    Width = 484
    Height = 28
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 8
      Top = 6
      Width = 300
      Height = 16
      Caption = 'Discussion'
    end
    object lblCount: TLabel
      Left = 376
      Top = 6
      Width = 100
      Height = 16
      Alignment = taRightJustify
      Anchors = [akTop, akRight]
      Caption = ''
      ExplicitLeft = 376
    end
  end
  object pnlInput: TPanel
    Left = 0
    Top = 303
    Width = 484
    Height = 80
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object memoComment: TMemo
      AlignWithMargins = True
      Left = 8
      Top = 4
      Width = 388
      Height = 72
      Margins.Left = 8
      Margins.Top = 4
      Margins.Right = 80
      Margins.Bottom = 4
      Align = alClient
      ScrollBars = ssVertical
      TabOrder = 0
    end
    object btnAdd: TButton
      AlignWithMargins = True
      Left = 411
      Top = 4
      Width = 65
      Height = 72
      Margins.Left = 4
      Margins.Top = 4
      Margins.Right = 8
      Margins.Bottom = 4
      Align = alRight
      Caption = 'Post'
      TabOrder = 1
      OnClick = btnAddClick
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 383
    Width = 484
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object btnEdit: TButton
      Left = 8
      Top = 6
      Width = 75
      Height = 25
      Caption = 'Edit'
      TabOrder = 0
      OnClick = btnEditClick
    end
    object btnDelete: TButton
      Left = 88
      Top = 6
      Width = 75
      Height = 25
      Caption = 'Delete'
      TabOrder = 1
      OnClick = btnDeleteClick
    end
    object btnClose: TButton
      Left = 401
      Top = 6
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 2
    end
  end
  object lvComments: TListView
    AlignWithMargins = True
    Left = 8
    Top = 30
    Width = 468
    Height = 271
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'Date'
        Width = 120
      end
      item
        Caption = 'User'
        Width = 100
      end
      item
        Caption = 'Comment'
        Width = 230
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 3
    ViewStyle = vsReport
    OnCustomDrawItem = lvCommentsCustomDrawItem
  end
end
