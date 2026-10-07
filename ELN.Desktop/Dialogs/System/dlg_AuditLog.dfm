object dlgAuditLog: TdlgAuditLog
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Audit Log'
  ClientHeight = 520
  ClientWidth = 860
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 860
    Height = 40
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblFrom: TLabel
      Left = 8
      Top = 12
      Width = 30
      Height = 20
      Caption = 'From:'
    end
    object lblTo: TLabel
      Left = 152
      Top = 12
      Width = 20
      Height = 20
      Caption = 'To:'
    end
    object lblEntity: TLabel
      Left = 284
      Top = 12
      Width = 35
      Height = 20
      Caption = 'Entity:'
    end
    object lblOp: TLabel
      Left = 422
      Top = 12
      Width = 25
      Height = 20
      Caption = 'Op:'
    end
    object lblUser: TLabel
      Left = 538
      Top = 12
      Width = 30
      Height = 20
      Caption = 'User:'
    end
    object dtpFrom: TDateTimePicker
      Left = 42
      Top = 8
      Width = 100
      Height = 24
      TabOrder = 0
    end
    object dtpTo: TDateTimePicker
      Left = 172
      Top = 8
      Width = 100
      Height = 24
      TabOrder = 1
    end
    object cmbEntityType: TComboBox
      Left = 322
      Top = 8
      Width = 90
      Height = 23
      Style = csDropDownList
      TabOrder = 2
    end
    object cmbOperation: TComboBox
      Left = 448
      Top = 8
      Width = 80
      Height = 23
      Style = csDropDownList
      TabOrder = 3
    end
    object cmbUser: TComboBox
      Left = 572
      Top = 8
      Width = 140
      Height = 23
      Style = csDropDownList
      TabOrder = 4
    end
    object btnRefresh: TButton
      Left = 722
      Top = 8
      Width = 70
      Height = 24
      Caption = 'Refresh'
      TabOrder = 5
      OnClick = btnRefreshClick
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 480
    Width = 860
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnClose: TButton
      Left = 772
      Top = 8
      Width = 80
      Height = 26
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 0
    end
  end
  object ListView: TListView
    AlignWithMargins = True
    Left = 8
    Top = 42
    Width = 844
    Height = 436
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'Timestamp'
        Width = 130
      end
      item
        Caption = 'Entity Type'
        Width = 80
      end
      item
        Caption = 'Entity ID'
        Width = 60
      end
      item
        Caption = 'Operation'
        Width = 70
      end
      item
        Caption = 'User'
        Width = 120
      end
      item
        Caption = 'Description'
        Width = 340
      end>
    GridLines = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
  end
end
